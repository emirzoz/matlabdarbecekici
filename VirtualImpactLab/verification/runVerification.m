function summary = runVerification(caseNames,opts)
% Verify the MATLAB modal database and impact engine against Abaqus 2024.
%
%   summary = runVerification            % all cases
%   summary = runVerification("block")   % one case
%
% For each part:
%  A. Same mesh   - the MATLAB mesh, material and clamp are exported to
%     Abaqus (C3D10). Compares frequencies, mode shapes (MAC), the modal FRF
%     (*STEADY STATE DYNAMICS) and a half-sine hammer impact (*MODAL DYNAMIC).
%     This isolates the MATLAB solver, normalization, DOF mapping, FRF and
%     time integration from discretization differences.
%  B. Independent - Abaqus/CAE imports the STEP file and meshes it itself.
%     Checks CAD import, units, face selection and meshing end to end.
% Writes results/<case>/ figures and results/VERIFICATION.md. Desktop only.
arguments
    caseNames string = string.empty
    opts.Independent (1,1) logical = true
    opts.Root (1,1) string = fileparts(mfilename('fullpath'))
end
app = fileparts(opts.Root); addpath(app); addpath(opts.Root);
cases = verificationCases(fullfile(fileparts(app),'imports'));
if ~isempty(caseNames), cases = cases(ismember([cases.name],caseNames)); end
outRoot = fullfile(opts.Root,'results'); if ~isfolder(outRoot), mkdir(outRoot); end
summary = struct([]);
for k = 1:numel(cases)
    cs = cases(k); folder = fullfile(outRoot,cs.name);
    if ~isfolder(folder), mkdir(folder); end
    fprintf('\n===== %s =====\n',cs.name);
    try
        r = verifyCase(cs,folder,opts);
    catch err
        fprintf(2,'%s\n',getReport(err,'extended','hyperlinks','off'));
        r = struct('name',cs.name,'error',err.message);
    end
    save(fullfile(folder,'verification.mat'),'r');
    summary = appendStruct(summary,r);
end
writeReport(summary,fullfile(outRoot,'VERIFICATION.md'));
save(fullfile(outRoot,'summary.mat'),'summary');
end

function cases = verificationCases(imports)
mk = @(name,file,hmax,minModes) struct('name',string(name),'file',string(file),'hmax',hmax,'minModes',minModes);
cases = [mk("demo-beam","",0.006,8)
         mk("block",fullfile(imports,'block.step'),0.004,10)
         mk("bearing-housing",fullfile(imports,'bearing-housing.step'),0.006,10)
         mk("corner-bracket-2020",fullfile(imports,'corner-bracket-2020.step'),0.0015,10)];
end

function r = verifyCase(cs,folder,opts)
r = struct('name',cs.name,'error',"");
t0 = tic;
if cs.file == ""
    [g,c,mi] = vil.createDemoBeam(cs.hmax);
    info = struct('fileUnits',"m",'span',[c.L c.width c.height]);
else
    [g,info] = vil.importCAD(cs.file);
    [g,mi] = vil.meshPart(g,cs.hmax);
    V = g.Mesh.Nodes;
    lo = min(V,[],2); hi = max(V,[],2); mid = (lo+hi)/2;
    % Clamp the face under the part centre at its lowest Z (base mount).
    c = struct('E',210e9,'nu',0.3,'rho',7800,'rangeHz',[1 2000], ...
        'fixedFaces',nearestFace(g,[mid(1) mid(2) lo(3)-1e-6]));
end
r.fileUnits = info.fileUnits; r.span = info.span;
db = vil.solveModes(g,c,MeshInfo=mi,MinModes=cs.minModes);
r.matlabSolveSeconds = toc(t0);
r.numNodes = size(db.nodes,2); r.numModes = numel(db.omega);
r.fromTessellation = isfield(mi,'fromTessellation') && mi.fromTessellation;
r.totalMass = db.totalMass; r.bandHz = db.config.rangeHz;
fprintf('MATLAB: %d nodes, %d modes up to %.0f Hz, %.1f s\n',r.numNodes,r.numModes,max(db.frequencyHz),r.matlabSolveSeconds);

[hammer,sensor] = chooseProbes(db);
fmax = max(db.frequencyHz);
fs = 1000*ceil(4*fmax/1000);
p = struct('peakForce',100,'contactDuration',max(2e-4,25/fs),'duration',0.02,'fs',fs,'zeta',0.02);
r.hammer = hammer; r.sensor = sensor; r.impact = p;

% ---- A. same mesh -------------------------------------------------------
inp = fullfile(folder,"samemesh.inp");
vil.exportAbaqus(db,inp,Hammer=hammer,Sensor=sensor,Zeta=p.zeta,Impact=p, ...
    MaxHz=db.config.rangeHz(2),FRFRangeHz=[1 0.98*fmax]);
t1 = tic; abq = runAbaqusJob(inp); r.abaqusSameMeshSeconds = toc(t1);
assert(isequal(abq.nodes(:),(1:r.numNodes).'),'vil:Labels','Abaqus node labels differ from MATLAB IDs.');
T = vil.compareModes(db.frequencyHz,db.Phi,abq.frequencyHz,abq.Phi);
r.sameMesh.modes = T; r.sameMesh.numAbaqusModes = numel(abq.frequencyHz);
dirIndex = find('XYZ'==sensor{2});
% Both solvers truncate at the same modes, so the cutoff warning is expected.
w = warning('off','vil:Truncation'); restoreWarning = onCleanup(@()warning(w));
frf = vil.calculateFRF(db,hammer,sensor,abq.ssd.frequencyHz,p.zeta);
Habq = abq.ssd.U(:,dirIndex).'; Hmat = frf.displacement;
r.sameMesh.frfError = norm(Hmat-Habq)/norm(Habq);
r.sameMesh.frfMagErrorDb = max(abs(20*log10(abs(Hmat)./abs(Habq))));
resp = vil.simulateImpact(db,hammer,sensor,p);
aAbq = interp1(abq.impact.time,abq.impact.acceleration,resp.time,'linear',NaN);
ok = ~isnan(aAbq);
r.sameMesh.impactError = norm(resp.acceleration(ok)-aAbq(ok))/norm(aAbq(ok));
r.sameMesh.peakAccel = [max(abs(resp.acceleration)) max(abs(aAbq))];
fprintf('Same mesh: max|df| %.4f%%, min MAC %.4f, FRF err %.2e, impact err %.2e\n', ...
    max(abs(T.Error_pct)),min(T.SubspaceMAC),r.sameMesh.frfError,r.sameMesh.impactError);
plotSameMesh(folder,cs.name,db,abq,frf,Habq,resp,aAbq,T);

% ---- B. independent Abaqus/CAE model from the STEP ---------------------
if opts.Independent && cs.file ~= ""
    scaleMap = dictionary(["mm","cm","m","inch","in"],[1e-3 1e-2 1 0.0254 0.0254]);
    t2 = tic;
    cae = runAbaqusCAE(cs.file,db,folder,"independent",ScaleToMetres=scaleMap(info.fileUnits), ...
        Hmax=mi.hmaxUsed,MaxHz=1.05*fmax);
    r.abaqusIndependentSeconds = toc(t2);
    % Map each Abaqus node to its nearest MATLAB node for MAC.
    nearest = dsearchn(db.nodes.',cae.coordinates);
    n = r.numNodes; na = numel(nearest);
    rows = [nearest; nearest+n; nearest+2*n];
    TI = vil.compareModes(db.frequencyHz,db.Phi(rows,:),cae.frequencyHz,cae.Phi);
    r.independent.modes = TI; r.independent.info = cae.info;
    r.independent.mappingDistance = max(vecnorm(db.nodes(:,nearest).'-cae.coordinates,2,2));
    r.independent.numAbaqusNodes = na;
    fprintf('Independent: Abaqus %d nodes, bbox %s, max|df| %.3f%%, min MAC %.3f\n', ...
        cae.info.numNodes,mat2str(diff(cae.info.bbox).',4),max(abs(TI.Error_pct)),min(TI.SubspaceMAC));
    plotIndependent(folder,cs.name,TI);
end
if cs.name == "demo-beam"
    I = c.width*c.height^3/12;
    r.beamTheoryHz = 1.875104068711961^2/(2*pi*c.L^2)*sqrt(c.E*I/(c.rho*c.width*c.height));
end
end

function [hammer,sensor] = chooseProbes(db)
% Hammer: top surface node farthest from the clamp. Sensor: the surface
% node farthest from the hammer, both measured in Z and Y respectively so
% the comparison includes a cross-direction transfer FRF.
s = db.surfaceNodes; X = db.nodes(:,s);
clamp = mean(db.nodes(:,db.fixedNodes),2);
free = s(~ismember(s,db.fixedNodes));
Xf = db.nodes(:,free);
[~,i] = max(vecnorm(Xf-clamp)); hammer = {free(i),'Z'};
[~,j] = max(vecnorm(Xf-db.nodes(:,free(i)))); sensor = {free(j),'Y'};
if isempty(X), error('vil:Surface','No surface nodes.'); end
end

function plotSameMesh(folder,name,db,abq,frf,Habq,resp,aAbq,T)
f = figure('Visible','off','Position',[0 0 1400 900],'Color','w');
tl = tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('%s - MATLAB vs Abaqus on the same mesh',name),'Interpreter','none');
ax = nexttile(tl);
semilogy(ax,frf.frequencyHz,abs(frf.displacement),'-','LineWidth',1.6,'DisplayName','MATLAB'); hold(ax,'on');
semilogy(ax,abq.ssd.frequencyHz,abs(Habq),'--','LineWidth',1.2,'DisplayName','Abaqus SSD');
xlabel(ax,'Frequency (Hz)'); ylabel(ax,'|Receptance| (m/N)'); legend(ax,'Location','best'); grid(ax,'on');
ax = nexttile(tl);
plot(ax,frf.frequencyHz,angle(frf.displacement)*180/pi,'-','LineWidth',1.6); hold(ax,'on');
plot(ax,abq.ssd.frequencyHz,angle(Habq)*180/pi,'--','LineWidth',1.2);
xlabel(ax,'Frequency (Hz)'); ylabel(ax,'Phase (deg)'); grid(ax,'on');
ax = nexttile(tl);
plot(ax,1e3*resp.time,resp.acceleration,'-','LineWidth',1.4,'DisplayName','MATLAB'); hold(ax,'on');
plot(ax,1e3*resp.time,aAbq,'--','LineWidth',1.1,'DisplayName','Abaqus modal dynamic');
xlabel(ax,'Time (ms)'); ylabel(ax,'Sensor acceleration (m/s^2)'); legend(ax,'Location','best'); grid(ax,'on');
ax = nexttile(tl);
imagesc(ax,T.Properties.UserData.mac); axis(ax,'image'); colorbar(ax); clim(ax,[0 1]);
xlabel(ax,'Abaqus mode'); ylabel(ax,'MATLAB mode'); title(ax,'MAC matrix');
exportgraphics(f,fullfile(folder,'samemesh.png'),'Resolution',110); close(f);
end

function plotIndependent(folder,name,T)
f = figure('Visible','off','Position',[0 0 900 420],'Color','w');
tl = tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
title(tl,sprintf('%s - MATLAB vs independent Abaqus/CAE model',name),'Interpreter','none');
ax = nexttile(tl); bar(ax,T.Error_pct); xlabel(ax,'MATLAB mode'); ylabel(ax,'Frequency error (%)'); grid(ax,'on');
ax = nexttile(tl); bar(ax,T.SubspaceMAC); ylim(ax,[0 1]); xlabel(ax,'MATLAB mode'); ylabel(ax,'MAC'); grid(ax,'on');
exportgraphics(f,fullfile(folder,'independent.png'),'Resolution',110); close(f);
end

function s = appendStruct(s,r)
if isempty(s), s = r; return; end
fields = union(fieldnames(s),fieldnames(r));
for f = fields.'
    if ~isfield(s,f{1}), [s.(f{1})] = deal([]); end
    if ~isfield(r,f{1}), r.(f{1}) = []; end
end
s(end+1) = orderfields(r,s(1));
end

function writeReport(summary,file)
L = ["# Verification against Abaqus 2024", "", ...
    "Generated by `verification/runVerification.m` on " + string(datetime('now','Format','yyyy-MM-dd HH:mm')) + ".", ...
    "Material for all parts: E = 210 GPa, nu = 0.3, rho = 7800 kg/m^3. Damping 2% of critical in every mode.", ""];
L = [L, "## Summary", "", ...
    "| Case | Nodes | Modes | Same mesh max \|df\| (%) | Same mesh min MAC | FRF rel. error | Impact rel. error | Independent max \|df\| (%) | Independent min MAC |", ...
    "|---|---|---|---|---|---|---|---|---|"];
for r = summary(:).'
    if strlength(string(r.error)) > 0
        L(end+1) = sprintf("| %s | failed: %s | | | | | | | |",r.name,r.error); continue
    end
    ind = ["n/a","n/a"];
    if isfield(r,'independent') && ~isempty(r.independent)
        ind = [sprintf("%.2f",max(abs(r.independent.modes.Error_pct))),sprintf("%.3f",min(r.independent.modes.SubspaceMAC))];
    end
    L(end+1) = sprintf("| %s | %d | %d | %.4f | %.4f | %.2e | %.2e | %s | %s |",r.name,r.numNodes,r.numModes, ...
        max(abs(r.sameMesh.modes.Error_pct)),min(r.sameMesh.modes.SubspaceMAC),r.sameMesh.frfError, ...
        r.sameMesh.impactError,ind(1),ind(2));
end
for r = summary(:).'
    if strlength(string(r.error)) > 0, continue, end
    L = [L, "", "## " + r.name, "", sprintf("Size %s m (file units: %s). Meshed mass %.4g kg. Band %.0f-%.0f Hz. Hammer node %d (%s), sensor node %d (%s).", ...
        mat2str(r.span,4),r.fileUnits,r.totalMass,r.bandHz(1),r.bandHz(2),r.hammer{1},r.hammer{2},r.sensor{1},r.sensor{2})]; %#ok<AGROW>
    if r.fromTessellation
        L(end+1) = "MATLAB could not mesh the CAD B-rep, so the part was rebuilt from its surface tessellation (curved faces are faceted). The independent Abaqus model uses the exact CAD."; %#ok<AGROW>
    end
    if isfield(r,'beamTheoryHz') && ~isempty(r.beamTheoryHz)
        L(end+1) = sprintf("Euler-Bernoulli first bending mode: %.3f Hz; MATLAB: %.3f Hz (%.3f%%).",r.beamTheoryHz, ...
            r.sameMesh.modes.MATLAB_Hz(1),100*(r.sameMesh.modes.MATLAB_Hz(1)/r.beamTheoryHz-1)); %#ok<AGROW>
    end
    L = [L, "", "![same mesh](" + r.name + "/samemesh.png)", "", modeTable(r)]; %#ok<AGROW>
    if isfield(r,'independent') && ~isempty(r.independent)
        L = [L, "", "![independent](" + r.name + "/independent.png)"]; %#ok<AGROW>
    end
end
writelines(L,file);
end

function L = modeTable(r)
T = r.sameMesh.modes;
hasInd = isfield(r,'independent') && ~isempty(r.independent);
L = ["| Mode | MATLAB (Hz) | Abaqus same mesh (Hz) | Error (%) | MAC |"; "|---|---|---|---|---|"];
if hasInd
    L = L + [" Abaqus/CAE (Hz) | Error (%) | MAC |"; "---|---|---|"];
end
L = L.';
for i = 1:height(T)
    row = sprintf("| %d | %.2f | %.2f | %.4f | %.4f |",i,T.MATLAB_Hz(i),T.Ref_Hz(i),T.Error_pct(i),T.SubspaceMAC(i));
    if hasInd
        TI = r.independent.modes;
        row = row + sprintf(" %.2f | %.3f | %.3f |",TI.Ref_Hz(i),TI.Error_pct(i),TI.SubspaceMAC(i));
    end
    L(end+1) = row; %#ok<AGROW>
end
end
