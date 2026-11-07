function [geometry,meshInfo,surf] = meshFromArrays(X,T,label,opts)
% fegeometry from ready tetrahedra (no remeshing), node numbering kept.
% X: 3 x N coordinates in metres; T: 4|10 x E connectivity, 1-based, corners
% first then midsides 12,23,31,14,24,34 (C3D10 / SOLID187 / MATLAB order).
% Checks repeated corners, unused nodes and element volumes; a mesh whose
% elements are all inverted is reordered, a mixed one is refused.
arguments
    X (3,:) double
    T double
    label (1,1) string = "mesh"
    opts.Progress = []
end
n = size(X,2);
assert(ismember(size(T,1),[4 10]),'vil:MeshElements', ...
    'Elements must be 4-node (linear) or 10-node (quadratic) tetrahedra.');
assert(all(T(:) == round(T(:))) && min(T(:)) >= 1 && max(T(:)) <= n,'vil:MeshElements', ...
    'Element connectivity must hold node IDs between 1 and %d.',n);
srt = sort(T(1:4,:),1);
dup = any(diff(srt,1,1) == 0,1);
assert(~any(dup),'vil:MeshElements','%d element(s) repeat a corner node (e.g. element %d).',nnz(dup),find(dup,1));
used = false(1,n); used(T(:)) = true;
assert(all(used),'vil:MeshNodes',['%d node(s) belong to no element (e.g. node %d). Remove them first: ' ...
    'the import keeps node IDs, which supports and payload selections refer to.'],nnz(~used),find(~used,1));
order = "linear"; if size(T,1) == 10, order = "quadratic"; end
report(opts.Progress,'Checking element volumes...');
a = X(:,T(2,:))-X(:,T(1,:)); b = X(:,T(3,:))-X(:,T(1,:)); c = X(:,T(4,:))-X(:,T(1,:));
vol = dot(a,cross(b,c,1),1)/6;
reordered = false;
if all(vol < 0)
    % Consistently inverted: swap corners 2 and 3 (and the matching midsides).
    perm = [1 3 2 4]; if order == "quadratic", perm = [1 3 2 4 7 6 5 8 10 9]; end
    T = T(perm,:); vol = -vol; reordered = true;
end
bad = vol <= 0;
if any(bad)
    error('vil:MeshVolume',['%d of %d elements have zero or negative volume (e.g. element %d, %.3g mm^3). ' ...
        'Repair the mesh (inverted or flat tetrahedra) before solving.'],nnz(bad),numel(vol),find(bad,1),1e9*vol(find(bad,1)));
end
report(opts.Progress,sprintf('Building the FE geometry from %d nodes and %d elements (no remeshing)...',n,size(T,2)));
geometry = fegeometry(X.',T.');
assert(size(geometry.Mesh.Nodes,2) == n && max(abs(geometry.Mesh.Nodes-X),[],'all') <= 1e-12*max(abs(X(:))) ...
    && isequal(double(geometry.Mesh.Elements),T),'vil:MeshChanged', ...
    'fegeometry renumbered the mesh; node-based selections would be wrong.');
report(opts.Progress,sprintf('Labelling the surface (%d faces)...',geometry.NumFaces));
surf = vil.extractSurface(geometry);
meshInfo = struct('hmaxRequested',NaN,'hmaxUsed',NaN,'order',order, ...
    'numNodes',n,'numElements',size(T,2),'numDofs',3*n,'fromTessellation',false, ...
    'numFaces',geometry.NumFaces,'surface',surf,'mesher',"Imported " + order + " tetrahedra: " + label, ...
    'imported',true,'volume',sum(vol),'minElementVolume',min(vol),'meanElementVolume',mean(vol), ...
    'reordered',reordered);
end

function report(progress,msg)
if isempty(progress), return; end
progress(msg);
end
