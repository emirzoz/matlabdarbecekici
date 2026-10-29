function [db,tests] = loadProject(filename)
S=load(filename,'db','tests');
assert(isfield(S,'db') && isfield(S.db,'version') && ismember(S.db.version,[1 2]),'vil:Project','Unsupported project file.');
db=S.db; tests=S.tests;
if ~isfield(db,'surfaceFaceId'), db.surfaceFaceId=zeros(size(db.surfaceFaces,1),1); end
end
