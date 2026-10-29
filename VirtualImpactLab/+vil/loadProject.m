function [db,tests] = loadProject(filename)
S=load(filename,'db','tests');
assert(isfield(S,'db') && isfield(S.db,'version') && S.db.version==1,'Unsupported project.');
db=S.db; tests=S.tests;
end
