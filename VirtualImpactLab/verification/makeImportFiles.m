function T = makeImportFiles(studyRoot)
% Write the solver input files in imports/ that the app opens with
% "Import Abaqus / Ansys model…", and check each by importing and solving it.
%   imports/antenna_carrier/reference_0.5kg_abaqus.inp   study file, *INCLUDE resolved
%   imports/antenna_carrier/gyroid_r5_c10_t08_0.5kg_abaqus.inp   (same)
%   imports/antenna_carrier/reference_0.5kg_ansys.cdb    written by vil.exportAnsys
%   imports/demo-beam-tipmass_abaqus.inp / _ansys.cdb    demo cantilever + 0.5 kg tip mass
% studyRoot: the Yorulma folder (antenna-carrier study).
arguments
    studyRoot (1,1) string = "C:/Users/Emir Yusuf Uytun/Documents/BAYKAR/Yorulma"
end
here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));
imp = fullfile(fileparts(fileparts(here)),'imports');
ac = fullfile(imp,'antenna_carrier');
rows = {};

% Study files: one self-contained .inp each.
for name = ["reference" "gyroid_r5_c10_t08"]
    src = fullfile(studyRoot,'abaqus','hollow',name,name+"_modal.inp");
    out = fullfile(ac,name+"_0.5kg_abaqus.inp");
    flatten(src,out);
    stored = vil.loadProject(fullfile(studyRoot,'variants_hollow','projects',name+"_VIL.mat"));
    db = solveFile(out);
    rows(end+1,:) = {string(out),db.frequencyHz(1),stored.frequencyHz(1),numel(db.fixedNodes),numel(db.payload.nodes)}; %#ok<AGROW>
    if name == "reference"
        cdb = fullfile(ac,"reference_0.5kg_ansys.cdb");
        vil.exportAnsys(db,cdb);
        d2 = solveFile(cdb);
        rows(end+1,:) = {string(cdb),d2.frequencyHz(1),stored.frequencyHz(1),numel(d2.fixedNodes),numel(d2.payload.nodes)}; %#ok<AGROW>
    end
end

% Demo cantilever, clamped at X = -150 mm, 0.5 kg on the X = +150 mm end.
[g,c,mi] = vil.createDemoBeam(0.01);
tip = vil.selectNodes(g.Mesh.Nodes,g.Mesh.Elements,mi.surface,struct('method',"plane",'axis',1,'positionMm',150,'toleranceMm',1e-3));
c.payload = struct('massKg',0.5,'nodes',tip);
ref = vil.solveModes(g,c,MeshInfo=mi,MinModes=12);
fa = fullfile(imp,"demo-beam-tipmass_abaqus.inp"); vil.exportAbaqus(ref,fa);
fb = fullfile(imp,"demo-beam-tipmass_ansys.cdb"); vil.exportAnsys(ref,fb);
for f = [string(fa) string(fb)]
    db = solveFile(f);
    rows(end+1,:) = {f,db.frequencyHz(1),ref.frequencyHz(1),numel(db.fixedNodes),numel(db.payload.nodes)}; %#ok<AGROW>
end
T = cell2table(rows,'VariableNames',{'File','f1_Hz','Reference_f1_Hz','SupportNodes','PayloadNodes'});
T.Diff_pct = 100*(T.f1_Hz./T.Reference_f1_Hz-1);
disp(T);
assert(all(abs(T.Diff_pct) < 1e-7),'An import file does not reproduce its reference.');
end

function db = solveFile(f)
[g,~,mi,m] = vil.importModel(f);
c = struct('E',m.E,'nu',m.nu,'rho',m.rho,'boundary',m.boundary,'fixedNodes',m.fixedNodes, ...
    'payload',struct('massKg',m.payload.massKg,'nodes',m.payload.nodes,'weights',m.payload.weights));
n = 8; if isfinite(m.nModes), n = m.nModes; end
db = vil.solveModes(g,c,MeshInfo=mi,MinModes=n);
end

function flatten(src,out)
% Copy an input file with its *INCLUDE files written in place.
txt = splitlines(string(fileread(src)));
k = find(startsWith(strtrim(txt),"*INCLUDE",'IgnoreCase',true));
for j = numel(k):-1:1
    tok = regexp(txt(k(j)),'(?i)input\s*=\s*"?([^",]+)"?','tokens','once');
    f = strtrim(tok(1));
    if ~isfile(f), [~,b,e] = fileparts(f); f = fullfile(fileparts(src),b+e); end
    inc = splitlines(string(fileread(f)));
    txt = [txt(1:k(j)-1); "** ---- included from " + fileName(f) + " ----"; inc; txt(k(j)+1:end)];
end
fid = fopen(out,'w'); fprintf(fid,'%s\n',strjoin(txt,newline)); fclose(fid);
end

function s = fileName(f)
[~,b,e] = fileparts(f); s = b + e;
end
