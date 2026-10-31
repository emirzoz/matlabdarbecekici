function exportAbaqus(db,filename,opts)
% Write the cached FE model as an Abaqus/Standard input file on the same mesh.
% MATLAB quadratic tetrahedra use the C3D10 node order (corners 1-4, then
% midsides 12,23,31,14,24,34), checked in R2025b, so connectivity is copied.
% Steps: FREQ (Lanczos), optional SSD (modal FRF) and IMPACT (modal dynamic)
% for a unit/half-sine load at the hammer node, response at the sensor node.
arguments
    db struct
    filename (1,1) string
    opts.Hammer cell = {}
    opts.Sensor cell = {}
    opts.Zeta (:,1) double = 0.01
    opts.MaxHz (1,1) double = 1.02*max(db.frequencyHz)
    opts.FRFRangeHz (1,2) double = [1 0.95*max(db.frequencyHz)]
    opts.FRFPointsPerInterval (1,1) double = 25
    opts.Impact struct = struct([])
    opts.BaseAxis (1,1) double = 0
    opts.BasePsd double = []
end
assert(size(db.elements,1)==10,'vil:Order','Abaqus export needs a quadratic (10-node) mesh.');
fid = fopen(filename,'w'); assert(fid>0,'vil:Write','Cannot write %s.',filename);
cleanup = onCleanup(@()fclose(fid));
c = db.config; n = size(db.nodes,2); ne = size(db.elements,2);
fprintf(fid,'*HEADING\nVirtual Impact Lab export %s, SI units (m, kg, s, N, Pa)\n',char(datetime('now')));
fprintf(fid,'*NODE, NSET=ALLNODES\n');
fprintf(fid,'%d, %.12g, %.12g, %.12g\n',[1:n; db.nodes]);
fprintf(fid,'*ELEMENT, TYPE=C3D10, ELSET=PART\n');
fprintf(fid,'%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d\n',[1:ne; double(db.elements)]);
isFree = isempty(db.fixedNodes);
assert(~isFree || (opts.BaseAxis == 0 && isempty(opts.BasePsd)),'vil:FreeFree', ...
    'Base motion needs a clamp: a free-free model cannot be exported with base excitation.');
if ~isFree, writeSet(fid,'FIXED',db.fixedNodes); end
probes = {'HAMMER',opts.Hammer;'SENSOR',opts.Sensor};
for k = 1:2
    if ~isempty(probes{k,2}), writeSet(fid,probes{k,1},probes{k,2}{1}); end
end
fprintf(fid,'*SOLID SECTION, ELSET=PART, MATERIAL=MAT\n,\n');
fprintf(fid,'*MATERIAL, NAME=MAT\n*ELASTIC\n%.12g, %.12g\n*DENSITY\n%.12g,\n',c.E,c.nu,c.rho);
if ~isFree, fprintf(fid,'*BOUNDARY\nFIXED, ENCASTRE\n'); end
if opts.BaseAxis > 0, fprintf(fid,'*AMPLITUDE, NAME=UNIT\n0., 1., 1e9, 1.\n'); end
if ~isempty(opts.BasePsd)
    fprintf(fid,'*PSD-DEFINITION, NAME=FLIGHT, TYPE=BASE\n');
    fprintf(fid,'%.10g, 0., %.10g\n',[opts.BasePsd(:,2) opts.BasePsd(:,1)].');
end
% Frequency extraction over the same band as MATLAB (slightly widened).
fprintf(fid,'*STEP, NAME=FREQ, PERTURBATION\n*FREQUENCY, EIGENSOLVER=LANCZOS, NORMALIZATION=MASS\n');
fprintf(fid,', %.10g, %.10g\n',max(c.rangeHz(1),0),opts.MaxHz);
fprintf(fid,'*OUTPUT, FIELD, VARIABLE=PRESELECT\n*NODE OUTPUT\nU,\n');
fprintf(fid,'*OUTPUT, HISTORY, VARIABLE=PRESELECT\n*END STEP\n');
haveProbes = ~isempty(opts.Hammer) && ~isempty(opts.Sensor);
if haveProbes
    hDof = dof(opts.Hammer{2}); sDof = dof(opts.Sensor{2});
    fprintf(fid,'*STEP, NAME=SSD, PERTURBATION\n*STEADY STATE DYNAMICS, FREQUENCY SCALE=LINEAR\n');
    fprintf(fid,'%.10g, %.10g, %d, 1.\n',opts.FRFRangeHz(1),opts.FRFRangeHz(2),opts.FRFPointsPerInterval);
    writeDamping(fid,opts.Zeta,db.frequencyHz);
    fprintf(fid,'*CLOAD\nHAMMER, %d, 1.\n',hDof);
    fprintf(fid,'*OUTPUT, FIELD\n*NODE OUTPUT, NSET=SENSOR\nU,\n*END STEP\n');
    if ~isempty(opts.Impact)
        p = opts.Impact; dt = 1/p.fs;
        % Same samples as vil.simulateImpact, so both integrate one
        % piecewise-linear force history.
        t = (0:floor(p.contactDuration*p.fs)+1)*dt;
        a = sin(pi*t/p.contactDuration).*(t<=p.contactDuration);
        fprintf(fid,'*AMPLITUDE, NAME=HALFSINE, DEFINITION=TABULAR\n');
        fprintf(fid,'%s\n',wrapPairs([t; a]));
        fprintf(fid,'*STEP, NAME=IMPACT\n*MODAL DYNAMIC, CONTINUE=NO\n%.10g, %.10g\n',dt,p.duration);
        writeDamping(fid,p.zeta,db.frequencyHz);
        fprintf(fid,'*CLOAD, AMPLITUDE=HALFSINE\nHAMMER, %d, %.10g\n',hDof,p.peakForce);
        fprintf(fid,'*OUTPUT, HISTORY, FREQUENCY=1\n*NODE OUTPUT, NSET=SENSOR\nU%d, A%d\n*END STEP\n',sDof,sDof);
    end
    if opts.BaseAxis > 0
        % Clamp motion: unit acceleration vs frequency, then random (m/s^2)^2/Hz.
        fprintf(fid,'*STEP, NAME=SSDBASE, PERTURBATION\n*STEADY STATE DYNAMICS, FREQUENCY SCALE=LINEAR\n');
        fprintf(fid,'%.10g, %.10g, %d, 1.\n',opts.FRFRangeHz(1),opts.FRFRangeHz(2),opts.FRFPointsPerInterval);
        writeDamping(fid,opts.Zeta,db.frequencyHz);
        fprintf(fid,'*BASE MOTION, DOF=%d, AMPLITUDE=UNIT\n',opts.BaseAxis);
        fprintf(fid,'*OUTPUT, FIELD\n*NODE OUTPUT, NSET=SENSOR\nTA,\n*END STEP\n');
    end
    if ~isempty(opts.BasePsd)
        % Abaqus integrates the PSD on these points: bias them onto the
        % resonances, or a coarse grid overstates each narrow peak.
        fprintf(fid,'*STEP, NAME=RANDOM\n*RANDOM RESPONSE\n%.10g, %.10g, 201, 7.\n', ...
            opts.BasePsd(1,1),opts.BasePsd(end,1));
        writeDamping(fid,opts.Zeta,db.frequencyHz);
        fprintf(fid,'*BASE MOTION, DOF=%d, LOAD CASE=1, SCALE=1.\n',opts.BaseAxis);
        fprintf(fid,'*CORRELATION, TYPE=UNCORRELATED, PSD=FLIGHT\n1, 1, 1.\n');
        fprintf(fid,'*OUTPUT, FIELD\n*NODE OUTPUT, NSET=SENSOR\nRTA,\n*END STEP\n');
    end
end
end

function writeDamping(fid,zeta,fHz)
% Fraction of critical damping (matches vil.damping): one value for every
% mode, or one per mode, given at each mode's frequency (Abaqus
% interpolates linearly in between).
fprintf(fid,'*MODAL DAMPING, DEFINITION=FREQUENCY RANGE\n');
if isscalar(zeta)
    fprintf(fid,'0., %.10g\n1e9, %.10g\n',zeta,zeta);
else
    assert(numel(zeta)==numel(fHz),'vil:Damping','Give one damping ratio or one per mode.');
    fprintf(fid,'%.10g, %.10g\n',[fHz(:).'; zeta(:).']);
end
end

function writeSet(fid,name,ids)
fprintf(fid,'*NSET, NSET=%s\n',name);
ids = ids(:).'; k = 1;
while k <= numel(ids)
    chunk = ids(k:min(k+15,end));
    fprintf(fid,'%s\n',strjoin(string(chunk),', ')); k = k+16;
end
end

function s = wrapPairs(pairs)
% Four (time, value) pairs per data line.
rows = strings(0,1);
for k = 1:4:size(pairs,2)
    blk = pairs(:,k:min(k+3,end));
    rows(end+1,1) = strjoin(compose('%.10g, %.10g',blk.'),', '); %#ok<AGROW>
end
s = strjoin(rows,newline);
end

function d = dof(direction)
if ischar(direction) || isstring(direction), d = find('XYZ'==upper(char(direction))); else, d = direction; end
assert(isscalar(d) && any(d==1:3),'vil:Direction','Abaqus export supports X, Y or Z probe directions only.');
end
