function [K,M] = shellMatrices(nodes,tri,lams,triLam,ref)
% Stiffness and lumped mass of a faceted shell of flat 3-node triangles,
% 6 DOFs per node, component-blocked: [ux; uy; uz; rx; ry; rz], n each.
% Element: CST membrane + DKT bending (Batoz, Bathe & Ho 1980, thin
% Kirchhoff plates) + laminate B coupling + a weak drilling penalty that
% ties rz to the in-plane rotation (Hughes & Brezzi), so rigid rotations
% stay free. lams: vil.laminate structs; triLam: laminate of each
% triangle; ref: global axis whose projection on each element is the
% 0 deg fibre direction. Checked in development against exact plate,
% laminate (Navier, incl. B coupling) and ring frequencies.
n = size(nodes,2); ne = size(tri,1);
if nargin < 4 || isempty(triLam), triLam = ones(ne,1); end
if nargin < 5 || isempty(ref), ref = [1;0;0]; end
ref = ref(:)/norm(ref);
gp = [1/6 1/6; 2/3 1/6; 1/6 2/3];
im = [1 2 7 8 13 14]; ib = [3 4 5 9 10 11 15 16 17]; idr = [im 6 12 18];
I = zeros(324,ne); J = I; V = I; Md = zeros(18,ne); Jm = Md;
for e = 1:ne
    L = lams(triLam(e)); t = tri(e,:);
    X = nodes(:,t);
    nv = cross(X(:,2)-X(:,1),X(:,3)-X(:,1)); area = norm(nv)/2; nv = nv/norm(nv);
    e1 = ref-(ref.'*nv)*nv;
    if norm(e1) < 1e-3, e1 = X(:,2)-X(:,1); end        % reference axis normal to the element
    e1 = e1/norm(e1); e2 = cross(nv,e1); T = [e1 e2 nv].';
    xl = T*(X-X(:,1)); x = xl(1,:); y = xl(2,:);
    b = [y(2)-y(3) y(3)-y(1) y(1)-y(2)]; c = [x(3)-x(2) x(1)-x(3) x(2)-x(1)];
    Bm = zeros(3,6); Bm(1,1:2:6) = b; Bm(2,2:2:6) = c; Bm(3,1:2:6) = c; Bm(3,2:2:6) = b; Bm = Bm/(2*area);
    Bw = zeros(1,6); Bw(2:2:6) = b; Bw(1:2:6) = -c; Bw = Bw/(4*area);   % (v,x - u,y)/2
    Kbb = zeros(9); Kmb = zeros(6,9);
    for g = 1:3
        Bb = dktB(x,y,gp(g,1),gp(g,2));
        Kbb = Kbb+area/3*(Bb.'*L.D*Bb); Kmb = Kmb+area/3*(Bm.'*L.B*Bb);
    end
    Kd = zeros(9); gam = 1e-2*L.A(3,3);
    for k = 1:3
        gv = [-Bw zeros(1,3)]; gv(6+k) = 1; Kd = Kd+gam*area/3*(gv.'*gv);
    end
    Ke = zeros(18);
    Ke(im,im) = area*(Bm.'*L.A*Bm); Ke(ib,ib) = Kbb; Ke(im,ib) = Kmb; Ke(ib,im) = Kmb.';
    Ke(idr,idr) = Ke(idr,idr)+Kd;
    R = kron(eye(6),T); Ke = R.'*Ke*R; Ke = (Ke+Ke.')/2;
    dof = reshape(t(:)+(0:5)*n,1,[]);       % node-major local order -> global
    dof = reshape(reshape(dof,3,6).',1,[]);
    [jj,ii] = meshgrid(dof,dof);
    I(:,e) = ii(:); J(:,e) = jj(:); V(:,e) = Ke(:);
    Md(:,e) = repmat([L.m L.m L.m L.I L.I L.I]*area/3,1,3).'; Jm(:,e) = dof(:);
end
K = sparse(I(:),J(:),V(:),6*n,6*n);
M = sparse(Jm(:),Jm(:),Md(:),6*n,6*n);
end

function B = dktB(x,y,xi,eta)
% DKT curvature matrix (3 x 9) at area coordinates (xi, eta); per node
% DOFs (w, rx, ry) with rx = w,y and ry = -w,x (right-hand rotations).
x12 = x(1)-x(2); x23 = x(2)-x(3); x31 = x(3)-x(1);
y12 = y(1)-y(2); y23 = y(2)-y(3); y31 = y(3)-y(1);
xs = [x23 x31 x12]; ys = [y23 y31 y12]; l2 = xs.^2+ys.^2;     % edges 4, 5, 6
P = -6*xs./l2; q = 3*xs.*ys./l2; r = 3*ys.^2./l2; t = -6*ys./l2;
P4 = P(1); P5 = P(2); P6 = P(3); q4 = q(1); q5 = q(2); q6 = q(3);
r4 = r(1); r5 = r(2); r6 = r(3); t4 = t(1); t5 = t(2); t6 = t(3);
a = 1-2*xi; b = 1-2*eta;
Hxk = [P6*a+(P5-P6)*eta, q6*a-(q5+q6)*eta, -4+6*(xi+eta)+r6*a-eta*(r5+r6), ...
       -P6*a+eta*(P4+P6), q6*a-eta*(q6-q4), -2+6*xi+r6*a+eta*(r4-r6), ...
       -eta*(P5+P4), eta*(q4-q5), -eta*(r5-r4)];
Hyk = [t6*a+eta*(t5-t6), 1+r6*a-eta*(r5+r6), -q6*a+eta*(q5+q6), ...
       -t6*a+eta*(t4+t6), -1+r6*a+eta*(r4-r6), -q6*a-eta*(q4-q6), ...
       -eta*(t4+t5), eta*(r4-r5), -eta*(q4-q5)];
Hxe = [-P5*b-xi*(P6-P5), q5*b-xi*(q5+q6), -4+6*(xi+eta)+r5*b-xi*(r5+r6), ...
       xi*(P4+P6), xi*(q4-q6), -xi*(r6-r4), ...
       P5*b-xi*(P4+P5), q5*b+xi*(q4-q5), -2+6*eta+r5*b+xi*(r4-r5)];
Hye = [-t5*b-xi*(t6-t5), 1+r5*b-xi*(r5+r6), -q5*b+xi*(q5+q6), ...
       xi*(t4+t6), xi*(r4-r6), -xi*(q4-q6), ...
       t5*b-xi*(t4+t5), -1+r5*b+xi*(r4-r5), -q5*b-xi*(q4-q5)];
A2 = x31*y12-x12*y31;
B = [y31*Hxk+y12*Hxe; -x31*Hyk-x12*Hye; -x31*Hxk-x12*Hxe+y31*Hyk+y12*Hye]/A2;
end
