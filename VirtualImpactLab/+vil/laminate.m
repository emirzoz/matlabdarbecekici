function L = laminate(ply,deg,t)
% Classical lamination theory. ply: one vil.plyMaterials entry (or a struct
% array, one per ply); deg: ply angles from the 0 deg (reference) axis,
% bottom ply first; t: ply thickness(es) (m). Returns A, B, D (Voigt,
% engineering shear: N = A eps + B kappa, M = B eps + D kappa, kappa =
% -w,xx ...), mass per area m, rotary inertia per area I, thickness h.
n = numel(deg);
if isscalar(ply), ply = repmat(ply,1,n); end
if isscalar(t), t = repmat(t,1,n); end
assert(numel(ply)==n && numel(t)==n,'vil:Layup','Give one material and one thickness per ply.');
h = sum(t); z = -h/2;
L = struct('A',zeros(3),'B',zeros(3),'D',zeros(3),'m',0,'I',0,'h',h,'deg',deg(:).');
for k = 1:n
    z1 = z+t(k); Qb = qbar(ply(k),deg(k));
    L.A = L.A+Qb*(z1-z); L.B = L.B+Qb*(z1^2-z^2)/2; L.D = L.D+Qb*(z1^3-z^3)/3;
    L.m = L.m+ply(k).rho*t(k); L.I = L.I+ply(k).rho*(z1^3-z^3)/3;
    z = z1;
end
% Round-off from +/- ply pairs: exact zeros keep symmetric layups uncoupled.
L.B(abs(L.B) < 1e-12*max(abs(L.A(:)))*h) = 0;
end

function Qb = qbar(p,deg)
% Ply stiffness rotated by deg into the laminate axes.
nu21 = p.nu12*p.E2/p.E1; d = 1-p.nu12*nu21;
Q = [p.E1/d p.nu12*p.E2/d 0; p.nu12*p.E2/d p.E2/d 0; 0 0 p.G12];
c = cosd(deg); s = sind(deg);
T = [c^2 s^2 2*c*s; s^2 c^2 -2*c*s; -c*s c*s c^2-s^2];   % stress transformation
R = diag([1 1 2]);                                        % engineering shear
Qb = T\Q*R*T/R;
end
