function db = buildModalDatabase(nodes,elements,Phi,omega,M,K,free,config,surf)
% Refuse inconsistent DOF mappings instead of producing plausible FRFs.
% M and K are used for checks only and are not stored: on STEP meshes they
% dominate memory and MAT-file size, and impacts never need them.
assert(size(Phi,1)==3*size(nodes,2),'vil:DofCount','Unexpected structural DOF count.');
assert(~isempty(omega),'vil:NoModes','No modes found in the requested frequency range.');
omega = omega(:); free = free(:);
assert(all(isfinite(omega) & omega>0),'vil:RigidModes','Only positive elastic modes are supported.');
Phi(setdiff(1:size(Phi,1),free),:) = 0;
Mff=M(free,free); Kff=K(free,free); P=Phi(free,:);
mass=real(diag(P'*Mff*P));
assert(all(mass>0),'vil:ModalMass','Nonpositive modal mass.');
Phi=Phi./sqrt(mass.'); P=Phi(free,:);
G=P'*Mff*P;
orthError=norm(G-eye(numel(omega)),'fro');
assert(orthError<1e-3*numel(omega), ...
    'vil:Orthogonality','Mass orthogonality check failed; inspect assembly DOF ordering.');
res=Kff*P-Mff*P*diag(omega.^2);
relative=vecnorm(res)./(vecnorm(Kff*P)+vecnorm(Mff*P*diag(omega.^2)));
assert(all(relative<1e-3),'vil:EigenResidual','Eigen residual failed; inspect constraints and DOF ordering.');
n=size(nodes,2);
% Translational mass of the meshed part: rigid X translation through M.
ex=zeros(3*n,1); ex(1:n)=1; totalMass=full(ex'*M*ex);
if nargin < 9 || isempty(surf)
    surf = surfaceFromElements(nodes,elements);
end
db=struct('version',2,'nodes',nodes,'elements',elements, ...
    'surfaceFaces',surf.tri,'surfaceFaceId',surf.faceId,'surfaceNodes',surf.nodes(:), ...
    'Phi',Phi,'omega',omega,'frequencyHz',omega/(2*pi), ...
    'originalModalMass',mass,'totalMass',totalMass,'numDofs',3*n, ...
    'freeDofs',free,'config',config,'eigenResidual',relative, ...
    'massOrthogonalityError',orthError,'created',char(datetime('now')));
end

function surf = surfaceFromElements(nodes,elements)
% Compact corner connectivity so unused quadratic midside points are not
% passed to triangulation. Map boundary indices back to original FEM IDs.
tet=elements(1:4,:).';
[cornerNodes,~,localIndex]=unique(tet(:));
tr=triangulation(reshape(localIndex,size(tet)),nodes(:,cornerNodes).');
local=freeBoundary(tr);
tri=reshape(cornerNodes(local(:)),size(local));
surf=struct('tri',tri,'faceId',zeros(size(tri,1),1),'nodes',unique(tri(:)));
end
