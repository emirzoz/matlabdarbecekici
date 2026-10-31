function [db,mats] = solveModes(geometry,c,opts)
% Modal solve on a meshed fegeometry; returns the reusable modal database.
% c: E, nu, rho (SI), fixedFaces (face IDs), rangeHz [lo hi],
%    boundary "clamped" (default) or "free" (free-free: no faces fixed).
% The lowest MinModes elastic modes are always computed, plus every further
% mode up to rangeHz(2). PDE Toolbox assembles K and M; the clamped DOFs
% are removed and the generalized problem is solved by shift-invert eigs.
% On bearing-housing.step (50k DOF) this takes ~7 s, against ~190 s for
% repeated band-limited solve(model,FrequencyRange=...) calls that had to
% search for a band containing any modes. Frequencies agree to 5 digits.
arguments
    geometry
    c struct
    opts.MinModes (1,1) double {mustBeInteger,mustBePositive} = 10
    opts.MaxModes (1,1) double {mustBeInteger,mustBePositive} = 200
    opts.Progress = []
    opts.MeshInfo struct = struct()
end
if ~isfield(c,'rangeHz') || isempty(c.rangeHz), c.rangeHz = [0 0]; end
validateattributes(c.rangeHz,{'numeric'},{'vector','numel',2,'nonnegative'});
validateattributes(c.E,{'numeric'},{'scalar','positive','finite'});
validateattributes(c.rho,{'numeric'},{'scalar','positive','finite'});
validateattributes(c.nu,{'numeric'},{'scalar','>',-1,'<',0.5});
assert(~isempty(geometry.Mesh),'vil:NoMesh','Mesh the part before solving.');
if ~isfield(c,'boundary') || strlength(string(c.boundary)) == 0, c.boundary = "clamped"; end
c.boundary = string(c.boundary);
assert(ismember(c.boundary,["clamped" "free"]),'vil:Boundary','boundary must be "clamped" or "free".');
isFree = c.boundary == "free";
if isFree, c.fixedFaces = []; end
faces = unique(c.fixedFaces(:)).';
assert(isFree || ~isempty(faces),'vil:NoFixture','Select at least one fixed face, or choose free-free.');
assert(all(faces>=1 & faces<=geometry.NumFaces & faces==round(faces)), ...
    'vil:BadFace','Fixed face IDs must be integers between 1 and %d.',geometry.NumFaces);
c.fixedFaces = faces;

model = femodel(AnalysisType="structuralModal",Geometry=geometry);
model.MaterialProperties = materialProperties(YoungsModulus=c.E, ...
    PoissonsRatio=c.nu,MassDensity=c.rho);
if ~isFree, model.FaceBC(faces) = faceBC(Constraint="fixed"); end
mesh = model.Geometry.Mesh;
n = size(mesh.Nodes,2);

report(opts.Progress,sprintf('Assembling stiffness and mass (%d DOF)...',3*n));
A = assembleFEMatrices(model);
fixed = zeros(1,0);
if ~isFree
    fixed = unique(cell2mat(arrayfun(@(f)findNodes(mesh,'region','Face',f),faces,'UniformOutput',false)));
end
free = setdiff(1:3*n,[fixed fixed+n fixed+2*n]);
Kff = A.K(free,free); Mff = A.M(free,free);
Kff = (Kff+Kff.')/2; Mff = (Mff+Mff.')/2;

hiHz = c.rangeHz(2);
% A free part has six rigid-body modes at zero frequency, so K is singular:
% shift below zero, where K - sigma*M is positive definite.
nRigid = 6*isFree;
if isFree
    sigma = -1e-6*full(mean(diag(Kff))/mean(diag(Mff)));
else
    sigma = 'smallestabs';
end
N = min(opts.MinModes+nRigid,numel(free)-1);
while true
    report(opts.Progress,sprintf('Solving the lowest %d modes (%d free DOF)...',N,numel(free)));
    [X,L] = eigs(Kff,Mff,N,sigma,'IsSymmetricDefinite',true);
    [lambda,order] = sort(real(diag(L))); X = real(X(:,order));
    fTop = sqrt(max(lambda(end),0))/(2*pi);
    if fTop >= hiHz || N >= min(opts.MaxModes+nRigid,numel(free)-1), break; end
    N = min([2*N opts.MaxModes+nRigid numel(free)-1]);
end
% Rigid-body modes come out at round-off level, many decades below the
% first elastic mode.
rigid = abs(lambda) <= 1e-8*lambda(end);
if isFree
    assert(nnz(rigid) == 6,'vil:RigidBody',['Expected 6 rigid-body modes for a free part, found %d. ' ...
        'The mesh may hold several disconnected bodies.'],nnz(rigid));
    rigidHz = sqrt(abs(lambda(rigid)))/(2*pi);
    lambda = lambda(~rigid); X = X(:,~rigid);
elseif any(rigid)
    error('vil:RigidBody',['The part can still move as a rigid body (first eigenvalue %.3g). ' ...
        'Clamp faces that fully constrain it, or choose free-free.'],lambda(1));
else
    rigidHz = zeros(0,1);
end
omega = sqrt(lambda);
keep = (1:numel(omega)).' <= opts.MinModes | omega/(2*pi) <= hiHz;
omega = omega(keep); X = X(:,keep);
c.rangeHz = [0 max(hiHz,omega(end)/(2*pi))];
Phi = zeros(3*n,numel(omega)); Phi(free,:) = X;   % component-blocked: all X, all Y, all Z

report(opts.Progress,'Normalizing and checking modes...');
if isfield(opts.MeshInfo,'surface'), surf = opts.MeshInfo.surface; else, surf = vil.extractSurface(model.Geometry); end
db = vil.buildModalDatabase(mesh.Nodes,mesh.Elements,Phi,omega,A.M,A.K,free,c,surf);
db.fixedNodes = fixed(:);
db.rigidBodyHz = rigidHz;
% K and M stay out of db (size); mats is for residual flexibility in this session.
if nargout > 1, mats = struct('K',A.K,'M',A.M,'free',free(:)); end
db.meshInfo = rmfieldIfPresent(opts.MeshInfo,'surface');
db.span = (max(mesh.Nodes,[],2)-min(mesh.Nodes,[],2)).';
end

function s = rmfieldIfPresent(s,f)
if isfield(s,f), s = rmfield(s,f); end
end

function report(progress,msg)
if isempty(progress), return; end
progress(msg);
end
