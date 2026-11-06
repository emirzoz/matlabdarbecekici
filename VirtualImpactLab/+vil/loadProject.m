function [db,tests,settings] = loadProject(filename)
% Load a project and bring older layouts up to date.
% settings: the solve set-up (material, supports, payload, mesh, units) as
% stored by vil.saveProject, or rebuilt from db.config for older files,
% including the payload study projects (payloadKg, payloadModel, tipNodes,
% tipZ, endPlaneTolerance, fixedNodes with empty fixedFaces).
vars = string({whos('-file',filename).name});
assert(ismember("db",vars),'vil:Project','Unsupported project file: no modal database "db".');
want = intersect(["db" "tests" "settings"],vars);
S = load(filename,want{:});
assert(isfield(S.db,'version') && ismember(S.db.version,[1 2 3]),'vil:Project','Unsupported project file.');
db = S.db;
tests = {}; if isfield(S,'tests'), tests = S.tests; end
% Version 1 projects predate face labels and stored clamp nodes.
if ~isfield(db,'surfaceFaceId'), db.surfaceFaceId=zeros(size(db.surfaceFaces,1),1); end
if ~isfield(db,'fixedNodes')
    n=size(db.nodes,2); clamped=setdiff(1:3*n,db.freeDofs);
    db.fixedNodes=unique(mod(clamped-1,n)+1).';
end
db = vil.projectSettings(db);          % fills payload/structure-mass fields
if isfield(S,'settings') && isstruct(S.settings)
    settings = S.settings;
else
    settings = db.config.settings;
end
end
