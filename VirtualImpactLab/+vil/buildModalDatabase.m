function db = buildModalDatabase(nodes,elements,Phi,omega,M,K,free,config)
% Refuse inconsistent DOF mappings instead of producing plausible FRFs.
assert(size(Phi,1)==3*size(nodes,2),'Unexpected structural DOF count.');
assert(~isempty(omega),'No modes found in the requested frequency range.');
omega = omega(:); free = free(:);
assert(all(isfinite(omega) & omega>0),'Only positive elastic modes are supported.');
Phi(setdiff(1:size(Phi,1),free),:) = 0;
Mff=M(free,free); Kff=K(free,free); P=Phi(free,:);
G=P'*Mff*P;
mass=real(diag(G));
assert(all(mass>0),'Nonpositive modal mass.');
Phi=Phi./sqrt(mass.'); P=Phi(free,:);
G=P'*Mff*P;
assert(norm(G-eye(numel(omega)),'fro')<1e-3*numel(omega), ...
    'Mass orthogonality check failed; inspect assembly DOF ordering.');
res=Kff*P-Mff*P*diag(omega.^2);
relative=vecnorm(res)./(vecnorm(Kff*P)+vecnorm(Mff*P*diag(omega.^2)));
assert(all(relative<1e-3),'Eigen residual failed; inspect constraints and DOF ordering.');
% Retain only exterior corner nodes as valid probes (quadratic midside nodes
% are deliberately omitted, but every selectable node is on the surface).
tet=elements(1:4,:).'; tr=triangulation(tet,nodes.');
faces=freeBoundary(tr); surfaceNodes=unique(faces(:));
db=struct('version',1,'nodes',nodes,'elements',elements, ...
    'surfaceFaces',faces,'surfaceNodes',surfaceNodes,'Phi',Phi, ...
    'omega',omega,'frequencyHz',omega/(2*pi),'modalMass',ones(size(omega)), ...
    'modalStiffness',omega.^2,'originalModalMass',mass,'M',M,'K',K, ...
    'freeDofs',free,'config',config,'eigenResidual',relative, ...
    'massOrthogonalityError',norm(G-eye(numel(omega)),'fro'), ...
    'created',char(datetime('now')));
end
