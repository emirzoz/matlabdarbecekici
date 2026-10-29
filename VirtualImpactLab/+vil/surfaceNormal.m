function nrm = surfaceNormal(nodes,tri,node)
% Outward unit normal at a surface node: area-weighted mean of the normals
% of its exterior triangles. freeBoundary orients facets outward.
touch = any(tri==node,2);
assert(any(touch),'vil:Probe','Node %d is not on the surface.',node);
T = tri(touch,:);
a = nodes(:,T(:,1)); b = nodes(:,T(:,2)); c = nodes(:,T(:,3));
nrm = sum(cross(b-a,c-a),2);
nrm = nrm/norm(nrm);
end
