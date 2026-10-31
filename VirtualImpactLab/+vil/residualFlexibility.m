function r = residualFlexibility(db,mats,F,G,keep)
% Static contribution of the modes left out of the modal model, per path:
%    r_k = g_k' * (K^-1 - sum_kept phi*phi'/w^2) * f_k     (m/N)
% F, G: load and gauge vectors (DOFs x paths, from vil.mapProbePoints);
% keep: logical mask of the modes the test retains. Adds -w^2*r to each
% accelerance, i.e. r*F'' in time. mats: K, M, free from vil.solveModes.
% Free-free: the load is balanced by rigid-body inertia (inertia relief) and
% the rigid motion is removed, so only elastic flexibility remains.
if nargin < 5, keep = true(size(db.omega)); end
fr = mats.free(:); K = mats.K(fr,fr); M = mats.M(fr,fr);
f = F(fr,:); g = G(fr,:);
P = db.Phi(fr,keep); w = db.omega(keep);
if isempty(db.fixedNodes)
    R = rigidBasis(db.nodes); R = R(fr,:);
    R = R/chol(R.'*M*R);                     % mass-orthonormal rigid modes
    f = f - M*(R*(R.'*f));
    % K is singular here: a shift far below the first elastic mode keeps the
    % solve definite and changes the elastic flexibility by < 1e-4 relative.
    x = (K + 1e-4*db.omega(1)^2*M)\f;
    x = x - R*(R.'*(M*x));
else
    x = K\f;
end
x = x - P*((P.'*f)./w.^2);
r = full(sum(g.*x,1)).';
end

function R = rigidBasis(X)
% Translations and small rotations about the centroid, component-blocked.
n = size(X,2); c = X-mean(X,2); o = ones(n,1); z = zeros(n,1);
x = c(1,:).'; y = c(2,:).'; zc = c(3,:).';
R = [o z z  z   zc -y; ...
     z o z -zc  z   x; ...
     z z o  y  -x   z];
end
