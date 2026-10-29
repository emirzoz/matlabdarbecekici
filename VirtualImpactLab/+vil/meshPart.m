function [geometry,meshInfo] = meshPart(geometry,hmax,opts)
% Quadratic tetrahedral mesh with automatic refinement retries.
% The mesher fails on coarse Hmax for parts with small features (seen on
% bearing-housing.step at Hmax = span/12), so Hmax is reduced until it works.
arguments
    geometry
    hmax (1,1) double {mustBePositive} = vil.suggestMeshSize(geometry)
    opts.Order (1,1) string {mustBeMember(opts.Order,["quadratic","linear"])} = "quadratic"
    opts.MaxNodes (1,1) double {mustBePositive} = 250e3
    opts.Retries (1,1) double {mustBeInteger,mustBeNonnegative} = 5
    opts.Progress = []
end
[meshed,h,lastErr] = tryMesh(geometry,hmax,opts);
fromTessellation = false;
if ~isempty(lastErr)
    % Some STEP parts (bearing-housing.step) never mesh from their B-rep, at
    % any Hmax/Hmin. Their surface tessellation is watertight, though, and
    % re-importing it as STL meshes reliably. Curved faces become faceted and
    % face IDs change, so this runs before fixed faces are chosen.
    report(opts.Progress,'CAD mesher failed; rebuilding the solid from its surface tessellation...');
    stl = [tempname '.stl'];
    cleanup = onCleanup(@()deleteIfPresent(stl));
    stlwrite(triangulation(geometry),stl);
    [meshed,h,stlErr] = tryMesh(fegeometry(stl),hmax,opts);
    if ~isempty(stlErr)
        error('vil:MeshFailed',['Meshing failed down to Hmax = %.4g mm, both from CAD (%s) ' ...
            'and from its tessellation (%s).'],1e3*h,lastErr.message,stlErr.message);
    end
    fromTessellation = true;
end
geometry = meshed;
mesh = geometry.Mesh;
nNodes = size(mesh.Nodes,2);
if nNodes > opts.MaxNodes
    error('vil:MeshTooLarge',['Mesh has %d nodes (limit %d). Increase the element size; ' ...
        'large meshes exceed MATLAB Online memory during the modal solve.'],nNodes,opts.MaxNodes);
end
surf = vil.extractSurface(geometry);
meshInfo = struct('hmaxRequested',hmax,'hmaxUsed',h,'order',opts.Order, ...
    'numNodes',nNodes,'numElements',size(mesh.Elements,2), ...
    'numDofs',3*nNodes,'fromTessellation',fromTessellation, ...
    'numFaces',geometry.NumFaces,'surface',surf);
end

function [geometry,h,lastErr] = tryMesh(geometry,hmax,opts)
h = hmax; lastErr = [];
for attempt = 0:opts.Retries
    try
        report(opts.Progress,sprintf('Meshing with Hmax = %.4g mm...',1e3*h));
        geometry = generateMesh(geometry,Hmax=h,GeometricOrder=opts.Order);
        lastErr = []; return
    catch err
        lastErr = err; h = 0.7*h;
    end
end
h = h/0.7;
end

function deleteIfPresent(f)
if isfile(f), delete(f); end
end

function report(progress,msg)
if isempty(progress), return; end
progress(msg);
end
