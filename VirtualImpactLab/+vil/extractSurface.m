function surf = extractSurface(geometry)
% Exterior triangles of a tetrahedral mesh, each labelled with its CAD face ID.
% Triangles use global mesh node IDs (corner nodes only); quadratic midside
% nodes are excluded from the triangulation but remain valid FE nodes.
mesh = geometry.Mesh;
tet = mesh.Elements(1:4,:).';
[cornerNodes,~,localIndex] = unique(tet(:));
tr = triangulation(reshape(localIndex,size(tet)),mesh.Nodes(:,cornerNodes).');
local = freeBoundary(tr);
tri = reshape(cornerNodes(local(:)),size(local));
faceId = zeros(size(tri,1),1);
faceNodes = cell(geometry.NumFaces,1);
onFace = false(size(mesh.Nodes,2),1);
for f = 1:geometry.NumFaces
    n = findNodes(mesh,'region','Face',f);
    faceNodes{f} = n(:);
    onFace(:) = false; onFace(n) = true;
    hit = faceId == 0 & all(onFace(tri),2);
    faceId(hit) = f;
end
% Triangles spanning two faces at a sharp corner: assign by majority.
for k = find(faceId == 0).'
    counts = cellfun(@(n)sum(ismember(tri(k,:),n)),faceNodes);
    [~,faceId(k)] = max(counts);
end
nodes = unique(tri(:));
surf = struct('tri',tri,'faceId',faceId,'nodes',nodes,'faceNodes',{faceNodes});
end
