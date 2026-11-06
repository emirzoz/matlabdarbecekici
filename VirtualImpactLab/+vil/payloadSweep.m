function result = payloadSweep(geometry,c,massesKg,opts)
% Full modal solve for each payload mass (no frequency scaling): one
% vil.solveModes call per mass on the same mesh, material, supports and
% attachment nodes. K and M are assembled once and reused.
% c: as for vil.solveModes, with c.payload.nodes set (massKg is overwritten).
% opts.Cancel: function returning true to stop; checked between solves (an
% eigen solve in progress cannot be interrupted). opts.Step(k,total,msg)
% reports progress. result.table holds one row per completed mass.
arguments
    geometry
    c struct
    massesKg double {mustBeVector,mustBeFinite,mustBeNonnegative}
    opts.MinModes (1,1) double {mustBeInteger,mustBePositive} = 6
    opts.MeshInfo struct = struct()
    opts.Progress = []
    opts.Step = []
    opts.Cancel = []
    opts.KeepDatabases (1,1) logical = false
end
masses = massesKg(:).';
assert(numel(masses) <= 50,'vil:Sweep','Use at most 50 masses in one sweep.');
assert(isfield(c,'payload') && isfield(c.payload,'nodes') && ~isempty(c.payload.nodes),'vil:EmptySelection', ...
    'Select the payload attachment region before running a mass sweep.');
nm = opts.MinModes;
rows = cell(0,1); dbs = {}; assembly = [];
cancelled = false; t0 = tic;
for k = 1:numel(masses)
    if ~isempty(opts.Cancel) && opts.Cancel()
        cancelled = true; break
    end
    if ~isempty(opts.Step)
        opts.Step(k,numel(masses),sprintf('Payload %.4g kg (%d of %d): full modal solve...',masses(k),k,numel(masses)));
    end
    ck = c; ck.payload.massKg = masses(k);
    t1 = tic;
    [db,assembly] = vil.solveModes(geometry,ck,MinModes=nm,MeshInfo=opts.MeshInfo, ...
        Progress=opts.Progress,Assembly=assembly);
    f = nan(1,nm); f(1:min(nm,numel(db.frequencyHz))) = db.frequencyHz(1:min(nm,end));
    eff = db.participation.^2/db.totalMass;      % effective mass fractions, M_total
    rows{end+1,1} = [masses(k) db.structureMass db.totalMass f max(db.eigenResidual) ...
        db.massOrthogonalityError eff(:,1).' toc(t1)]; %#ok<AGROW>
    if opts.KeepDatabases, dbs{end+1} = db; end %#ok<AGROW>
end
names = ["Payload_kg" "StructureMass_kg" "TotalMass_kg" "f"+(1:nm)+"_Hz" "MaxEigenResidual" ...
    "MassOrthogonalityError" "Mode1_EffMassFraction_X" "Mode1_EffMassFraction_Y" "Mode1_EffMassFraction_Z" "SolveTime_s"];
if isempty(rows), data = zeros(0,numel(names)); else, data = cell2mat(rows); end
T = array2table(data,'VariableNames',cellstr(names));
result = struct('table',T,'cancelled',cancelled,'requestedKg',masses,'elapsed',toc(t0), ...
    'payloadNodes',c.payload.nodes(:).','numModes',nm,'databases',{dbs}, ...
    'note',"Each row is a separate eigen solve with M_total = M_structure + m*B'*B.");
end
