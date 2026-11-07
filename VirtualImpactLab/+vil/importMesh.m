function [geometry,info,meshInfo] = importMesh(filename,units,opts)
% Import a ready tetrahedral volume mesh (no remeshing) as an fegeometry in metres.
% filename: a .mat file holding either
%   nodes (N x 3 or 3 x N) and elements (E x 4|10 or 4|10 x E), 1-based,
%   e.g. the TetGen meshes written by the TPMS study (*_tetmesh.mat), or
%   db (a Virtual Impact Lab project), whose mesh is reused.
% units: "auto" (default), "m" or "mm". Auto takes, in order: a 'units'
%   variable in the file; agreement of the mesh volume with a tetVolume_mm3
%   variable; else millimetres if the largest dimension exceeds 2.
% Checks: sizes, integer connectivity inside 1..N, repeated nodes in an
%   element, positive element volumes (a mesh with every element inverted is
%   reordered), and that fegeometry keeps the node numbering, because supports
%   and payload nodes are stored by node ID.
arguments
    filename
    units (1,1) string {mustBeMember(units,["auto" "m" "mm"])} = "auto"
    opts.Progress = []
end
filename = char(filename);
assert(isfile(filename),'vil:FileNotFound','File not found: %s',filename);
[~,name,ext] = fileparts(filename);
assert(strcmpi(ext,'.mat'),'vil:Format','Mesh files must be .mat (nodes + elements, or a VIL project).');
report(opts.Progress,'Reading the mesh file...');
vars = whos('-file',filename);
names = string({vars.name});
source = "nodes/elements";
if all(ismember(["nodes" "elements"],names))
    S = load(filename,'nodes','elements');
    X = S.nodes; T = S.elements;
elseif ismember("db",names)
    S = load(filename,'db');
    assert(isfield(S.db,'nodes') && isfield(S.db,'elements'),'vil:Format','%s holds no mesh.',[name ext]);
    X = S.db.nodes; T = S.db.elements; source = "VIL project mesh";
else
    error('vil:Format',['%s must contain variables "nodes" and "elements" (or a VIL project "db"). ' ...
        'Found: %s.'],[name ext],strjoin(names,', '));
end
extra = struct();
for v = ["units" "tetVolume_mm3" "surfaceVolume_mm3"]
    if ismember(v,names), t = load(filename,v); extra.(v) = t.(v); end
end

% ---- orientation and connectivity -----------------------------------------
assert(isnumeric(X) && ismatrix(X) && isreal(X) && all(isfinite(X(:))),'vil:MeshNodes', ...
    'Node coordinates must be a real, finite numeric matrix.');
if size(X,2) == 3 && size(X,1) ~= 3, X = X.';
elseif size(X,1) ~= 3, error('vil:MeshNodes','Nodes must be N x 3 or 3 x N (got %s).',mat2str(size(X)));
end
X = double(X); n = size(X,2);
assert(isnumeric(T) && ismatrix(T),'vil:MeshElements','Elements must be a numeric matrix.');
if ismember(size(T,2),[4 10]) && ~ismember(size(T,1),[4 10]), T = T.'; end
assert(ismember(size(T,1),[4 10]),'vil:MeshElements', ...
    'Elements must be E x 4 (linear) or E x 10 (quadratic) tetrahedra (got %s).',mat2str(size(T)));
T = double(T);
assert(all(T(:) == round(T(:))),'vil:MeshElements','Element connectivity must hold integer node IDs.');
lo = min(T(:)); hi = max(T(:));
if lo == 0
    error('vil:MeshElements',['Element connectivity starts at node 0: the file is 0-based. ' ...
        'Add 1 to every element index before importing.']);
end
assert(lo >= 1 && hi <= n,'vil:MeshElements', ...
    'Element connectivity refers to node %d, but the file has nodes 1 to %d.',max(hi,lo),n);
order = "linear"; if size(T,1) == 10, order = "quadratic"; end

% ---- units ------------------------------------------------------------------
a = X(:,T(2,:))-X(:,T(1,:)); b = X(:,T(3,:))-X(:,T(1,:)); c = X(:,T(4,:))-X(:,T(1,:));
vol1 = dot(a,cross(b,c,1),1)/6;     % in file units^3
[scale,unitNote] = chooseScale(units,X,vol1,extra);
X = scale*X;

% ---- mesh checks and geometry ---------------------------------------------------
[geometry,meshInfo] = vil.meshFromArrays(X,T,string([name ext]),Progress=opts.Progress);
span = max(X,[],2)-min(X,[],2);
info = struct('file',filename,'name',[name ext],'format',"MESH",'fileUnits',unitNote.unit, ...
    'scaleApplied',scale,'scaleNote',unitNote.text,'bboxMin',min(X,[],2).','bboxMax',max(X,[],2).', ...
    'span',span.','numFaces',geometry.NumFaces,'numCells',geometry.NumCells,'source',source);
meshInfo.units = unitNote.unit; meshInfo.scale = scale;
if max(span) < 1e-3 || max(span) > 20
    warning('vil:Size','Mesh size %s m looks implausible; check the units.',mat2str(span.',4));
end
end

function [scale,note] = chooseScale(units,X,vol,extra)
span = max(X,[],2)-min(X,[],2);
V = abs(sum(vol));
factor = struct('m',1,'mm',1e-3);
if units ~= "auto"
    scale = factor.(units);
    note = struct('unit',units,'text',"Mesh units set to " + units + " by the user.");
else
    if isfield(extra,'units') && ismember(string(extra.units),["m" "mm"])
        unit = string(extra.units); why = "the file's 'units' variable";
    elseif isfield(extra,'tetVolume_mm3') && isscalar(extra.tetVolume_mm3) && extra.tetVolume_mm3 > 0
        % Mesh volume in mm^3 under each hypothesis, against the stored value.
        err = abs([V*1e9 V]/extra.tetVolume_mm3-1);
        [best,k] = min(err); cand = ["m" "mm"]; unit = cand(k);
        why = sprintf("the stored tetVolume_mm3 = %.6g (mesh volume matches to %.2g %%)",extra.tetVolume_mm3,100*best);
        if best > 0.01, unit = ""; end
    else
        unit = "";
    end
    if unit == ""
        if max(span) > 2, unit = "mm"; why = "largest dimension > 2, so millimetres were assumed";
        else, unit = "m"; why = "largest dimension <= 2, so metres were assumed"; end
    end
    scale = factor.(unit);
    note = struct('unit',unit,'text',"Mesh units: " + unit + " (auto, from " + why + ").");
end
if isfield(extra,'tetVolume_mm3') && isscalar(extra.tetVolume_mm3) && extra.tetVolume_mm3 > 0
    check = 1e9*V*scale^3/extra.tetVolume_mm3-1;
    if abs(check) > 0.01
        note.text = note.text + sprintf(" WARNING: mesh volume differs from tetVolume_mm3 by %.3g %%: check the units.",100*check);
    end
end
end

function report(progress,msg)
if isempty(progress), return; end
progress(msg);
end
