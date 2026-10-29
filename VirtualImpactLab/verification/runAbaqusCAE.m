function abq = runAbaqusCAE(stepFile,db,folder,job,opts)
% Independent Abaqus model: Abaqus imports and meshes the STEP file itself.
% Fixed faces are found from points on the MATLAB fixed faces; results are
% returned with Abaqus node coordinates for nearest-node MAC comparison.
arguments
    stepFile (1,1) string
    db struct
    folder (1,1) string
    job (1,1) string
    opts.ScaleToMetres (1,1) double
    opts.Hmax (1,1) double
    opts.MaxHz (1,1) double = max(db.frequencyHz)
    opts.Abaqus (1,1) string = "C:\SIMULIA\Commands\abaqus.bat"
end
if ~isfolder(folder), mkdir(folder); end
c = db.config;
cfg = struct('step',char(stepFile),'scale',opts.ScaleToMetres,'hmax',opts.Hmax, ...
    'E',c.E,'nu',c.nu,'rho',c.rho,'fixedPoints',fixedFacePoints(db),'maxHz',opts.MaxHz,'job',char(job));
cfgFile = fullfile(folder,job+"_cfg.json");
writelines(jsonencode(cfg),cfgFile);
here = cd(folder); restore = onCleanup(@()cd(here));
script = fullfile(fileparts(mfilename('fullpath')),'abaqus','cae_step_modal.py');
system(sprintf('"%s" cae noGUI="%s" -- "%s"',opts.Abaqus,script,cfgFile));
odb = fullfile(folder,job+".odb");
assert(isfile(odb) && isfile(fullfile(folder,job+"_cae.json")),'vil:AbaqusCAE', ...
    'Abaqus/CAE job %s failed; see %s.',job,fullfile(folder,job+".dat"));
out = fullfile(folder,job+"_results");
reader = fullfile(fileparts(mfilename('fullpath')),'abaqus','read_odb.py');
system(sprintf('"%s" python "%s" "%s" "%s"',opts.Abaqus,reader,odb,out));
abq = readAbaqusResults(out);
abq.info = jsondecode(fileread(fullfile(folder,job+"_cae.json")));
N = readmatrix(fullfile(folder,job+"_nodes.txt"),FileType='text');
[~,order] = ismember(abq.nodes,N(:,1));
abq.coordinates = N(order,2:4);
end

function P = fixedFacePoints(db)
% Up to three fixed-face nodes per CAD face, away from the face boundary.
faceIds = db.config.fixedFaces;
P = zeros(0,3);
tri = db.surfaceFaces; fid = db.surfaceFaceId;
for f = faceIds(:).'
    inside = unique(tri(fid==f,:));
    others = unique(tri(fid~=f,:));
    interior = setdiff(inside,others);
    if isempty(interior), interior = inside; end
    X = db.nodes(:,interior).';
    % Nodes closest to the face's mean position are well inside the face.
    [~,k] = sort(vecnorm(X-mean(X,1),2,2));
    P = [P; X(k(1:min(3,end)),:)]; %#ok<AGROW>
end
end
