function [T,notes] = compareProjects(sources,opts)
% Side-by-side summary of solved projects, grouped by solve assumptions.
% sources: cell array of project file names and/or modal databases (structs).
% Rows that share material, supports, payload mass and payload model share an
% assumption group (A, B, ...). notes lists what differs between groups, so
% results solved under different assumptions are never shown as like for like.
arguments
    sources cell
    opts.Names string = strings(0,1)
    opts.Modes (1,1) double {mustBeInteger,mustBePositive} = 3
end
rows = struct([]); dbg = strings(0,1); parts = struct();
for k = 1:numel(sources)
    src = sources{k};
    if ischar(src) || isstring(src)
        db = vil.loadProject(src);
        [~,label] = fileparts(char(src)); label = string(label);
    else
        db = vil.projectSettings(src); label = "current";
    end
    if numel(opts.Names) >= k && strlength(opts.Names(k)) > 0, label = opts.Names(k); end
    s = db.config.settings;
    f = nan(1,opts.Modes); m = min(opts.Modes,numel(db.frequencyHz)); f(1:m) = db.frequencyHz(1:m);
    r = struct('Project',label,'StructureMass_g',1e3*db.structureMass,'Payload_kg',db.payloadMass, ...
        'TotalMass_kg',db.totalMass);
    for j = 1:opts.Modes, r.("f"+j+"_Hz") = f(j); end
    r.Material = sprintf('%s E=%.4g GPa nu=%.3g rho=%.5g',s.material.name,s.material.E/1e9,s.material.nu,s.material.rho);
    [r.Supports,supKey] = describeSupport(s);
    [r.PayloadModel,payKey] = payloadText(s);
    r.Mesh = sprintf('%s, %d nodes, %d el.',s.mesh.order,s.mesh.numNodes,s.mesh.numElements);
    r.MaxEigenResidual = max(db.eigenResidual);
    key = sprintf('%.6g|%.6g|%.6g|%s|%s|%.6g|%s',s.material.E,s.material.nu,s.material.rho, ...
        supKey,s.boundary,db.payloadMass,payKey);
    rows = [rows r]; %#ok<AGROW>
    dbg(end+1,1) = string(key); %#ok<AGROW>
    % What decides the group, without names and node counts.
    parts.Material(k,1) = string(sprintf('E=%.4g GPa nu=%.3g rho=%.5g',s.material.E/1e9,s.material.nu,s.material.rho));
    parts.Supports(k,1) = s.boundary + " " + supKey;
    parts.Payload_kg(k,1) = string(sprintf('%.4g',db.payloadMass));
    parts.PayloadModel(k,1) = payKey;
end
T = struct2table(rows,'AsArray',true);
[keys,~,g] = unique(dbg,'stable');
letters = string(char('A'+(0:numel(keys)-1)).');
T = addvars(T,letters(g),'Before',1,'NewVariableNames','Group');
notes = strings(0,1);
if numel(keys) > 1
    notes(end+1) = sprintf(['%d different assumption groups: compare frequencies only within a group. ' ...
        'Differences:'],numel(keys));
    for col = ["Material" "Supports" "Payload_kg" "PayloadModel"]
        v = parts.(col);
        if numel(unique(v)) > 1
            notes(end+1) = "  " + col + ": " + strjoin(unique(letters(g)+"="+v,'stable'),'; '); %#ok<AGROW>
        end
    end
else
    notes(end+1) = "All projects share material, supports, payload mass and payload model (group A).";
end
meshes = unique(string(T.Mesh));
if numel(meshes) > 1
    notes(end+1) = "Meshes differ between rows (geometry variants): mesh density and element order also affect frequencies.";
end
T = sortrows(T,'Group');
end

function [s,key] = describeSupport(st)
% key leaves out node counts: different meshes of one set-up still match.
if st.boundary == "free", s = "free-free"; key = s; return, end
sp = st.support; ax = 'XYZ';
switch sp.method
    case "faces", key = sprintf('faces %s',num2str(sp.faces));
    case "plane", key = sprintf('%s=%.4g mm +/-%.4g mm, Ux=Uy=Uz=0',ax(sp.axis),sp.positionMm,sp.toleranceMm);
    otherwise, key = sprintf('node list near %s=%.4g mm, Ux=Uy=Uz=0',ax(sp.axis),sp.positionMm);
end
s = string(sprintf('%s (%d nodes)',key,sp.count)); key = string(key);
end

function [s,key] = payloadText(st)
p = st.payload;
if ~p.enabled, s = "none"; key = s; return, end
ax = 'XYZ';
switch p.method
    case "plane", where = sprintf('%s=%.4g mm +/-%.4g mm',ax(p.axis),p.positionMm,p.toleranceMm);
    case "faces", where = "faces " + num2str(p.faces);
    otherwise, where = "stored node list";
end
key = "translational mass on the mean translation of " + string(where);
s = key + sprintf(' (%d nodes)',p.count);
end
