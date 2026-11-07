function [geometry,info,meshInfo,model] = importModel(filename,units,opts)
% Import a solver input file with its set-up: mesh, material, supports and
% point mass, ready to solve without picking anything.
%   Abaqus: .inp (keywords *NODE, *ELEMENT, ...), flat or Abaqus/CAE.
%   Ansys:  .cdb, .dat (Workbench ds.dat), APDL .inp/.mac.
% units: "auto" (default; /UNITS in Ansys files, else from Young's modulus),
%   "SI" (m, kg, s, Pa) or "mm-t-s" (mm, tonne, s, MPa).
% model: E, nu, rho (SI), materialName, boundary ("clamped" | "free"),
%   fixedNodes (new node IDs with Ux=Uy=Uz=0), payload (massKg, nodes,
%   weights: [] for a uniform average), nModes, rangeHz, notes, units.
% Nodes are renumbered 1..N in ascending file order over the solid elements;
% reference nodes (payload points) are not mesh nodes. Supports must fix all
% three translations (vil:PartialBoundary otherwise); a point mass must sit on
% a mesh node or be tied to mesh nodes by averaging equations (*EQUATION, CE),
% a distributing coupling, RBE3 or a deformable remote point.
arguments
    filename
    units (1,1) string {mustBeMember(units,["auto" "SI" "mm-t-s"])} = "auto"
    opts.Progress = []
end
filename = char(filename);
assert(isfile(filename),'vil:FileNotFound','File not found: %s',filename);
[~,name,ext] = fileparts(filename);
fmt = detectFormat(filename,lower(ext));
if fmt == "Abaqus", R = vil.readAbaqus(filename,opts.Progress); else, R = vil.readAnsys(filename,opts.Progress); end
notes = R.notes;

% ---- mesh: renumber the solid nodes 1..N ----------------------------------
nn = cellfun(@(c)size(c,1),R.conn);
assert(all(nn == nn(1)),'vil:MeshElements','The mesh mixes linear and quadratic tetrahedra.');
Tk = cell2mat(R.conn);
keys = unique(Tk(:)).';
[found,loc] = ismember(keys,R.nodeKey);
assert(all(found),'vil:Format','Element node %d is not defined.',keys(find(~found,1)));
[~,T] = ismember(Tk,keys);
Xf = R.X(:,loc);

% ---- units ------------------------------------------------------------------
[f,unitText] = chooseUnits(units,R);
X = f.L*Xf;
E = f.P*R.material.E; rho = f.rho*R.material.rho; nu = R.material.nu;
[geometry,meshInfo,surf] = vil.meshFromArrays(X,T,string([name ext]),Progress=opts.Progress); %#ok<ASGLU>
meshInfo.units = f.name; meshInfo.scale = f.L; meshInfo.fileNodeIds = keys;
meshInfo.mesher = sprintf("Imported %s model (%s, %s): %s",fmt,meshInfo.order,strjoin(unique(R.elemType),"/"),[name ext]);
toNew = @(k) mapKeys(k,keys);

% ---- supports -------------------------------------------------------------------
bc = R.bcs; bc = bc(bc(:,2) <= 3,:);
onMesh = ismember(bc(:,1),keys);
offMesh = unique(bc(~onMesh,1)).';
mask = false(numel(keys),3);
if any(onMesh)
    id = toNew(bc(onMesh,1)); mask(sub2ind(size(mask),id(:),bc(onMesh,2))) = true;
end
some = any(mask,2); full = all(mask,2); part = some & ~full;
if any(part)
    k = find(part,1);
    error('vil:PartialBoundary',['%d node(s) are fixed in only some directions (e.g. file node %d: %s fixed). ' ...
        'Only full supports (Ux = Uy = Uz = 0) are supported: symmetry and roller supports are not.'], ...
        nnz(part),keys(k),strjoin("U"+string(find(mask(k,:))),", "));
end
fixedNodes = find(full).';
boundary = "clamped"; if isempty(fixedNodes), boundary = "free"; end
supportNote = "none (free-free)";
if ~isempty(fixedNodes)
    supportNote = sprintf("%s: %d nodes, Ux = Uy = Uz = 0",strjoin(unique(R.bcSource),", "),numel(fixedNodes));
end

% ---- payload ----------------------------------------------------------------------
payload = struct('massKg',0,'nodes',zeros(1,0),'weights',[],'note',"none",'refNode',NaN);
usedEq = false(1,numel(R.equations)); usedCp = false(1,numel(R.couplings));
if ~isempty(R.masses)
    [mk,~,g] = unique(R.masses(:,1)); mm = accumarray(g,R.masses(:,2)).';
    assert(isscalar(mk),'vil:Payload',['The file has point masses on %d different nodes (%s). One payload mass ' ...
        'is supported: merge them into one point mass.'],numel(mk),mat2str(mk.'));
    m = f.M*mm;
    assert(m > 0,'vil:Payload','The point mass must be positive (got %g).',mm);
    if ismember(mk,keys)
        nodes = toNew(mk); w = 1; how = sprintf("on mesh node %d",mk);
    else
        assert(~ismember(mk,offMesh),'vil:Payload','The payload reference node %d is itself fixed by a support.',mk);
        cp = find(arrayfun(@(c)isequal(c.ref,mk),R.couplings));
        if ~isempty(cp)
            c = R.couplings(cp(1)); usedCp(cp(1)) = true;
            assert(all(ismember(c.nodes,keys)),'vil:Payload','Coupling %s refers to nodes outside the solid mesh.',c.source);
            nodes = toNew(c.nodes); w = ones(1,numel(nodes))/numel(nodes);
            how = sprintf("%s on node %d, %d coupled nodes, uniform weights",c.source,mk,numel(nodes));
            if contains(c.kind,"areaweighted")
                notes(end+1) = "The coupling is defined on an element surface: Abaqus/Ansys weight such couplings by " + ...
                    "tributary area, here the nodes are weighted uniformly. On an uneven mesh the frequencies can differ slightly.";
            elseif ~contains(c.kind,"UNIFORM")
                notes(end+1) = "Coupling weighting " + c.kind + " is replaced by uniform weights.";
            end
        else
            [nodesK,w,usedEq] = fromEquations(mk,R.equations,usedEq);
            assert(all(ismember(nodesK,keys)),'vil:Payload','The payload equations refer to nodes outside the solid mesh.');
            nodes = toNew(nodesK);
            how = sprintf("on reference node %d, tied by 3 equations to the average translation of %d nodes",mk,numel(nodes));
        end
    end
    [nodes,o] = sort(nodes); w = w(o);
    clash = intersect(nodes,fixedNodes);
    assert(isempty(clash),'vil:PayloadOnSupport','%d payload attachment node(s) are also fixed by a support.',numel(clash));
    uniform = max(abs(w-1/numel(w))) <= 1e-9/numel(w);
    if uniform, w = []; else, how = how + " (non-uniform weights)"; end
    payload = struct('massKg',m,'nodes',nodes,'weights',w, ...
        'note',sprintf("%.6g kg %s",m,how),'refNode',mk);
    if ~isempty(R.massSource), payload.note = payload.note + " [" + strjoin(R.massSource,", ") + "]"; end
end
if any(~usedEq)
    error('vil:Unsupported',['The file has %d constraint equation(s) that do not tie the payload mass to the part. ' ...
        'General multi-point constraints are not supported.'],nnz(~usedEq));
end
if any(~usedCp)
    error('vil:Unsupported',['Coupling/remote point %s carries no point mass. Remote supports and remote ' ...
        'points without a mass are not supported.'],R.couplings(find(~usedCp,1)).source);
end
if ~isempty(offMesh)
    notes(end+1) = sprintf("Supports on %d node(s) outside the solid mesh ignored.",numel(offMesh));
end

model = struct('E',E,'nu',nu,'rho',rho,'materialName',string(R.material.name),'boundary',boundary, ...
    'fixedNodes',fixedNodes,'supportNote',supportNote,'payload',payload,'nModes',R.nModes, ...
    'rangeHz',R.rangeHz,'notes',notes,'units',f.name,'format',fmt);

span = max(X,[],2)-min(X,[],2);
info = struct('file',filename,'name',[name ext],'format',upper(fmt),'fileUnits',f.name, ...
    'scaleApplied',f.L,'scaleNote',unitText,'bboxMin',min(X,[],2).','bboxMax',max(X,[],2).', ...
    'span',span.','numFaces',geometry.NumFaces,'numCells',geometry.NumCells, ...
    'source',fmt + " input file",'importNotes',notes);
end

% ---------------------------------------------------------------- helpers ---
function [nodes,w,used] = fromEquations(ref,eqs,used)
% Payload tied by u_ref,d = sum_i w_i u_i,d (one equation per direction).
nodes = []; W = [];
for d = 1:3
    hit = find(cellfun(@(e)any(e(:,1) == ref & e(:,2) == d),eqs) & ~used);
    assert(~isempty(hit),'vil:Payload',['The point mass on node %d is not connected to the part in direction %d: ' ...
        'tie it with an equation per direction, a distributing coupling or RBE3.'],ref,d);
    e = eqs{hit(1)}; used(hit(1)) = true;
    r = e(:,1) == ref; a = e(r,3);
    assert(isscalar(a) && a ~= 0,'vil:Payload','Equation for node %d direction %d is not an average.',ref,d);
    o = e(~r,:);
    assert(all(o(:,2) == d),'vil:Unsupported','The payload equation for direction %d mixes directions.',d);
    [nk,ord] = sort(o(:,1).'); wk = -o(ord,3).'/a;
    assert(abs(sum(wk)-1) <= 1e-6,'vil:Payload',['The payload equation for direction %d does not average ' ...
        '(weights sum to %.6g, not 1).'],d,sum(wk));
    assert(all(wk > 0),'vil:Payload','The payload equation for direction %d has negative weights.',d);
    if d == 1, nodes = nk; W = wk;
    else
        assert(isequal(nk,nodes) && max(abs(wk-W)) <= 1e-9,'vil:Payload', ...
            'The payload equations tie different nodes or weights in different directions.');
    end
end
w = W;
end

function id = mapKeys(k,keys)
[tf,id] = ismember(k,keys);
assert(all(tf),'vil:Format','Node %d is not a node of the solid mesh.',k(find(~tf,1)));
id = reshape(id,1,[]);
end

function [f,txt] = chooseUnits(units,R)
E = R.material.E; rho = R.material.rho;
why = "";
if units == "auto"
    if R.unitsHint ~= ""
        units = R.unitsHint; why = "from /UNITS in the file";
    elseif E >= 1e8
        units = "SI"; why = sprintf("Young's modulus %.4g looks like Pa",E);
    elseif E >= 1e2 && E < 1e7
        units = "mm-t-s"; why = sprintf("Young's modulus %.4g looks like MPa",E);
    else
        error('vil:Units',['Cannot tell the unit system from Young''s modulus %.4g. Choose SI (m, kg, s, Pa) ' ...
            'or mm-t-s (mm, tonne, s, MPa) for the import.'],E);
    end
else
    why = "chosen by the user";
end
if units == "SI"
    f = struct('name',"SI",'L',1,'M',1,'P',1,'rho',1);
    ok = rho >= 1 && rho <= 1e5;
else
    f = struct('name',"mm-t-s",'L',1e-3,'M',1e3,'P',1e6,'rho',1e12);
    ok = rho >= 1e-12 && rho <= 1e-7;
end
if ~ok
    error('vil:Units',['Density %.4g does not fit the %s unit system (E = %.4g). The file seems to mix units: ' ...
        'in SI the density is in kg/m^3 (e.g. 2700), in mm-t-s in tonne/mm^3 (e.g. 2.7e-9).'],rho,f.name,E);
end
txt = sprintf("Units: %s (%s). Converted to SI: E %.4g GPa, density %.6g kg/m^3.",f.name,why,f.P*E/1e9,f.rho*rho);
end

function fmt = detectFormat(filename,ext)
if ismember(ext,[".cdb" ".dat" ".mac" ".ans" ".db_input"]), fmt = "Ansys"; return, end
fid = fopen(filename,'r'); c = onCleanup(@()fclose(fid));
head = string(fread(fid,[1 200000],'*char'));
if ~isempty(regexp(head,'^\s*\*(heading|node|element|part|include|material|preprint)\>','once','ignorecase','lineanchors'))
    fmt = "Abaqus";
elseif ~isempty(regexp(head,'^\s*(nblock|eblock|/prep7|et\s*,|/batch|/title|n\s*,)','once','ignorecase','lineanchors'))
    fmt = "Ansys";
else
    error('vil:Format','%s is neither an Abaqus input file (*NODE, *ELEMENT) nor an Ansys input file (NBLOCK, EBLOCK).',filename);
end
end
