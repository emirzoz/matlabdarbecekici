function fixed = shellClampNodes(sh,nodes,surf,clampFaces)
% Shell nodes held by clamped faces of the solid. A clamp face may touch the
% shell (a bolt-hole wall) or lie on the far side of the wall (the underside
% of a flange): a shell node is held if a clamp-face node lies within 1.1x
% its local wall thickness, which reaches both skins from the mid-surface.
cn = unique(surf.tri(ismember(surf.faceId,clampFaces),:));
assert(~isempty(cn),'vil:NoFixture','Pick the faces the part is clamped by.');
Y = nodes(:,cn); fixed = false(size(sh.nodes,2),1);
for k = 1:2000:size(sh.nodes,2)
    j = k:min(k+1999,size(sh.nodes,2)); x = sh.nodes(:,j);
    d2 = sum(Y.^2,1).'-2*Y.'*x+sum(x.^2,1);
    fixed(j) = sqrt(max(min(d2,[],1),0)).' <= 1.1*sh.nodeThickness(j);
end
fixed = find(fixed);
assert(~isempty(fixed),'vil:NoFixture','No shell node lies on the clamped faces: pick faces that touch the shell skin.');
end
