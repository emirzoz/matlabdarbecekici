function sh = createRadome(varargin)
% Nose radome as a ready shell mesh (mid-surface, same fields as
% vil.shellFromFaces): a tangent ogive with a spherical nose cap tangent to
% it, on a short cylindrical mounting flange. Axis along +Z, base of the
% ogive at z = 0, tip at z = Length; the flange runs from z = 0 down to
% -Flange. Face 1: ogive and nose; face 2: flange (clamp it for a radome
% bolted to the airframe). Rings are spaced by ElementSize along the
% meridian, each ring with as many nodes as its circumference needs, and
% neighbouring rings are zipped together by shortest diagonals.
% Options (SI): Diameter 0.15, Length 0.225 (fineness 1.5), NoseRadius 0.01,
% Wall 0.002, Flange 0.015, FlangeWall 0.004, ElementSize 0.006.
o = struct('Diameter',0.15,'Length',0.225,'NoseRadius',0.01,'Wall',0.002, ...
    'Flange',0.015,'FlangeWall',0.004,'ElementSize',0.006);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
R = o.Diameter/2; L = o.Length; h = o.ElementSize;
assert(L > R && o.NoseRadius < R/2 && h > 0,'vil:Radome', ...
    'Need Length > radius, NoseRadius < radius/2 and a positive element size.');
% Tangent ogive, x from the (sharp) tip: r(x) = sqrt(rho^2-(L-x)^2)+R-rho.
rho = (R^2+L^2)/(2*R);
ogive = @(x) sqrt(max(rho^2-(L-x).^2,0))+R-rho;
slope = @(x) (L-x)./sqrt(max(rho^2-(L-x).^2,eps));
% Nose cap: sphere tangent to the ogive where r = NoseRadius.
xt = fzeroBisect(@(x)ogive(x)-o.NoseRadius,0,L); s = slope(xt);
Rs = o.NoseRadius*sqrt(1+s^2); xc = xt+s*o.NoseRadius;
% Meridian (axial z, radius r) from the tip down to the flange bottom, fine.
a = linspace(0,atan2(o.NoseRadius,xc-xt),200);
cap = [xc-Rs*cos(a); Rs*sin(a)];                       % x, r
x = linspace(xt,L,2000); og = [x; ogive(x)];
mer = [cap og(:,2:end) [L+linspace(0,o.Flange,50); R*ones(1,50)]];
mer = mer(:,[true any(diff(mer,1,2),1)]);
z = L-mer(1,:); r = mer(2,:);
arc = [0 cumsum(vecnorm(diff([z;r],1,2)))];
nr = max(3,round(arc(end)/h));
sk = linspace(0,arc(end),nr+1);
zk = interp1(arc,z,sk); rk = interp1(arc,r,sk);
% Keep the ogive/flange seam (z = 0) as a ring so face 2 starts there.
[~,j] = min(abs(zk)); zk(j) = 0; rk(j) = R;
nodes = [0;0;zk(1)]; ring = {1};
for k = 2:numel(sk)
    m = max(6,round(2*pi*rk(k)/h)); th = 2*pi*(0:m-1)/m + pi/m*mod(k,2);
    ring{k} = size(nodes,2)+(1:m); %#ok<AGROW>
    nodes = [nodes [rk(k)*cos(th); rk(k)*sin(th); zk(k)*ones(1,m)]]; %#ok<AGROW>
end
tri = zeros(0,3);
for k = 1:numel(ring)-1, tri = [tri; zipRings(nodes,ring{k},ring{k+1})]; end %#ok<AGROW>
% Outward normals (away from the axis, or up at the tip).
A = nodes(:,tri(:,1)); B = nodes(:,tri(:,2)); C = nodes(:,tri(:,3));
nv = cross(B-A,C-A); cen = (A+B+C)/3;
% From the axis: horizontally below the nose sphere centre, radially from
% the centre above it.
out = cen-[zeros(2,size(cen,2)); min(cen(3,:),L-xc)];
flip = sum(nv.*out,1) < 0; tri(flip,:) = tri(flip,[1 3 2]);
cz = (nodes(3,tri(:,1))+nodes(3,tri(:,2))+nodes(3,tri(:,3)))/3;
faceId = 1+(cz(:) < -1e-9);
faceT = [o.Wall; o.FlangeWall]; tTri = faceT(faceId);
n = size(nodes,2);
tn = accumarray(tri(:),repmat(tTri,3,1),[n 1])./accumarray(tri(:),1,[n 1]);
sh = struct('nodes',nodes,'tri',tri,'faceId',faceId,'triThickness',tTri,'nodeThickness',tn, ...
    'faces',[1 2],'faceThickness',faceT,'solidNode',(1:n).','normal',zeros(3,n),'offset',false, ...
    'piece',ones(n,1),'numPieces',1,'options',o, ...
    'name',sprintf('Ogive radome %.0f × %.0f mm, %.1f mm wall',2e3*R,1e3*L,1e3*o.Wall));
end

function t = zipRings(X,a,b)
% Triangles between two closed rings, always taking the shorter diagonal.
m = numel(a); n = numel(b); i = 1; j = 1; t = zeros(m+n,3); q = 0;
while i <= m || j <= n
    ai = a(mod(i-1,m)+1); bj = b(mod(j-1,n)+1);
    an = a(mod(i,m)+1); bn = b(mod(j,n)+1);
    useA = j > n || (i <= m && norm(X(:,an)-X(:,bj)) < norm(X(:,ai)-X(:,bn)));
    q = q+1;
    if useA, t(q,:) = [ai an bj]; i = i+1; else, t(q,:) = [ai bn bj]; j = j+1; end
end
t = t(1:q,:);
if m == 1, t = t(t(:,1) ~= t(:,2) & t(:,2) ~= t(:,3),:); end
end

function x = fzeroBisect(f,a,b)
for k = 1:100
    x = (a+b)/2; if f(a)*f(x) <= 0, b = x; else, a = x; end
end
end
