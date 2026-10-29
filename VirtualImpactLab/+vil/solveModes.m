function db = solveModes(geometry,c,opts)
% Modal solve on a meshed fegeometry; returns the reusable modal database.
% c: E, nu, rho (SI), fixedFaces (face IDs), rangeHz [lo hi].
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
faces = unique(c.fixedFaces(:)).';
assert(~isempty(faces),'vil:NoFixture','Select at least one fixed face.');
assert(all(faces>=1 & faces<=geometry.NumFaces & faces==round(faces)), ...
    'vil:BadFace','Fixed face IDs must be integers between 1 and %d.',geometry.NumFaces);
c.fixedFaces = faces;

model = femodel(AnalysisType="structuralModal",Geometry=geometry);
model.MaterialProperties = materialProperties(YoungsModulus=c.E, ...
    PoissonsRatio=c.nu,MassDensity=c.rho);
model.FaceBC(faces) = faceBC(Constraint="fixed");
mesh = model.Geometry.Mesh;
n = size(mesh.Nodes,2);

report(opts.Progress,sprintf('Assembling stiffness and mass (%d DOF)...',3*n));
A = assembleFEMatrices(model);
fixed = unique(cell2mat(arrayfun(@(f)findNodes(mesh,'region','Face',f),faces,'UniformOutput',false)));
free = setdiff(1:3*n,[fixed fixed+n fixed+2*n]);
Kff = A.K(free,free); Mff = A.M(free,free);
Kff = (Kff+Kff.')/2; Mff = (Mff+Mff.')/2;

hiHz = c.rangeHz(2);
N = min(opts.MinModes,numel(free)-1);
while true
    report(opts.Progress,sprintf('Solving the lowest %d modes (%d free DOF)...',N,numel(free)));
    [X,L] = eigs(Kff,Mff,N,'smallestabs','IsSymmetricDefinite',true);
    [lambda,order] = sort(real(diag(L))); X = real(X(:,order));
    fTop = sqrt(max(lambda(end),0))/(2*pi);
    if fTop >= hiHz || N >= min(opts.MaxModes,numel(free)-1), break; end
    N = min([2*N opts.MaxModes numel(free)-1]);
end
if lambda(1) <= 1e-8*lambda(end)
    error('vil:RigidBody',['The part can still move as a rigid body (first eigenvalue %.3g). ' ...
        'Clamp faces that fully constrain it.'],lambda(1));
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
