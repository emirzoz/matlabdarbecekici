function db = projectSettings(db)
% Normalize a modal database of any version and describe how it was solved.
% Adds db.payloadMass, db.structureMass and db.payload when missing, and
% db.config.settings: material, units, supports, payload, mesh and modes, in
% the form the app restores its controls from. Older payload studies stored
% payloadKg/payloadModel/tipZ/endPlaneTolerance in config, tipNodes in db and
% the root clamp as fixedNodes with empty fixedFaces; those are recognised,
% and a stored node list is re-expressed as a coordinate plane only if that
% plane selects exactly the same nodes.
c = db.config;
n = size(db.nodes,2);
if ~isfield(c,'fixedFaces'), c.fixedFaces = []; end
if ~isfield(c,'boundary'), c.boundary = "clamped"; end
boundary = string(c.boundary);

% ---- payload -------------------------------------------------------------------
if isfield(db,'payload') && isstruct(db.payload) && isfield(db.payload,'massKg')
    p = db.payload;
elseif isfield(c,'payloadKg')
    nodes = zeros(1,0); if isfield(db,'tipNodes'), nodes = db.tipNodes(:).'; end
    model = "Translational point mass on the average translation of the attachment nodes";
    if isfield(c,'payloadModel'), model = string(c.payloadModel); end
    sel = struct();
    if isfield(c,'tipZ')
        tol = 1e-8; if isfield(c,'endPlaneTolerance'), tol = c.endPlaneTolerance; end
        sel = struct('method',"plane",'axis',3,'positionMm',1e3*c.tipZ,'toleranceMm',1e3*tol);
    end
    p = struct('massKg',c.payloadKg,'nodes',nodes,'model',model,'selection',sel);
else
    p = struct('massKg',0,'nodes',zeros(1,0),'model',"none",'selection',struct());
end
if ~isfield(p,'selection'), p.selection = struct(); end
db.payload = p;
db.payloadMass = p.massKg;
if ~isfield(db,'structureMass'), db.structureMass = db.totalMass-p.massKg; end
if ~isfield(db,'tipNodes'), db.tipNodes = p.nodes(:); end

% ---- supports ------------------------------------------------------------------
fixed = db.fixedNodes(:).';
if boundary == "free"
    sup = struct('method',"faces",'faces',[],'axis',3,'positionMm',0,'toleranceMm',0.05);
elseif isfield(c,'support') && isstruct(c.support) && isfield(c.support,'method')
    sup = c.support;
elseif ~isempty(c.fixedFaces)
    sup = struct('method',"faces",'faces',c.fixedFaces(:).','axis',3,'positionMm',0,'toleranceMm',0.05);
else
    sup = inferPlane(db.nodes,fixed,[0.05 0.01 0.1 0.5]);
end
sup = completeSelection(sup);
supNodes = fixed; if sup.method == "faces", supNodes = zeros(1,0); end
sup.nodes = supNodes;
sup.count = numel(fixed);

pay = struct('method',"plane",'faces',[],'axis',3,'positionMm',NaN,'toleranceMm',0.05);
if ~isempty(fieldnames(p.selection)), pay = p.selection; end
if p.massKg > 0 && (~isfield(pay,'method') || ~ismember(string(pay.method),["plane" "faces" "nodes"]))
    pay = inferPlane(db.nodes,p.nodes,[0.05 0.01 0.1 0.5]);
end
pay = completeSelection(pay);
if pay.method == "plane" && ~isempty(p.nodes) && isfinite(pay.positionMm)
    % A stored plane must still pick the stored nodes; otherwise keep the list.
    ids = find(abs(db.nodes(pay.axis,:)-pay.positionMm/1e3) <= pay.toleranceMm/1e3);
    if ~isequal(ids(:),p.nodes(:)), pay.method = "nodes"; end
end
pay.nodes = p.nodes(:).';
pay.count = numel(p.nodes);

% ---- material and mesh -----------------------------------------------------------
matName = "Custom"; if isfield(c,'materialName'), matName = string(c.materialName); end
mi = struct(); if isfield(db,'meshInfo'), mi = db.meshInfo; end
order = "quadratic"; if size(db.elements,1) == 4, order = "linear"; end
meshUnits = "m"; if isfield(mi,'units'), meshUnits = string(mi.units); end
mesher = ""; if isfield(mi,'mesher'), mesher = string(mi.mesher); end
name = ""; if isfield(db,'info') && isfield(db.info,'name'), name = string(db.info.name); end

settings = struct('version',1, ...
    'material',struct('name',matName,'E',c.E,'nu',c.nu,'rho',c.rho), ...
    'units',"SI: m, kg, s, N, Pa (lengths shown in mm)", ...
    'boundary',boundary,'support',sup, ...
    'payload',struct('enabled',p.massKg>0,'massKg',p.massKg,'method',pay.method,'faces',pay.faces, ...
        'axis',pay.axis,'positionMm',pay.positionMm,'toleranceMm',pay.toleranceMm,'nodes',pay.nodes, ...
        'count',pay.count,'model',string(p.model),'weights',weightsOf(p)), ...
    'mesh',struct('name',name,'order',order,'numNodes',n,'numElements',size(db.elements,2), ...
        'units',meshUnits,'mesher',mesher), ...
    'modes',struct('count',numel(db.omega),'rangeHz',c.rangeHz), ...
    'assumptions',"Linear elastic, isotropic; small vibrations about the unloaded state; no gravity preload; " + ...
        "payload as translational inertia only.");
c.settings = settings;
db.config = c;
end

function s = completeSelection(s)
d = struct('method',"faces",'faces',[],'axis',3,'positionMm',0,'toleranceMm',0.05);
for f = string(fieldnames(d)).'
    if ~isfield(s,f) || isempty(s.(f)) && f ~= "faces", s.(f) = d.(f); end
end
s.method = string(s.method);
if ischar(s.axis) || isstring(s.axis), s.axis = find('XYZ'==upper(char(s.axis))); end
s = rmfieldIf(s,["nodes" "count" "description"]);
end

function s = rmfieldIf(s,f)
for k = f, if isfield(s,k), s = rmfield(s,k); end, end
end

function sel = inferPlane(X,ids,tolerances)
% A node list that lies on one coordinate plane and is exactly what a plane
% selection with a round tolerance returns is reported as that plane.
sel = struct('method',"nodes",'faces',[],'axis',3,'positionMm',0,'toleranceMm',0.05);
if isempty(ids), return, end
P = X(:,ids); spread = max(P,[],2)-min(P,[],2);
[~,ax] = min(spread);
sel.axis = ax;
for pos = unique([round(1e3*median(P(ax,:)),2) round(1e3*mean(P(ax,:)),3)])
    for tol = tolerances
        hit = find(abs(X(ax,:)-pos/1e3) <= tol/1e3);
        if isequal(hit(:),sort(ids(:)))
            sel.method = "plane"; sel.positionMm = pos; sel.toleranceMm = tol; return
        end
    end
end
sel.positionMm = round(1e3*median(P(ax,:)),3);
end

function w = weightsOf(p)
% Non-uniform payload weights ([] = uniform average).
w = []; if isfield(p,'weights'), w = p.weights; end
end
