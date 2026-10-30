function [db,tests] = loadProject(filename)
S=load(filename,'db','tests');
assert(isfield(S,'db') && isfield(S.db,'version') && ismember(S.db.version,[1 2 3]),'vil:Project','Unsupported project file.');
db=S.db; tests=S.tests;
% Version 1 projects predate face labels and stored clamp nodes.
if ~isfield(db,'surfaceFaceId'), db.surfaceFaceId=zeros(size(db.surfaceFaces,1),1); end
if ~isfield(db,'fixedNodes')
    n=size(db.nodes,2); clamped=setdiff(1:3*n,db.freeDofs);
    db.fixedNodes=unique(mod(clamped-1,n)+1).';
end
end
