function db = solveModes(geometry,c,opts)
% Modal solve on a meshed fegeometry; returns the reusable modal database.
% c: E, nu, rho (SI), fixedFaces (face IDs), rangeHz [lo hi].
% If fewer than MinModes modes lie below rangeHz(2), the upper limit is
% widened up to MaxHz, since small stiff parts often have
% their first mode far above a default band (corner-bracket-2020: >20 kHz).
arguments
    geometry
    c struct
    opts.MinModes (1,1) double {mustBeInteger,mustBeNonnegative} = 6
    opts.MaxHz (1,1) double {mustBePositive} = 2e5
    opts.Progress = []
    opts.MeshInfo struct = struct()
end
validateattributes(c.rangeHz,{'numeric'},{'vector','numel',2,'nonnegative','increasing'});
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
span = max(mesh.Nodes,[],2)-min(mesh.Nodes,[],2);

lo = c.rangeHz(1); hi = c.rangeHz(2);
while true
    report(opts.Progress,sprintf('Solving modes %.4g to %.4g Hz (%d DOF)...',lo,hi,3*size(mesh.Nodes,2)));
    result = solve(model,FrequencyRange=2*pi*[max(lo,0) hi]);
    omega = result.NaturalFrequencies(:);
    nFound = numel(omega);
    if nFound >= opts.MinModes || hi >= opts.MaxHz, break; end
    if nFound == 0
        hi = min(4*hi,opts.MaxHz);
    else
        % Solid modal density grows roughly as f^3; aim just past MinModes
        % instead of overshooting by 4x, which was costly on STEP parts.
        hi = min(1.15*hi*(opts.MinModes/nFound)^(1/3),opts.MaxHz);
        hi = max(hi,1.1*omega(end)/(2*pi));
    end
end
if isempty(omega)
    error('vil:NoModes', ...
        ['No modes were found between %.6g and %.6g Hz. Mesh size is %s m: check ' ...
         'that this matches the real part, and check density, stiffness and the fixed faces.'], ...
         lo,hi,mat2str(span.',4));
end
c.rangeHz = [lo hi];
shapes = result.ModeShapes;
Phi = [shapes.ux;shapes.uy;shapes.uz];   % component-blocked: all X, all Y, all Z
assert(size(Phi,2)==numel(omega),'vil:ModeCount','Mode shape count differs from frequency count.');

report(opts.Progress,'Assembling M and K for mass normalization checks...');
A = assembleFEMatrices(model);
n = size(mesh.Nodes,2);
fixed = unique(cell2mat(arrayfun(@(f)findNodes(mesh,'region','Face',f),faces,'UniformOutput',false)));
free = setdiff(1:3*n,[fixed fixed+n fixed+2*n]);
if isfield(opts.MeshInfo,'surface'), surf = opts.MeshInfo.surface; else, surf = vil.extractSurface(model.Geometry); end
db = vil.buildModalDatabase(mesh.Nodes,mesh.Elements,Phi,omega,A.M,A.K,free,c,surf);
db.fixedNodes = fixed(:);
db.meshInfo = rmfieldIfPresent(opts.MeshInfo,'surface');
db.span = span.';
end

function s = rmfieldIfPresent(s,f)
if isfield(s,f), s = rmfield(s,f); end
end

function report(progress,msg)
if isempty(progress), return; end
progress(msg);
end
