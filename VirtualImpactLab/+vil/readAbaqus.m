function R = readAbaqus(filename,progress)
% Read the parts of an Abaqus/Standard input file that a modal model needs.
% Handles flat files and Abaqus/CAE files (*Part / *Assembly / *Instance with
% translation and rotation, one instance), *INCLUDE, *NODE, *ELEMENT (C3D4*,
% C3D10*, MASS, ROTARYI), *NSET/*ELSET (GENERATE, INSTANCE=, ELSET=),
% *SURFACE (ELEMENT faces S1-S4, NODE), *MATERIAL/*ELASTIC/*DENSITY,
% *SOLID SECTION, *BOUNDARY (model level and the first *FREQUENCY step),
% *MASS, *EQUATION, *COUPLING with *DISTRIBUTING or *KINEMATIC, *FREQUENCY.
% Returns the raw model (file units, file node IDs as keys) for importModel.
% Keywords that change stiffness or mass and are not modelled raise
% vil:Unsupported instead of being skipped.
if nargin < 2, progress = []; end
report(progress,'Reading the Abaqus input file...');
L = readLines(filename,0);
L = strtrim(L);
L = L(strlength(L) > 0 & ~startsWith(L,"**"));
isKw = startsWith(L,"*");
keyIdx = find(isKw); keyIdx(end+1) = numel(L)+1;

AS = 1e9;                       % key offset of assembly-level node/element IDs
R = struct('format',"Abaqus",'nodeKey',zeros(1,0),'X',zeros(3,0),'conn',{{}},'elemType',strings(1,0), ...
    'elemKey',{{}},'masses',zeros(0,2),'bcs',zeros(0,2),'equations',{{}},'couplings',struct('ref',{},'nodes',{},'kind',{},'source',{}), ...
    'material',struct('E',NaN,'nu',NaN,'rho',NaN,'name',""),'unitsHint',"",'nModes',NaN,'rangeHz',[0 0], ...
    'notes',strings(1,0),'bcSource',strings(1,0),'massSource',strings(1,0));
nodeBlocks = {}; nodeScope = {};
nsets = containers.Map('KeyType','char','ValueType','any');
elsets = containers.Map('KeyType','char','ValueType','any');
surfaces = containers.Map('KeyType','char','ValueType','any');
blkEk = {}; blkNk = {};          % element keys and node keys per *ELEMENT block (lookup for sets and surfaces)
massElsets = {}; massValues = {}; materials = struct(); sections = {};
instances = containers.Map('KeyType','char','ValueType','any');
scope = "model"; partName = ""; inStep = false; stepFreq = false; freqSeen = false;
skippedStepBcs = 0; curMat = ""; pendingCoupling = []; pendingSurfaceCoupling = false;
nParts = 0; mainPart = "";

for q = 1:numel(keyIdx)-1
    line = L(keyIdx(q)); data = L(keyIdx(q)+1:keyIdx(q+1)-1);
    [kw,op] = parseKeyword(line);
    switch kw
        case "HEADING"
        case "PART"
            nParts = nParts+1; partName = lower(opt(op,'name',"part")); scope = partName;
            if mainPart == "", mainPart = partName; end
            assert(nParts == 1,'vil:Assembly',['%s defines more than one part. Only single parts are supported ' ...
                '(no assemblies): export one part with its supports and mass.'],fname(filename));
        case "ENDPART"
            scope = "model";
        case "ASSEMBLY"
            scope = "assembly";
        case "ENDASSEMBLY"
            scope = "model";
        case "INSTANCE"
            nm = lower(opt(op,'name',"")); pt = lower(opt(op,'part',""));
            assert(instances.Count == 0,'vil:Assembly','%s has more than one *Instance: only single parts are supported.',fname(filename));
            tr = struct('part',pt,'shift',[0;0;0],'rot',[]);
            if numel(data) >= 1, v = nums(data(1)); if numel(v) >= 3, tr.shift = v(1:3).'; end, end
            if numel(data) >= 2, v = nums(data(2)); if numel(v) >= 7 && v(7) ~= 0, tr.rot = v(1:7); end, end
            instances(char(nm)) = tr;
        case "ENDINSTANCE"
        case "NODE"
            v = nums(data); v = reshape(v,4,[]);     % id, x, y, z (2D and 6-field nodes are not supported)
            off = offsetOf(scope); keys = v(1,:)+off;
            nodeBlocks{end+1} = [keys; v(2:4,:)]; nodeScope{end+1} = scope; %#ok<AGROW>
            if hasOpt(op,'nset'), addSet(nsets,setKey(scope,opt(op,'nset')),keys); end
        case "ELEMENT"
            ty = upper(opt(op,'type',""));
            if startsWith(ty,"C3D10"), nn = 10; elseif startsWith(ty,"C3D4"), nn = 4;
            elseif ty == "MASS" || ty == "ROTARYI", nn = 1;
            else
                error('vil:ElementType',['%s uses element type %s. Only solid tetrahedra (C3D4*, C3D10*) and ' ...
                    'point masses (MASS) are supported; mesh the part with tetrahedra.'],fname(filename),ty);
            end
            v = nums(data);
            assert(mod(numel(v),nn+1) == 0,'vil:Format','*ELEMENT, TYPE=%s: the data does not hold %d nodes per element.',ty,nn);
            v = reshape(v,nn+1,[]); off = offsetOf(scope);
            ek = v(1,:)+off; nk = v(2:end,:)+off;
            blkEk{end+1} = ek; blkNk{end+1} = nk; %#ok<AGROW>
            if nn > 1
                R.conn{end+1} = nk; R.elemType(end+1) = ty; R.elemKey{end+1} = ek;
            elseif ty == "ROTARYI"
                R.notes(end+1) = "ROTARYI elements ignored: no rotary inertia is modelled.";
            end
            if hasOpt(op,'elset'), addSet(elsets,setKey(scope,opt(op,'elset')),ek); end
            if ty == "MASS" && ~hasOpt(op,'elset')
                error('vil:Format','*ELEMENT, TYPE=MASS needs ELSET= so that *MASS can refer to it.');
            end
        case "NSET"
            keys = setMembers(data,op,scope,nsets,true);
            if hasOpt(op,'elset')
                es = resolveSet(elsets,opt(op,'elset'),scope,instances,'element');
                en = elemNodes(es); keys = unique(cell2mat(en(:)).');
            end
            addSet(nsets,setKey(scope,opt(op,'nset')),keys);
        case "ELSET"
            keys = setMembers(data,op,scope,elsets,false);
            addSet(elsets,setKey(scope,opt(op,'elset')),keys);
        case "SURFACE"
            ty = upper(opt(op,'type',"ELEMENT"));
            surfaces(char(setKey(scope,opt(op,'name')))) = struct('type',ty,'data',data,'scope',scope,'inst',opt(op,'instance',""));
        case "MATERIAL"
            curMat = lower(opt(op,'name',"material"));
            materials.(matlab.lang.makeValidName(curMat)) = struct('name',opt(op,'name',"material"),'E',NaN,'nu',NaN,'rho',NaN);
        case "ELASTIC"
            ty = upper(opt(op,'type',"ISOTROPIC"));
            assert(ty == "ISOTROPIC",'vil:Unsupported','*ELASTIC, TYPE=%s: only isotropic materials are supported.',ty);
            v = nums(data(1)); f = matlab.lang.makeValidName(curMat);
            materials.(f).E = v(1); materials.(f).nu = v(2);
            if numel(data) > 1, R.notes(end+1) = "Temperature-dependent *ELASTIC: the first line is used."; end
        case "DENSITY"
            v = nums(data(1)); f = matlab.lang.makeValidName(curMat); materials.(f).rho = v(1);
        case "SOLIDSECTION"
            sections{end+1} = struct('elset',opt(op,'elset'),'material',lower(opt(op,'material')),'scope',scope); %#ok<AGROW>
        case "MASS"
            v = nums(data(1));
            massElsets{end+1} = struct('name',opt(op,'elset'),'scope',scope); massValues{end+1} = v(1); %#ok<AGROW>
        case "ROTARYINERTIA"
            R.notes(end+1) = "*ROTARY INERTIA ignored: no rotary inertia is modelled.";
        case "STEP"
            inStep = true; stepFreq = false;
        case "ENDSTEP"
            inStep = false;
        case "FREQUENCY"
            if ~freqSeen
                freqSeen = true; stepFreq = true;
                if ~isempty(data)
                    t = strtrim(split(data(1),","));
                    nm = str2double(t(1)); if isfinite(nm), R.nModes = nm; end
                    if numel(t) >= 3, hi = str2double(t(3)); if isfinite(hi), R.rangeHz = [0 hi]; end, end
                end
            end
        case "BOUNDARY"
            if inStep && ~stepFreq, skippedStepBcs = skippedStepBcs+1; continue, end
            if hasOpt(op,'type') && upper(opt(op,'type')) ~= "DISPLACEMENT"
                error('vil:Unsupported','*BOUNDARY, TYPE=%s is not supported in a modal model.',opt(op,'type'));
            end
            for d = data(:).'
                t = strtrim(split(d,",")); t = t(strlength(t) > 0);
                keys = nodeRefs(t(1),scope,nsets,instances);
                if numel(t) >= 2 && isnan(str2double(t(2)))
                    dofs = namedBoundary(upper(t(2)));
                else
                    a = str2double(t(2)); b = a; if numel(t) >= 3, b = str2double(t(3)); end
                    if ~isfinite(b), b = a; end
                    val = 0; if numel(t) >= 4, val = str2double(t(4)); end
                    if val ~= 0
                        error('vil:PrescribedMotion',['*BOUNDARY on %s prescribes %g (not 0). A modal model needs ' ...
                            'fixed (zero) supports only.'],t(1),val);
                    end
                    dofs = a:b;
                end
                [K,D] = ndgrid(keys,dofs);
                R.bcs = [R.bcs; K(:) D(:)];
                R.bcSource(end+1) = t(1);
            end
        case "EQUATION"
            tok = strtrim(split(strjoin(regexprep(data,',\s*$',''),","),","));
            k = 1;
            while k <= numel(tok)
                nt = str2double(tok(k)); k = k+1;
                terms = reshape(tok(k:k+3*nt-1),3,[]); k = k+3*nt;
                refs = arrayfun(@(s)nodeRefs(s,scope,nsets,instances),terms(1,:),'UniformOutput',false);
                len = cellfun(@numel,refs);
                assert(all(len == len(1)),'vil:Format','*EQUATION mixes node sets of different sizes.');
                for j = 1:len(1)
                    R.equations{end+1} = [cellfun(@(r)r(j),refs).' str2double(terms(2,:)).' str2double(terms(3,:)).'];
                end
            end
        case "COUPLING"
            pendingCoupling = struct('ref',opt(op,'refnode'),'surface',opt(op,'surface'),'scope',scope,'name',opt(op,'constraintname',"coupling"));
        case "KINEMATIC"
            error('vil:RigidTie',['Coupling "%s" is kinematic (rigid): it makes the attached region rigid, which this ' ...
                'model cannot represent. Use a distributing coupling (or *EQUATION averages) for the payload.'],pendingCoupling.name);
        case "DISTRIBUTING"
            assert(~isempty(pendingCoupling),'vil:Format','*DISTRIBUTING without *COUPLING.');
            dofs = [];
            for d = data(:).'
                v = nums(d); if numel(v) == 1, v(2) = v(1); end, dofs = [dofs v(1):v(2)]; %#ok<AGROW>
            end
            if isempty(dofs), dofs = 1:6; end
            assert(all(ismember(1:3,dofs)),'vil:Unsupported','Distributing coupling "%s" must couple DOFs 1-3.',pendingCoupling.name);
            w = upper(opt(op,'weightingmethod',"UNIFORM"));
            pendingCoupling.weighting = w;
            R.couplings(end+1) = struct('ref',pendingCoupling.ref,'nodes',pendingCoupling.surface,'kind',"distributing:" + w, ...
                'source',string(pendingCoupling.name) + "|" + pendingCoupling.scope);
            pendingCoupling = [];
        case {"TIE","MPC","RIGIDBODY","SPRING","DASHPOT","CONNECTORSECTION","KINEMATICCOUPLING", ...
                "DISTRIBUTINGCOUPLING","SHELLSECTION","BEAMSECTION","MEMBRANESECTION","NONSTRUCTURALMASS", ...
                "PLASTIC","HYPERELASTIC","SUBSTRUCTUREPROPERTY","BASEMOTIONNOT"}
            error('vil:Unsupported',['%s contains *%s, which changes the stiffness or mass and is not supported. ' ...
                'Supported: one solid tetrahedral part, isotropic material, fixed supports, point mass tied by ' ...
                '*EQUATION or distributing *COUPLING.'],fname(filename),kw);
        otherwise
            % Output requests, amplitudes, loads, damping, other steps: no effect on the modes.
    end
end
if skippedStepBcs > 0
    R.notes(end+1) = sprintf("%d *BOUNDARY block(s) in non-frequency steps ignored.",skippedStepBcs);
end
assert(~isempty(nodeBlocks),'vil:Format','%s has no *NODE data.',fname(filename));
assert(~isempty(R.conn),'vil:Format','%s has no solid tetrahedra (*ELEMENT, TYPE=C3D4/C3D10).',fname(filename));

% Nodes, with the instance placement applied to part nodes.
P = cell2mat(nodeBlocks);
R.nodeKey = P(1,:); R.X = P(2:4,:);
if instances.Count == 1
    tr = instances.values; tr = tr{1};
    isPart = R.nodeKey < AS;
    x = R.X(:,isPart);
    x = x+tr.shift;
    if ~isempty(tr.rot)
        a = tr.rot(1:3).'; b = tr.rot(4:6).'; ax = (b-a)/norm(b-a); th = deg2rad(tr.rot(7));
        Kx = [0 -ax(3) ax(2); ax(3) 0 -ax(1); -ax(2) ax(1) 0];
        Rm = eye(3)+sin(th)*Kx+(1-cos(th))*Kx^2;
        x = Rm*(x-a)+a;
    end
    R.X(:,isPart) = x;
end

% Material: the one of the solid section of the tetrahedra.
mats = fieldnames(materials);
assert(~isempty(mats),'vil:Material','%s defines no *MATERIAL.',fname(filename));
used = strings(1,0);
for k = 1:numel(sections), used(end+1) = sections{k}.material; end %#ok<AGROW>
used = unique(used);
if isempty(used), used = string(lower(materials.(mats{1}).name)); end
assert(numel(used) == 1,'vil:Material',['The solid sections use %d materials (%s): only one isotropic ' ...
    'material per part is supported.'],numel(used),strjoin(used,', '));
f = matlab.lang.makeValidName(used);
assert(isfield(materials,f),'vil:Material','Material %s used by *SOLID SECTION is not defined.',used);
R.material = materials.(f);
assert(isfinite(R.material.E) && isfinite(R.material.nu),'vil:Material','Material %s has no *ELASTIC data.',R.material.name);
assert(isfinite(R.material.rho),'vil:Material','Material %s has no *DENSITY: a modal analysis needs it.',R.material.name);

% Point masses.
for k = 1:numel(massElsets)
    es = resolveSet(elsets,massElsets{k}.name,massElsets{k}.scope,instances,'element');
    en = elemNodes(es);
    for e = 1:numel(en)
        assert(isscalar(en{e}),'vil:Format','*MASS on elset %s refers to non-MASS elements.',massElsets{k}.name);
        R.masses(end+1,:) = [en{e} massValues{k}];
    end
    R.massSource(end+1) = massElsets{k}.name;
end

% Couplings: reference node and the coupled nodes.
for k = 1:numel(R.couplings)
    c = R.couplings(k); parts = split(c.source,"|"); sc = parts(2);
    R.couplings(k).ref = nodeRefs(c.ref,sc,nsets,instances);
    sk = setKey(sc,c.nodes);
    if ~isKey(surfaces,char(sk)), sk = setKey(mainPart,c.nodes); end
    assert(isKey(surfaces,char(sk)),'vil:Format','Coupling surface %s is not defined.',c.nodes);
    s = surfaces(char(sk));
    R.couplings(k).nodes = surfaceNodes(s,nsets,elsets,@elemNodes,instances);
    if s.type == "ELEMENT"
        R.couplings(k).kind = R.couplings(k).kind + ":areaweighted";
    end
    R.couplings(k).source = parts(1);
end

    function en = elemNodes(es)
        % Node keys of each element key in es (cell of column vectors).
        en = cell(1,numel(es)); found = false(1,numel(es));
        for b = 1:numel(blkEk)
            [hit,loc] = ismember(es,blkEk{b});
            for j = find(hit & ~found), en{j} = blkNk{b}(:,loc(j)); end
            found = found | hit;
        end
        assert(all(found),'vil:Format','Element %d of a set is not defined.',es(find(~found,1)));
    end

    function off = offsetOf(sc)
        off = 0; if sc == "assembly", off = AS; end
    end

    function keys = setMembers(data,op,sc,map,isNode)
        % IDs of a *NSET/*ELSET data block (numbers, ranges, other set names).
        off = offsetOf(sc); inst = opt(op,'instance',"");
        if strlength(inst) > 0, off = 0; end
        if hasOpt(op,'generate')
            v = reshape(nums(data),3,[]); keys = [];
            for j = 1:size(v,2), keys = [keys v(1,j):v(3,j):v(2,j)]; end %#ok<AGROW>
            keys = keys+off; return
        end
        if isempty(data), keys = zeros(1,0); return, end
        s1 = char(strjoin(regexprep(data,',\s*$',''),","));
        v = sscanf(s1,'%f,');
        if numel(v) == nnz(s1 == ',')+1, keys = v(:).'+off; return, end    % numbers only (fast path)
        tok = strtrim(split(string(s1),","));
        tok = tok(strlength(tok) > 0);
        v = str2double(tok); keys = v(isfinite(v)).'+off;
        for s = reshape(tok(~isfinite(v)),1,[])
            if isNode, keys = [keys nodeRefs(s,sc,map,instances)]; %#ok<AGROW>
            else, keys = [keys resolveSet(map,s,sc,instances,'element')]; end %#ok<AGROW>
        end
    end
end

% ---------------------------------------------------------------- helpers ---
function keys = nodeRefs(tokn,sc,nsets,instances)
% A node number, an instance-qualified node (Part-1-1.12) or a node set.
tokn = strtrim(string(tokn));
v = str2double(tokn);
if isfinite(v), keys = v+(sc == "assembly")*1e9; return, end
p = split(tokn,".");
if numel(p) == 2 && isfinite(str2double(p(2))) && isKey(instances,char(lower(p(1))))
    keys = str2double(p(2)); return
end
keys = resolveSet(nsets,tokn,sc,instances,'node');
end

function keys = resolveSet(map,name,sc,instances,what)
name = lower(strtrim(string(name)));
cand = sc + "." + name;
if contains(name,".")
    p = split(name,".");
    if isKey(instances,char(p(1))), tr = instances(char(p(1))); cand = tr.part + "." + strjoin(p(2:end),"."); end
end
if ~isKey(map,char(cand))
    k = string(map.keys); hit = k(endsWith(k,"." + name));
    assert(~isempty(hit),'vil:Format','The %s set "%s" is not defined.',what,name);
    cand = hit(1);
end
keys = map(char(cand));
end

function nodes = surfaceNodes(s,nsets,elsets,elemNodesFn,instances)
% Nodes of a surface: node surfaces list nodes/sets; element surfaces list
% elements (or element sets) with a face label S1-S4 (tetrahedra).
faces = {[1 2 3 5 6 7],[1 4 2 8 9 5],[2 4 3 9 10 6],[3 4 1 10 8 7]};   % corner and midside positions
nodes = [];
sc = s.scope; if strlength(s.inst) > 0, sc = "part"; end
for d = s.data(:).'
    t = strtrim(split(d,",")); t = t(strlength(t) > 0);
    if s.type == "NODE"
        assert(numel(t) < 2 || str2double(t(2)) == 1 || isnan(str2double(t(2))),'vil:Unsupported', ...
            'Node surfaces with weights other than 1 are not supported.');
        nodes = [nodes nodeRefs(t(1),sc,nsets,instances)]; %#ok<AGROW>
    else
        v = str2double(t(1));
        if isfinite(v), es = v+(sc == "assembly")*1e9; else, es = resolveSet(elsets,t(1),sc,instances,'element'); end
        lab = upper(t(min(2,end))); fk = sscanf(lab,'S%d');
        assert(~isempty(fk) && fk >= 1 && fk <= 4,'vil:Format','Surface face label %s: only S1-S4 of tetrahedra are supported.',lab);
        en = elemNodesFn(es(:).');
        for e = 1:numel(en)
            idx = faces{fk}; idx = idx(idx <= numel(en{e}));
            nodes = [nodes en{e}(idx).']; %#ok<AGROW>
        end
    end
end
nodes = unique(nodes);
end

function dofs = namedBoundary(name)
switch name
    case {"ENCASTRE","PINNED"}, dofs = 1:3;
    case "XSYMM", dofs = 1;
    case "YSYMM", dofs = 2;
    case "ZSYMM", dofs = 3;
    case "XASYMM", dofs = [2 3];
    case "YASYMM", dofs = [1 3];
    case "ZASYMM", dofs = [1 2];
    otherwise, error('vil:Format','Unknown *BOUNDARY type %s.',name);
end
end

function addSet(map,key,ids)
key = char(key);
if isKey(map,key), map(key) = unique([map(key) ids(:).']); else, map(key) = unique(ids(:).'); end
end

function k = setKey(sc,name)
k = string(sc) + "." + lower(strtrim(string(name)));
end

function [kw,op] = parseKeyword(line)
p = strtrim(split(line,","));
kw = upper(erase(extractAfter(p(1),1)," "));
op = struct();
for s = reshape(p(2:end),1,[])
    if strlength(s) == 0, continue, end
    kv = split(s,"=");
    key = lower(erase(kv(1)," ")); key = matlab.lang.makeValidName(char(key));
    if numel(kv) >= 2, op.(key) = strip(strtrim(strjoin(kv(2:end),"=")),'"'); else, op.(key) = "true"; end
end
end

function tf = hasOpt(op,key)
tf = isfield(op,key);
end

function v = opt(op,key,default)
if isfield(op,key), v = op.(key);
elseif nargin > 2, v = string(default);
else, error('vil:Format','A keyword is missing its %s= parameter.',upper(key));
end
end

function v = nums(lines)
% All numbers of a data block, fields separated by commas, lines joined.
s = strjoin(regexprep(lines(:).',',\s*$',''),",");
v = sscanf(char(s),'%f,');
nf = numel(strfind(char(s),','))+1;
if numel(v) ~= nf
    error('vil:Format','Could not read a numeric data line near "%s".',extractBefore(s+" ",min(strlength(s)+1,60)));
end
v = v(:).';
end

function L = readLines(filename,depth)
% Lines of the file with *INCLUDE expanded (absolute path, else next to the file).
assert(depth < 10,'vil:Format','*INCLUDE nested too deeply.');
filename = char(filename);
assert(isfile(filename),'vil:FileNotFound','File not found: %s',filename);
txt = string(fileread(filename));
L = splitlines(txt);
inc = find(startsWith(strtrim(L),"*INCLUDE",'IgnoreCase',true));
for k = numel(inc):-1:1
    tok = regexp(L(inc(k)),'(?i)input\s*=\s*"?([^",]+)"?','tokens','once');
    assert(~isempty(tok),'vil:Format','*INCLUDE without INPUT=.');
    f = strtrim(tok(1));
    if ~isfile(f)
        [~,b,e] = fileparts(f); alt = fullfile(fileparts(filename),b+e);
        if isfile(alt), f = alt; else, f = fullfile(fileparts(filename),f); end
    end
    L = [L(1:inc(k)-1); readLines(f,depth+1); L(inc(k)+1:end)];
end
end

function s = fname(f)
[~,b,e] = fileparts(char(f)); s = [b e];
end

function report(progress,msg)
if isempty(progress), return; end
progress(msg);
end
