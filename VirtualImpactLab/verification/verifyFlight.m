function T = verifyFlight(cases)
% Abaqus check of the clamp-motion model on the same mesh: transmissibility
% (*STEADY STATE DYNAMICS with *BASE MOTION) and random response
% (*RANDOM RESPONSE). Desktop only; needs Abaqus. Writes results/FLIGHT.md.
arguments
    cases = ["demo" "bearing"]
end
here = fileparts(mfilename('fullpath')); app = fileparts(here);
addpath(app,here);
imports = fullfile(fileparts(app),'imports');
psd = [10 0.001; 40 0.01; 500 0.01; 2000 0.0025];        % g^2/Hz, same shape as the UI example
g0 = 9.80665; zeta = 0.02; axis = 3;
rows = cell(numel(cases),6);
for k = 1:numel(cases)
    db = model(cases(k),imports);
    folder = fullfile(here,'results','flight',cases(k));
    if ~isfolder(folder), mkdir(folder); end
    cand = db.surfaceNodes(~ismember(db.surfaceNodes,db.fixedNodes));
    clamp = mean(db.nodes(:,db.fixedNodes),2);
    [~,i] = max(vecnorm(db.nodes(:,cand)-clamp)); node = cand(i);
    inp = fullfile(folder,'flight.inp');
    vil.exportAbaqus(db,inp,'Hammer',{node,'Z'},'Sensor',{node,'Z'},'Zeta',zeta, ...
        'FRFRangeHz',[10 0.9*max(db.frequencyHz)],'FRFPointsPerInterval',15, ...
        'BaseAxis',axis,'BasePsd',[psd(:,1) psd(:,2)*g0^2]);
    abq = runAbaqusJob(string(inp));
    f = abq.ssdbase.frequencyHz; Ta = abq.ssdbase.value(:,3);
    Tm = vil.baseTransmissibility(db,axis,{node,'Z'},f,zeta);
    % Abaqus reports data + conjugate parts; compare magnitudes and complex shape.
    magErr = norm(abs(Ta)-abs(Tm))/norm(abs(Tm));

    fig = figure('Visible','off','Position',[0 0 900 420]); try, theme(fig,'light'); catch, end
    loglog(f,abs(Tm),'-',f,abs(Ta),'o','MarkerSize',3); grid on
    xlabel('Frequency (Hz)'); ylabel('|Transmissibility|'); legend('MATLAB','Abaqus','Location','best');
    title(sprintf('%s: clamp motion along Z, same mesh',cases(k)));
    exportgraphics(fig,fullfile(folder,'transmissibility.png'),'Resolution',130); close(fig);

    [rmsA,rmsM,note] = randomCheck(db,abq,node,psd,g0,zeta,axis);
    rows(k,:) = {char(cases(k)),numel(db.omega),numel(f),magErr,rmsM,rmsA};
    fprintf('%s: transmissibility error %.2e; random %.4g g rms MATLAB, %.4g g rms Abaqus %s\n',cases(k),magErr,rmsM,rmsA,note);
end
T = cell2table(rows,'VariableNames',{'Case','Modes','Lines','TransmissibilityError','RandomRms_MATLAB_g','RandomRms_Abaqus_g'});
lines = ["# Clamp-motion check against Abaqus 2024","", ...
    "Same mesh, damping 2 %, clamp shaken along Z, monitor at the free point farthest from the clamp.", ...
    "PSD (the example shape in the app): 10 Hz 0.001, 40 Hz 0.01, 500 Hz 0.01, 2000 Hz 0.0025 g²/Hz.","", ...
    "| Case | Modes | Lines | Transmissibility rel. error | Random MATLAB (g rms) | Random Abaqus (g rms) |","|---|---|---|---|---|---|"];
for k = 1:height(T)
    lines(end+1) = sprintf('| %s | %d | %d | %.2e | %.4g | %.4g |',T.Case{k},T.Modes(k),T.Lines(k), ...
        T.TransmissibilityError(k),T.RandomRms_MATLAB_g(k),T.RandomRms_Abaqus_g(k)); %#ok<AGROW>
end
writelines(lines,fullfile(here,'results','FLIGHT.md'));
end

function [rmsA,rmsM,note] = randomCheck(db,abq,node,psd,g0,zeta,axis)
note = "";
f = struct('rpm',100,'rpmRange',[100 100],'order',1,'amplitudeG',0,'psd',psd,'axis',axis, ...
    'zeta',zeta,'monitor',{{node,'Z'}},'marginPct',10);
r = vil.flightResponse(db,f); rmsM = r.outputRmsG;
rmsA = NaN;
if isfield(abq,'random') && ~isempty(abq.random.frequencyHz)
    rmsA = abs(abq.random.value(end,3))/g0;
else
    note = "(no Abaqus random output)";
end
end

function db = model(name,imports)
c = struct('E',210e9,'nu',0.3,'rho',7800,'rangeHz',[0 0],'source',name);
switch name
    case "demo"
        [g,cfg,mi] = vil.createDemoBeam(0.008);
        c.fixedFaces = cfg.fixedFaces;
        db = vil.solveModes(g,c,MinModes=30,MeshInfo=mi);
    case "bearing"
        g = vil.importCAD(fullfile(imports,'bearing-housing.step'));
        [g,mi] = vil.meshPart(g,0.006);
        X = g.Mesh.Nodes;
        c.fixedFaces = nearestFace(g,[mean(X(1,:)) mean(X(2,:)) min(X(3,:))]);
        db = vil.solveModes(g,c,MinModes=30,MeshInfo=mi);
end
end
