function p = mapProbePoints(db,node,direction)
% Modal amplitudes of a surface node along 'X'/'Y'/'Z', an axis index 1-3,
% or any 3-vector (normalized), e.g. the surface normal for a square hit.
validateattributes(node,{'numeric'},{'scalar','integer','positive'});
assert(ismember(node,db.surfaceNodes),'vil:Probe','Probe must be a selectable surface node.');
n = size(db.nodes,2);
if ischar(direction) || isstring(direction)
    direction = find('XYZ'==upper(char(direction)));
    assert(isscalar(direction),'vil:Direction','Direction must be X, Y, Z or a 3-vector.');
end
if isscalar(direction)
    validateattributes(direction,{'numeric'},{'integer','>=',1,'<=',3});
    p = db.Phi(node+(direction-1)*n,:);
else
    validateattributes(direction,{'numeric'},{'vector','numel',3,'finite'});
    u = direction(:)/norm(direction);
    assert(all(isfinite(u)),'vil:Direction','Direction vector must be nonzero.');
    p = u.'*db.Phi(node+[0 n 2*n],:);
end
end
