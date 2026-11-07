function [db,mats] = solveModes(geometry,c,opts)
% Modal solve on a meshed fegeometry; returns the reusable modal database.
% c: E, nu, rho (SI), fixedFaces (face IDs), rangeHz [lo hi],
%    boundary "clamped" (default) or "free" (free-free: no faces fixed).
% Optional:
%    c.fixedNodes  node IDs clamped in addition to fixedFaces (Ux=Uy=Uz=0).
%                  Solid tetrahedra have no rotational DOF, so fixing the
%                  three translations of a node is a full clamp of that node.
%    c.payload     struct with massKg and nodes: a translational inertia mass
%                  that follows the average X/Y/Z translation of the nodes:
%                     u_payload = B*u,   M_total = M_structure + m*(B.'*B)
%                  B (3 x 3n) averages each translation over the nodes. It
%                  adds no stiffness, no rotary inertia, no offset of the
%                  payload centre of mass and does not tie the nodes together.
%                  No gravity preload: the mass acts only as inertia.
% The lowest MinModes elastic modes are always computed, plus every further
% mode up to rangeHz(2). PDE Toolbox assembles K and M; the clamped DOFs
% are removed and the generalized problem is solved by shift-invert eigs.
% On bearing-housing.step (50k DOF) this takes ~7 s, against ~190 s for
% repeated band-limited solve(model,FrequencyRange=...) calls that had to
% search for a band containing any modes. Frequencies agree to 5 digits.
% opts.Assembly takes the second output of an earlier call on the same mesh
% and material, so a payload-mass sweep assembles K and M only once.
arguments
    geometry
    c struct
    opts.MinModes (1,1) double {mustBeInteger,mustBePositive} = 10
    opts.MaxModes (1,1) double {mustBeInteger,mustBePositive} = 200
    opts.Progress = []
    opts.MeshInfo struct = struct()
    opts.Assembly = []
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
if ~isfield(c,'fixedFaces'), c.fixedFaces = []; end
if ~isfield(c,'fixedNodes'), c.fixedNodes = []; end
if isFree, c.fixedFaces = []; c.fixedNodes = []; end
mesh = geometry.Mesh;
n = size(mesh.Nodes,2);
faces = unique(c.fixedFaces(:)).';
extraFixed = unique(round(c.fixedNodes(:))).';
assert(isFree || ~isempty(faces) || ~isempty(extraFixed),'vil:NoFixture', ...
    'Select at least one fixed face or support node, or choose free-free.');
assert(all(faces>=1 & faces<=geometry.NumFaces & faces==round(faces)), ...
    'vil:BadFace','Fixed face IDs must be integers between 1 and %d.',geometry.NumFaces);
assert(all(extraFixed>=1 & extraFixed<=n),'vil:BadNode','Support node IDs must lie between 1 and %d.',n);
c.fixedFaces = faces;
c.fixedNodes = extraFixed;

payloadKg = 0; payloadNodes = zeros(1,0); payloadWeights = [];
if isfield(c,'payload') && ~isempty(c.payload) && isfield(c.payload,'massKg')
    payloadKg = c.payload.massKg;
    assert(isnumeric(payloadKg) && isscalar(payloadKg) && isreal(payloadKg) && isfinite(payloadKg) && payloadKg >= 0, ...
        'vil:PayloadMass','Payload mass must be a finite value of 0 kg or more (got %s).',mat2str(payloadKg));
    if payloadKg > 0
        assert(isfield(c.payload,'nodes') && ~isempty(c.payload.nodes),'vil:EmptySelection', ...
            'The payload has no attachment nodes: select faces or a plane for it.');
        payloadNodes = round(c.payload.nodes(:)).';
        assert(all(payloadNodes>=1 & payloadNodes<=n),'vil:BadNode','Payload node IDs must lie between 1 and %d.',n);
        if isfield(c.payload,'weights') && ~isempty(c.payload.weights)
            % Weighted average (e.g. an imported *EQUATION with unequal
            % coefficients): u_payload = sum w_i u_i, sum w_i = 1.
            w = c.payload.weights(:).';
            assert(numel(w) == numel(payloadNodes) && numel(unique(payloadNodes)) == numel(payloadNodes) ...
                && all(w > 0) && abs(sum(w)-1) <= 1e-9,'vil:PayloadWeights', ...
                'Payload weights must be positive, one per distinct node, and sum to 1.');
            [payloadNodes,o] = sort(payloadNodes); payloadWeights = w(o);
        else
            payloadNodes = unique(payloadNodes);
        end
    end
end

if isempty(opts.Assembly)
    model = femodel(AnalysisType="structuralModal",Geometry=geometry);
    model.MaterialProperties = materialProperties(YoungsModulus=c.E, ...
        PoissonsRatio=c.nu,MassDensity=c.rho);
    if ~isempty(faces), model.FaceBC(faces) = faceBC(Constraint="fixed"); end
    report(opts.Progress,sprintf('Assembling stiffness and mass (%d DOF)...',3*n));
    A = assembleFEMatrices(model);
    K = A.K; Mstruct = A.M;
else
    a = opts.Assembly;
    assert(a.numNodes == n && isequal([a.E a.nu a.rho],[c.E c.nu c.rho]), ...
        'vil:Assembly','The cached K and M belong to another mesh or material.');
    K = a.K; Mstruct = a.Mstructure;
end
fixed = zeros(1,0);
if ~isFree
    if ~isempty(faces)
        fixed = unique(cell2mat(arrayfun(@(f)findNodes(mesh,'region','Face',f),faces,'UniformOutput',false)));
    end
    fixed = union(fixed,extraFixed);
end
clash = intersect(payloadNodes,fixed);
if ~isempty(clash)
    error('vil:PayloadOnSupport',['%d of the %d payload attachment node(s) are also support nodes ' ...
        '(e.g. node %d). A clamped node cannot carry the payload: choose separate regions.'], ...
        numel(clash),numel(payloadNodes),clash(1));
end
free = setdiff(1:3*n,[fixed fixed+n fixed+2*n]);
if payloadKg > 0
    np = numel(payloadNodes);
    w = ones(np,1)/np; if ~isempty(payloadWeights), w = payloadWeights(:); end
    B = sparse(repelem((1:3).',np),reshape(payloadNodes(:)+(0:2)*n,[],1),repmat(w,3,1),3,3*n);
    M = Mstruct + payloadKg*(B.'*B);
else
    M = Mstruct;
end
Kff = K(free,free); Mff = M(free,free);
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

% Payload record, also under the field names of the earlier study scripts
% (payloadKg, payloadModel, tipNodes) so older tools keep reading it.
model = "Translational point mass on the average X/Y/Z translation of the attachment nodes; " + ...
    "no rotary inertia, no CG offset, nodes not tied together; inertia only (no gravity preload)";
if payloadKg > 0
    if ~isempty(payloadWeights), model = replace(model,"average","weighted average"); end
    c.payload = struct('massKg',payloadKg,'nodes',payloadNodes(:).','model',model, ...
        'selection',fieldOr(c.payload,'selection',struct()),'weights',payloadWeights);
    c.payloadKg = payloadKg; c.payloadModel = model;
else
    c.payload = struct('massKg',0,'nodes',zeros(1,0),'model',"none",'selection',struct(),'weights',[]);
    c.payloadKg = 0; c.payloadModel = "none";
end

report(opts.Progress,'Normalizing and checking modes...');
if isfield(opts.MeshInfo,'surface'), surf = opts.MeshInfo.surface; else, surf = vil.extractSurface(geometry); end
db = vil.buildModalDatabase(mesh.Nodes,mesh.Elements,Phi,omega,M,K,free,c,surf);
db.fixedNodes = fixed(:);
db.rigidBodyHz = rigidHz;
% K and M stay out of db (size). mats serves residual flexibility (M is the
% total mass matrix, payload included) and, through Mstructure, reuse of the
% assembly in a payload sweep.
if nargout > 1
    mats = struct('K',K,'M',M,'free',free(:),'Mstructure',Mstruct,'E',c.E,'nu',c.nu,'rho',c.rho,'numNodes',n);
end
db.meshInfo = rmfieldIfPresent(opts.MeshInfo,'surface');
db.span = (max(mesh.Nodes,[],2)-min(mesh.Nodes,[],2)).';
% Masses: totalMass (and every participation factor) uses M_total, so the
% modal effective masses of FRF/flight sum towards structure + payload.
ex = zeros(3*n,1); ex(1:n) = 1;
db.structureMass = full(ex.'*Mstruct*ex);
db.payloadMass = payloadKg;
db.payload = c.payload;
db.tipNodes = payloadNodes(:);
end

function v = fieldOr(s,f,default)
if isstruct(s) && isfield(s,f), v = s.(f); else, v = default; end
end

function s = rmfieldIfPresent(s,f)
if isfield(s,f), s = rmfield(s,f); end
end

function report(progress,msg)
if isempty(progress), return; end
progress(msg);
end
