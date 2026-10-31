function [db,mats] = solveShellModes(nodes,tri,c,varargin)
% Modal solve of a laminated shell (vil.shellMatrices) into the same modal
% database as vil.solveModes, so hammer tests, flight, damping and residual
% flexibility work unchanged. Translations are in Phi (3n rows, component-
% blocked); rotations in PhiRot.
% c: laminates (vil.laminate structs), triLam (laminate per triangle),
%    ref (0 deg fibre axis), boundary "clamped"/"free", fixedNodes (all six
%    DOFs held), faceId (CAD face of each triangle), rangeHz [lo hi].
% Options: 'MinModes' (10), 'MaxModes' (200), 'Progress' (function handle).
% (Name-value pairs are parsed by hand so the shell code also runs in Octave.)
o = struct('MinModes',10,'MaxModes',200,'Progress',[]);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
if ~isfield(c,'rangeHz') || isempty(c.rangeHz), c.rangeHz = [0 0]; end
if ~isfield(c,'triLam') || isempty(c.triLam), c.triLam = ones(size(tri,1),1); end
if ~isfield(c,'ref') || isempty(c.ref), c.ref = [1;0;0]; end
if ~isfield(c,'faceId') || isempty(c.faceId), c.faceId = zeros(size(tri,1),1); end
if ~isfield(c,'boundary'), c.boundary = 'clamped'; end
isFree = strcmpi(char(c.boundary),'free');
if isFree, c.fixedNodes = []; end
assert(isFree || ~isempty(c.fixedNodes),'vil:NoFixture','Select the faces the shell is clamped to, or choose free-free.');
n = size(nodes,2);
report(o.Progress,sprintf('Assembling shell stiffness and mass (%d DOF)...',6*n));
[K,M] = vil.shellMatrices(nodes,tri,c.laminates,c.triLam,c.ref);
fixed = unique(c.fixedNodes(:)).';
% Nodes no element touches carry no stiffness: hold them too.
used = unique(tri(:)).'; idle = setdiff(1:n,used);
held = unique([fixed idle]);
free = setdiff(1:6*n,reshape(held(:)+(0:5)*n,1,[]));
Kff = K(free,free); Mff = M(free,free);
hiHz = c.rangeHz(2); nRigid = 6*isFree;
if isFree, sigma = -1e-6*full(mean(diag(Kff))/mean(diag(Mff))); else, sigma = 0; end
N = min(o.MinModes+nRigid,numel(free)-1);
while true
    report(o.Progress,sprintf('Solving the lowest %d shell modes (%d free DOF)...',N,numel(free)));
    [X,L] = eigsSym(Kff,Mff,N,sigma);
    [lambda,order] = sort(real(diag(L))); X = real(X(:,order));
    if sqrt(max(lambda(end),0))/(2*pi) >= hiHz || N >= min(o.MaxModes+nRigid,numel(free)-1), break; end
    N = min([2*N o.MaxModes+nRigid numel(free)-1]);
end
rigid = abs(lambda) <= 1e-8*lambda(end);
if isFree
    assert(nnz(rigid) == 6,'vil:RigidBody',['Expected 6 rigid-body modes for a free shell, found %d. ' ...
        'The picked faces may form separate pieces.'],nnz(rigid));
elseif any(rigid)
    error('vil:RigidBody',['The shell can still move as a rigid body (first eigenvalue %.3g). ' ...
        'Clamp faces that fully constrain it, or choose free-free.'],lambda(1));
end
rigidHz = sqrt(abs(lambda(rigid)))/(2*pi);
lambda = lambda(~rigid); X = X(:,~rigid);
omega = sqrt(lambda);
keep = (1:numel(omega)).' <= o.MinModes | omega/(2*pi) <= hiHz;
omega = omega(keep); X = X(:,keep);
c.rangeHz = [0 max(hiHz,omega(end)/(2*pi))];
% Mass-normalize and check, as vil.buildModalDatabase does for solids.
mass = real(sum(X.*(Mff*X),1)).';
assert(all(mass > 0),'vil:ModalMass','Nonpositive modal mass.');
X = X./sqrt(mass.');
G = X.'*Mff*X; orthError = norm(G-eye(numel(omega)),'fro');
assert(orthError < 1e-3*numel(omega),'vil:Orthogonality','Shell mass orthogonality check failed.');
res = Kff*X-Mff*X*diag(omega.^2);
relative = vecnorm(res)./(vecnorm(Kff*X)+vecnorm(Mff*X*diag(omega.^2)));
assert(all(relative < 1e-3),'vil:EigenResidual','Shell eigen residual check failed.');
PhiAll = zeros(6*n,numel(omega)); PhiAll(free,:) = X;
ex = zeros(6*n,1); ex(1:n) = 1;
participation = zeros(3,numel(omega));
for d = 1:3
    r = zeros(6*n,1); r((d-1)*n+(1:n)) = 1;
    participation(d,:) = (PhiAll.'*(M*r)).';
end
report(o.Progress,'Shell modes ready.');
db = struct('version',3,'isShell',true,'nodes',nodes,'elements',tri.', ...
    'surfaceFaces',tri,'surfaceFaceId',c.faceId(:),'surfaceNodes',used(:), ...
    'Phi',PhiAll(1:3*n,:),'PhiRot',PhiAll(3*n+1:end,:),'omega',omega,'frequencyHz',omega/(2*pi), ...
    'originalModalMass',mass,'totalMass',full(ex.'*M*ex),'participation',participation,'numDofs',6*n, ...
    'freeDofs',free(:),'config',c,'eigenResidual',relative(:),'massOrthogonalityError',orthError, ...
    'created',datestr(now),'fixedNodes',fixed(:),'rigidBodyHz',rigidHz);
if nargout > 1, mats = struct('K',K,'M',M,'free',free(:)); end
end

function [X,L] = eigsSym(K,M,N,sigma)
try
    [X,L] = eigs(K,M,N,sigma,'IsSymmetricDefinite',true);
catch
    [X,L] = eigs(K,M,N,sigma);    % Octave: no name-value options
end
end

function report(progress,msg)
if isempty(progress), return; end
progress(msg);
end
