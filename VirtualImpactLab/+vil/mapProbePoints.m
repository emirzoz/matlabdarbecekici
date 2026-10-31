function [p,v] = mapProbePoints(db,location,direction,opts)
% Modal amplitudes at a probe along 'X'/'Y'/'Z', an axis index 1-3, or any
% 3-vector (normalized), e.g. the surface normal for a square hit.
% location: a surface node ID, or a 3-vector point (m) anywhere on the
% surface, interpolated linearly over the surface triangle it lies on.
% Radius > 0 spreads the probe over the surface within that distance of
% the point (a hammer tip face): tributary-area average on the same side.
% v is the matching unit load (or gauge) vector over all DOFs, so p = v'*Phi.
arguments
    db struct
    location double
    direction
    opts.Radius (1,1) double {mustBeNonnegative} = 0
end
n = size(db.nodes,2);
if isscalar(location)
    validateattributes(location,{'numeric'},{'scalar','integer','positive'});
    assert(ismember(location,db.surfaceNodes),'vil:Probe','Probe must be a selectable surface node.');
    ids = location; w = 1; x0 = db.nodes(:,location);
else
    validateattributes(location,{'numeric'},{'vector','numel',3,'finite'});
    [ids,w,x0] = onSurface(db,location(:));
end
if opts.Radius > 0, [ids,w] = tipPatch(db,x0,ids,w,opts.Radius); end
if ischar(direction) || isstring(direction)
    direction = find('XYZ'==upper(char(direction)));
    assert(isscalar(direction),'vil:Direction','Direction must be X, Y, Z or a 3-vector.');
end
if isscalar(direction)
    validateattributes(direction,{'numeric'},{'integer','>=',1,'<=',3});
    u = zeros(3,1); u(direction) = 1;
else
    validateattributes(direction,{'numeric'},{'vector','numel',3,'finite'});
    u = direction(:)/norm(direction);
    assert(all(isfinite(u)),'vil:Direction','Direction vector must be nonzero.');
end
rows = ids(:)+(0:2)*n; vals = w(:)*u.';
keep = vals ~= 0;
v = sparse(rows(keep),1,vals(keep),3*n,1);
p = full(v.'*db.Phi);
end

function [ids,w,x0] = onSurface(db,x)
% Closest point on the surface triangulation and its barycentric weights.
% Fixed (clamped) nodes stay in: their amplitude is zero, as it should be.
tri = db.surfaceFaces; V = db.nodes;
A = V(:,tri(:,1)); B = V(:,tri(:,2)); C = V(:,tri(:,3));
% Only triangles near the point need the exact projection.
cen = (A+B+C)/3; [~,order] = sort(vecnorm(cen-x)); cand = order(1:min(60,numel(order)));
best = Inf;
for k = cand(:).'
    [q,bary] = closestOnTriangle(x,A(:,k),B(:,k),C(:,k));
    d = norm(q-x);
    if d < best, best = d; ids = tri(k,:); w = bary; x0 = q; end
end
end

function [q,b] = closestOnTriangle(p,a,b0,c)
% Ericson, Real-Time Collision Detection, 5.1.5.
ab = b0-a; ac = c-a; ap = p-a;
d1 = ab.'*ap; d2 = ac.'*ap;
if d1<=0 && d2<=0, q = a; b = [1 0 0]; return, end
bp = p-b0; d3 = ab.'*bp; d4 = ac.'*bp;
if d3>=0 && d4<=d3, q = b0; b = [0 1 0]; return, end
vc = d1*d4-d3*d2;
if vc<=0 && d1>=0 && d3<=0, v = d1/(d1-d3); q = a+v*ab; b = [1-v v 0]; return, end
cp = p-c; d5 = ab.'*cp; d6 = ac.'*cp;
if d6>=0 && d5<=d6, q = c; b = [0 0 1]; return, end
vb = d5*d2-d1*d6;
if vb<=0 && d2>=0 && d6<=0, w = d2/(d2-d6); q = a+w*ac; b = [1-w 0 w]; return, end
va = d3*d6-d5*d4;
if va<=0 && (d4-d3)>=0 && (d5-d6)>=0
    w = (d4-d3)/((d4-d3)+(d5-d6)); q = b0+w*(c-b0); b = [0 1-w w]; return
end
den = 1/(va+vb+vc); v = vb*den; w = vc*den;
q = a+ab*v+ac*w; b = [1-v-w v w];
end

function [ids,w] = tipPatch(db,x0,ids0,w0,r)
% Uniform pressure over the surface within r of x0, lumped to nodes by
% tributary area (a third of each triangle per corner). Triangles facing
% away (the far side of a thin wall) are left out.
tri = db.surfaceFaces; V = db.nodes;
A = V(:,tri(:,1)); B = V(:,tri(:,2)); C = V(:,tri(:,3));
nrm = cross(B-A,C-A); area = vecnorm(nrm)/2; nrm = nrm./max(2*area,eps);
here = vil.surfaceNormal(V,tri,ids0(find(w0==max(w0),1)));
cen = (A+B+C)/3;
in = vecnorm(cen-x0) <= r & (here.'*nrm) > 0.5;
if ~any(in), ids = ids0; w = w0; return, end
corner = tri(in,:); a = repmat(area(in).'/3,1,3);
[ids,~,j] = unique(corner(:));
w = accumarray(j,a(:)); w = w/sum(w);
end
