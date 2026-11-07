function R = readAnsys(filename,progress)
% Read the parts of an Ansys Mechanical APDL input (CDWRITE .cdb, Workbench
% ds.dat, hand-written APDL) that a modal model needs: NBLOCK/N nodes,
% EBLOCK/E/EN elements (SOLID187, SOLID285, SOLID185 and SOLID186 tetrahedra,
% MASS21, TARGE170 pilots with CONTA17x MPC contact), ET/KEYOPT/R/RMORE,
% MP/MPDATA (EX, PRXY or NUXY, DENS), CMBLOCK components, D (zero only, on
% nodes, ranges, components or the current CMSEL/NSEL selection), CE, RBE3,
% /UNITS, MODOPT, *SET and NAME=value variables.
% Rigid ties (CERIG, CP, rigid MPC contact) raise vil:RigidTie; hexahedra,
% shells and beams raise vil:ElementType.
if nargin < 2, progress = []; end
report(progress,'Reading the Ansys input file...');
filename = char(filename);
assert(isfile(filename),'vil:FileNotFound','File not found: %s',filename);
Lraw = splitlines(string(fileread(filename)));    % fixed-width blocks: leading blanks matter
L = regexprep(Lraw,'!.*$','');
L = strtrim(L);
up = upper(L);
term = find(up == "-1" | startsWith(up,"N,R5.3,LOC") | startsWith(up,"-1,") | startsWith(up,"-1 "));

R = struct('format',"Ansys",'nodeKey',zeros(1,0),'X',zeros(3,0),'conn',{{}},'elemType',strings(1,0), ...
    'elemKey',{{}},'masses',zeros(0,2),'bcs',zeros(0,2),'equations',{{}},'couplings',struct('ref',{},'nodes',{},'kind',{},'source',{}), ...
    'material',struct('E',NaN,'nu',NaN,'rho',NaN,'name',""),'unitsHint',"",'nModes',NaN,'rangeHz',[0 0], ...
    'notes',strings(1,0),'bcSource',strings(1,0),'massSource',strings(1,0));
nodeBlocks = {};
EB = {};          % element blocks: struct of row vectors num/type/real/mat and a cell of node lists
et = containers.Map('KeyType','double','ValueType','double');
keyopt = containers.Map('KeyType','char','ValueType','double');
rc = containers.Map('KeyType','double','ValueType','any');
mp = containers.Map('KeyType','char','ValueType','double');
comps = containers.Map('KeyType','char','ValueType','any');
vars = containers.Map('KeyType','char','ValueType','any');
cur = struct('type',1,'real',1,'mat',1,'pilot',false); lastR = NaN; lastEq = 0;
eqs = containers.Map('KeyType','double','ValueType','any');
sel = "all"; selUnknown = false; selName = "all nodes"; nextElem = 1;
i = 0;
while i < numel(L)
    i = i+1; s = L(i);
    if strlength(s) == 0 || startsWith(s,"/COM",'IgnoreCase',true) || startsWith(s,"C***",'IgnoreCase',true), continue, end
    % NAME=value assignment
    tok = regexp(s,'^([A-Za-z_]\w*)\s*=\s*(.+)$','tokens','once');
    if ~isempty(tok), setVar(tok(1),tok(2)); continue, end
    t = strtrim(split(s,","));
    cmd = upper(t(1)); t = t(2:end);
    switch cmd
        case "NBLOCK"
            [ni,wi,nr,wr] = blockFormat(L(i+1));
            e = term(find(term > i+1,1)); data = Lraw(i+2:e-1);
            V = fixedFields(data,[repmat(wi,1,ni) repmat(wr,1,nr)]);
            V(isnan(V)) = 0;
            nodeBlocks{end+1} = [V(:,1).'; V(:,ni+1:ni+3).']; %#ok<AGROW>
            i = e;
        case "EBLOCK"
            solid = numel(t) >= 2 && upper(t(2)) == "SOLID";
            [ni,wi] = blockFormat(L(i+1));
            e = term(find(term > i+1,1)); data = Lraw(i+2:e-1);
            V = fixedFields(data,repmat(wi,1,ni));
            if solid, addSolidRecords(V); else, addOtherRecords(V); end
            i = e;
        case "CMBLOCK"
            name = upper(t(1)); kind = upper(t(2)); cnt = str2double(t(3));
            [ni,wi] = blockFormat(L(i+1));
            nl = ceil(cnt/ni); data = Lraw(i+2:i+1+nl);
            V = fixedFields(data,repmat(wi,1,ni)).'; v = V(~isnan(V)).';
            ids = [];
            for k = 1:numel(v)
                if v(k) < 0, ids = [ids ids(end)+1:-v(k)]; else, ids(end+1) = v(k); end %#ok<AGROW>
            end
            comps(char(name)) = struct('kind',kind,'ids',ids);
            i = i+1+nl;
        case "*SET"
            setVar(t(1),strjoin(t(2:end),","));
        case "*GET"
            vars(char(upper(t(1)))) = NaN;
        case "/UNITS"
            u = upper(t(1));
            if u == "MKS" || u == "SI", R.unitsHint = "SI";
            elseif u == "MPA", R.unitsHint = "mm-t-s";
            else, R.notes(end+1) = "/UNITS," + u + " not recognised: units decided from E."; end
        case "ET"
            id = val(t(1)); ty = upper(sub(t(2))); ty = str2double(regexprep(ty,'^[A-Z]+',''));
            et(id) = ty;
        case {"KEYOPT","KEYO"}
            keyopt(sprintf('%d_%d',val(t(1)),val(t(2)))) = val(t(3));
        case "R"
            id = val(t(1)); v = arrayfun(@(x)valOr0(x),t(2:end)).'; rc(id) = v; lastR = id;
        case "RMORE"
            v = arrayfun(@(x)valOr0(x),t).'; rc(lastR) = [rc(lastR) v];
        case "MP"
            mp(sprintf('%s_%d',normLab(t(1)),val(t(2)))) = val(t(3));
        case "MPDATA"
            mp(sprintf('%s_%d',normLab(t(1)),val(t(2)))) = val(t(4));
        case "TYPE", cur.type = val(t(1));
        case "REAL", cur.real = val(t(1));
        case "MAT", cur.mat = val(t(1));
        case "TSHAP", cur.pilot = upper(t(1)) == "PILO";
        case "N"
            v = arrayfun(@(x)valOr0(x),t(1:min(4,end))).'; v(end+1:4) = 0;
            nodeBlocks{end+1} = v(:); %#ok<AGROW>
        case {"E","EN"}
            if cmd == "EN", num = val(t(1)); t = t(2:end); else, num = nextElem; end
            nn = arrayfun(@(x)valOr0(x),t).'; nn = nn(nn > 0);
            EB{end+1} = struct('num',num,'type',cur.type,'real',cur.real,'mat',cur.mat,'nodes',{{nn}}); %#ok<AGROW>
            nextElem = num+1;
        case "EMORE"
            nn = arrayfun(@(x)valOr0(x),t).'; nn = nn(nn > 0);
            EB{end}.nodes{end} = [EB{end}.nodes{end} nn];
        case "CMSEL"
            how = upper(t(1)); nm = ""; if numel(t) >= 2, nm = upper(t(2)); end
            if how == "ALL", sel = "all"; selUnknown = false; selName = "all nodes"; continue, end
            if how == "NONE", sel = zeros(1,0); selUnknown = false; continue, end
            assert(isKey(comps,char(nm)),'vil:Format','CMSEL refers to component %s, which is not defined.',nm);
            c = comps(char(nm)); if c.kind ~= "NODE", continue, end
            sel = combine(how,c.ids);
            if how == "S", selName = nm; else, selName = selName + " " + how + " " + nm; end
        case "NSEL"
            how = upper(t(1));
            if how == "ALL", sel = "all"; selUnknown = false; selName = "all nodes";
            elseif how == "NONE", sel = zeros(1,0); selUnknown = false;
            elseif numel(t) >= 2 && upper(t(2)) == "NODE"
                a = val(t(4)); b = a; inc = 1;
                if numel(t) >= 5 && strlength(t(5)) > 0, b = val(t(5)); end
                if numel(t) >= 6 && strlength(t(6)) > 0, inc = val(t(6)); end
                sel = combine(how,a:inc:b); selName = "selected nodes";
            else
                selUnknown = true;
            end
        case "ALLSEL", sel = "all"; selUnknown = false; selName = "all nodes";
        case "NSLE", selUnknown = true;
        case "D"
            target = upper(sub(t(1)));
            labs = upper(t(2)); if numel(t) >= 7, labs = [labs upper(t(7:end)).']; end
            v = 0; if numel(t) >= 3 && strlength(t(3)) > 0, v = val(t(3)); end
            if v ~= 0
                error('vil:PrescribedMotion','D,%s,%s prescribes %g (not 0). A modal model needs fixed (zero) supports only.',target,labs(1),v);
            end
            if target == "ALL"
                assert(~selUnknown,'vil:Unsupported',['D,ALL is applied to a node selection made by location or ' ...
                    'from elements, which cannot be replayed here. Define the supports as a node component (CMBLOCK).']);
                if isstring(sel), ids = currentNodes(); else, ids = sel; end
                src = selName;
            elseif isKey(comps,char(target))
                ids = comps(char(target)).ids; src = target;
            else
                a = val(target); b = a; inc = 1;
                if numel(t) >= 5 && strlength(t(5)) > 0, b = val(t(5)); end
                if numel(t) >= 6 && strlength(t(6)) > 0, inc = val(t(6)); end
                ids = a:inc:b; src = "node list";
            end
            dofs = [];
            for lb = reshape(labs(strlength(labs) > 0),1,[])
                switch lb
                    case "UX", dofs(end+1) = 1; %#ok<AGROW>
                    case "UY", dofs(end+1) = 2; %#ok<AGROW>
                    case "UZ", dofs(end+1) = 3; %#ok<AGROW>
                    case "ALL", dofs = [dofs 1 2 3]; %#ok<AGROW>
                    otherwise   % rotations: solids have none
                end
            end
            [K,D] = ndgrid(ids,unique(dofs));
            R.bcs = [R.bcs; K(:) D(:)]; R.bcSource(end+1) = src;
        case "CE"
            nq = upper(t(1));
            if nq == "NEXT" || strlength(nq) == 0, n = lastEq+1; elseif nq == "HIGH", n = lastEq; else, n = val(nq); end
            if numel(t) >= 2 && strlength(t(2)) > 0 && val(t(2)) ~= 0
                error('vil:Unsupported','CE,%d has a non-zero constant: only homogeneous constraint equations are supported.',n);
            end
            terms = zeros(0,3);
            for k = 3:3:numel(t)-2
                if strlength(t(k)) == 0, continue, end
                terms(end+1,:) = [val(t(k)) dofOf(t(k+1)) val(t(k+2))]; %#ok<AGROW>
            end
            if isKey(eqs,n), eqs(n) = [eqs(n); terms]; else, eqs(n) = terms; end
            lastEq = max(lastEq,n);
        case "RBE3"
            master = val(t(1)); dl = upper(t(2)); slaves = upper(t(3));
            assert(ismember(dl,["ALL" "UXYZ"]),'vil:Unsupported','RBE3 DOF label %s: the payload needs UX, UY and UZ (UXYZ or ALL).',dl);
            assert(numel(t) < 4 || strlength(t(4)) == 0,'vil:Unsupported','RBE3 with a weight table is not supported (uniform weights only).');
            assert(isKey(comps,char(slaves)),'vil:Format','RBE3 slave component %s is not defined.',slaves);
            R.couplings(end+1) = struct('ref',master,'nodes',comps(char(slaves)).ids,'kind',"distributing:UNIFORM",'source',"RBE3 " + slaves);
        case "CERIG"
            error('vil:RigidTie','CERIG makes the attached nodes rigid, which this model cannot represent. Use RBE3 or CE averages for the payload.');
        case "CP"
            error('vil:RigidTie','CP couples nodal DOFs (the nodes move together), which this model cannot represent.');
        case "MODOPT"
            if numel(t) >= 2, n = valOr0(t(2)); if n > 0, R.nModes = n; end, end
            if numel(t) >= 4, hi = valOr0(t(4)); if hi > 0, R.rangeHz = [0 hi]; end, end
        otherwise
            % Loads, outputs, solution controls: no effect on the modes.
    end
end
assert(~isempty(nodeBlocks),'vil:Format','%s has no nodes (NBLOCK or N).',fname(filename));
P = cell2mat(nodeBlocks); R.nodeKey = P(1,:); R.X = P(2:4,:);
for n = cell2mat(eqs.keys), R.equations{end+1} = eqs(n); end

% Elements by type.
assert(~isempty(EB),'vil:Format','%s has no elements.',fname(filename));
B = [EB{:}];
num = [B.num]; tid = [B.type]; rl = [B.real]; mt = [B.mat]; nodesOf = [B.nodes];
ty = zeros(size(tid));
for u = unique(tid), ty(tid == u) = typeOf(u); end
solidTypes = [187 285 185 186];
isSolid = ismember(ty,solidTypes);
assert(any(isSolid),'vil:Format','%s has no solid tetrahedra (SOLID187, SOLID285, SOLID185 or SOLID186).',fname(filename));
bad = ~ismember(ty,[solidTypes 21 170 174 175 177 178]);
if any(bad)
    error('vil:ElementType',['%s has elements of type %d (e.g. element %d). Only solid tetrahedra (SOLID187, ' ...
        'SOLID285, degenerate SOLID185/186), MASS21 point masses and MPC contact remote points are supported.'], ...
        fname(filename),ty(find(bad,1)),num(find(bad,1)));
end
k4 = zeros(1,0); k10 = zeros(1,0); c4 = zeros(4,0); c10 = zeros(10,0);
for u = solidTypes
    ii = find(ty == u); if isempty(ii), continue, end
    [c,isQuad] = tetNodes(nodesOf(ii),u,num(ii));
    if isQuad, c10 = [c10 c]; k10 = [k10 num(ii)]; else, c4 = [c4 c]; k4 = [k4 num(ii)]; end %#ok<AGROW>
end
assert(isempty(k4) || isempty(k10),'vil:MeshElements','The mesh mixes linear and quadratic tetrahedra.');
if ~isempty(k10), R.conn = {c10}; R.elemKey = {k10}; R.elemType = "SOLID187";
else, R.conn = {c4}; R.elemKey = {k4}; R.elemType = "SOLID285"; end

% Material of the solids.
m = unique(mt(isSolid));
mprops = arrayfun(@(id)[mpGet("EX",id) mpGet("NUXY",id) mpGet("DENS",id)],m,'UniformOutput',false);
mprops = unique(cell2mat(mprops(:)),'rows');
assert(size(mprops,1) == 1,'vil:Material','The solid elements use %d different materials: only one isotropic material is supported.',size(mprops,1));
R.material = struct('E',mprops(1),'nu',mprops(2),'rho',mprops(3),'name',"MAT " + m(1));
assert(isfinite(R.material.E),'vil:Material','Material %d has no EX.',m(1));
if ~isfinite(R.material.nu), R.material.nu = 0.3; R.notes(end+1) = "No PRXY/NUXY: Ansys default 0.3 used."; end
assert(isfinite(R.material.rho),'vil:Material','Material %d has no DENS: a modal analysis needs it.',m(1));

% Point masses (MASS21).
for k = find(ty == 21)
    ko3 = koGet(tid(k),3); ko1 = koGet(tid(k),1);
    assert(ko1 == 0,'vil:Unsupported','MASS21 with KEYOPT(1)=1 (weights instead of masses) is not supported.');
    assert(ismember(ko3,[0 2]),'vil:Unsupported','MASS21 KEYOPT(3)=%d (2D) is not supported.',ko3);
    assert(isKey(rc,rl(k)),'vil:Format','MASS21 element %d has no real constant set %d.',num(k),rl(k));
    r = rc(rl(k)); r(end+1:6) = 0;
    assert(max(abs(r(1:3)-r(1))) <= 1e-9*abs(r(1)),'vil:Unsupported', ...
        'MASS21 element %d has different masses per direction (%s): only an isotropic point mass is supported.',num(k),mat2str(r(1:3)));
    if ko3 == 0 && any(r(4:6) ~= 0), R.notes(end+1) = "MASS21 rotary inertia ignored: no rotary inertia is modelled."; end
    R.masses(end+1,:) = [nodesOf{k}(1) r(1)];
    R.massSource(end+1) = "MASS21 element " + num(k);
end

% Remote points by MPC contact: TARGE170 pilot node + CONTA17x nodes of the same real set.
for k = find(ty == 170 & cellfun(@numel,nodesOf) == 1)
    pc = find(ismember(ty,[174 175 177 178]) & rl == rl(k));
    assert(~isempty(pc),'vil:Format','Pilot node %d (real set %d) has no contact elements.',nodesOf{k}(1),rl(k));
    ctype = tid(pc(1));
    assert(koGet(ctype,2) == 2,'vil:Unsupported',['Contact real set %d is not an MPC constraint (KEYOPT(2)=%d): ' ...
        'real contact is not supported.'],rl(k),koGet(ctype,2));
    ko4 = koGet(ctype,4);
    if ko4 == 2
        error('vil:RigidTie',['Remote point at node %d is rigid (contact KEYOPT(4)=2): it makes the attached region ' ...
            'rigid, which this model cannot represent. Use deformable behaviour.'],nodesOf{k}(1));
    end
    if ko4 ~= 1, R.notes(end+1) = sprintf("Remote point %d: contact KEYOPT(4)=%d, treated as deformable (force-distributed).",nodesOf{k}(1),ko4); end
    R.couplings(end+1) = struct('ref',nodesOf{k}(1),'nodes',unique([nodesOf{pc}]),'kind',"distributing:UNIFORM:areaweighted", ...
        'source',"remote point (real set " + rl(k) + ")");
end

    function setVar(name,value)
        v = str2double(sub(strtrim(value)));
        vars(char(upper(strtrim(name)))) = v;
    end

    function s = sub(s)
        % Replace a variable name by its value.
        s = strtrim(string(s));
        if strlength(s) > 0 && isKey(vars,char(upper(s))), s = string(vars(char(upper(s)))); end
    end

    function v = val(s)
        v = str2double(sub(s));
        assert(isfinite(v),'vil:Format',['Could not read "%s" as a number (line %d: %s). Values set by *GET ' ...
            'or expressions are not evaluated.'],s,i,L(i));
    end

    function v = valOr0(s)
        if strlength(strtrim(s)) == 0, v = 0; else, v = val(s); end
    end

    function d = dofOf(lb)
        switch upper(lb)
            case "UX", d = 1; case "UY", d = 2; case "UZ", d = 3;
            otherwise, error('vil:Unsupported','CE on DOF %s: only UX, UY and UZ are supported.',lb);
        end
    end

    function ids = currentNodes()
        Q = cell2mat(nodeBlocks); ids = Q(1,:);
    end

    function out = combine(how,ids)
        if isstring(sel), base = currentNodes(); else, base = sel; end
        switch how
            case "S", out = ids;
            case "A", out = union(base,ids);
            case "R", out = intersect(base,ids);
            case "U", out = setdiff(base,ids);
            otherwise, error('vil:Unsupported','Selection type %s is not supported.',how);
        end
        selUnknown = false;
    end

    function addSolidRecords(V)
        % Records: mat type real sec esys bd sm shape nn exc num nodes...
        Vt = V.'; v = Vt(~isnan(Vt)).';
        starts = zeros(1,ceil(numel(v)/12)); p = 1; nrec = 0;
        while p <= numel(v)
            nrec = nrec+1; starts(nrec) = p; p = p+11+v(p+8);
        end
        starts = starts(1:nrec); nn = v(starts+8);
        nodes = cell(1,nrec);
        for q = unique(nn)
            s0 = starts(nn == q); idx = s0+(11:10+q).';
            nodes(nn == q) = num2cell(v(idx).',2).';
        end
        EB{end+1} = struct('num',v(starts+10),'type',v(starts+1),'real',v(starts+2),'mat',v(starts),'nodes',{nodes});
    end

    function addOtherRecords(V)
        n = size(V,1); nodes = cell(1,n);
        for q = 1:n
            r = V(q,6:end); nodes{q} = r(~isnan(r) & r > 0);
        end
        EB{end+1} = struct('num',V(:,1).','type',V(:,2).','real',V(:,3).','mat',V(:,4).','nodes',{nodes});
    end

    function t = typeOf(id)
        assert(isKey(et,id),'vil:Format','Element type %d is used but not defined with ET.',id);
        t = et(id);
    end

    function v = koGet(id,k)
        key = sprintf('%d_%d',id,k); v = 0; if isKey(keyopt,key), v = keyopt(key); end
    end

    function v = mpGet(lab,id)
        key = sprintf('%s_%d',lab,id); v = NaN; if isKey(mp,key), v = mp(key); end
        if isnan(v) && lab == "NUXY", key = sprintf('PRXY_%d',id); if isKey(mp,key), v = mp(key); end, end
    end
end

% ---------------------------------------------------------------- helpers ---
function [c,isQuad] = tetNodes(nodes,ty,num)
% Corner/midside order of tetrahedra (corners 1-4, midsides 12,23,31,14,24,34).
len = cellfun(@numel,nodes);
need = struct('t285',4,'t187',10,'t185',8,'t186',20).(sprintf('t%d',ty));
k = find(len ~= need,1);
assert(isempty(k),'vil:MeshElements','Element %d (type %d) has %d nodes, expected %d.',num(max([k 1])),ty,len(max([k 1])),need);
n = reshape([nodes{:}],need,[]);
switch ty
    case 285
        c = n; isQuad = false;
    case 187
        c = n; isQuad = true;
    case 185
        % Degenerate brick I J K K M M M M.
        bad = find(~(n(3,:) == n(4,:) & all(n(5:8,:) == n(5,:),1)),1);
        assert(isempty(bad),'vil:ElementType', ...
            'SOLID185 element %d is a brick, not a tetrahedron: only tetrahedral meshes are supported.',num(max([bad 1])));
        c = n([1 2 3 5],:); isQuad = false;
    case 186
        % Degenerate tetrahedron: I J K K M M M M Q R K T M M M M Y Z A A.
        bad = find(~(n(3,:) == n(4,:) & all(n(5:8,:) == n(5,:),1) & n(19,:) == n(20,:)),1);
        assert(isempty(bad),'vil:ElementType', ...
            'SOLID186 element %d is a brick, not a tetrahedron: only tetrahedral meshes are supported.',num(max([bad 1])));
        c = n([1 2 3 5 9 10 12 17 18 19],:); isQuad = true;
end
end

function lab = normLab(s)
lab = upper(strtrim(s)); if lab == "PRXY", lab = "NUXY"; end
end

function [ni,wi,nr,wr] = blockFormat(line)
% Fortran format of a block, e.g. (3i9,6e21.13e3) or (19i9).
f = lower(char(line));
ti = regexp(f,'(\d*)i(\d+)','tokens','once');
assert(~isempty(ti),'vil:Format','Unreadable block format %s.',line);
ni = str2double(ti{1}); if isnan(ni), ni = 1; end
wi = str2double(ti{2});
te = regexp(f,'(\d*)e(\d+)','tokens','once');
nr = 0; wr = 0;
if ~isempty(te), nr = str2double(te{1}); if isnan(nr), nr = 1; end, wr = str2double(te{2}); end
end

function V = fixedFields(lines,widths)
% Fixed-width numeric fields; blank or missing fields are NaN.
r = numel(lines); nf = numel(widths);
V = nan(r,nf);
if r == 0, return, end
M = char(lines(:));
tot = sum(widths);
if size(M,2) < tot, M(:,end+1:tot) = ' '; end
M(M == char(0)) = ' ';
edges = [0 cumsum(widths)];
for j = 1:nf
    col = M(:,edges(j)+1:edges(j+1));
    blank = all(col == ' ',2);
    col(blank,end) = '0';
    v = sscanf(reshape([col repmat(' ',r,1)].',1,[]),'%f');
    assert(numel(v) == r,'vil:Format','Could not read field %d of a fixed-width block.',j);
    v(blank) = NaN; V(:,j) = v;
end
end

function s = fname(f)
[~,b,e] = fileparts(char(f)); s = [b e];
end

function report(progress,msg)
if isempty(progress), return; end
progress(msg);
end
