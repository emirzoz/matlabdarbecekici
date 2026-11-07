function exportAnsys(db,filename)
% Write the solid model as an Ansys Mechanical APDL blocked input (.cdb style):
% SI units, SOLID187 (or SOLID285) on the same mesh and node numbers, one
% isotropic material, FIXED component with D,ALL,ALL, and the payload as a
% MASS21 point mass on a pilot node tied to its nodes by RBE3 (uniform) or
% by CE averaging equations (weighted). MODOPT asks for the same mode count.
% Read back by vil.importModel; also a starting point for an Ansys check.
arguments
    db struct
    filename (1,1) string
end
assert(~isfield(db,'isShell'),'vil:Shell','Ansys export writes solid models only.');
order = size(db.elements,1);
assert(ismember(order,[4 10]),'vil:Order','Ansys export needs 4- or 10-node tetrahedra.');
fid = fopen(filename,'w'); assert(fid>0,'vil:Write','Cannot write %s.',filename);
cleanup = onCleanup(@()fclose(fid));
c = db.config; n = size(db.nodes,2); ne = size(db.elements,2);
fprintf(fid,'/COM,Virtual Impact Lab export %s, SI units (m, kg, s, N, Pa)\n/PREP7\n/UNITS,MKS\n',char(datetime('now')));
fprintf(fid,'ET,1,%d\n',ternary(order == 10,187,285));
fprintf(fid,'MP,EX,1,%.15g\nMP,PRXY,1,%.15g\nMP,DENS,1,%.15g\n',c.E,c.nu,c.rho);
fprintf(fid,'NBLOCK,6,SOLID,%10d,%10d\n(3i9,6e21.13e3)\n',n,n);
fprintf(fid,'%9d%9d%9d%21.13E%21.13E%21.13E\n',[1:n; zeros(2,n); db.nodes]);
fprintf(fid,'N,R5.3,LOC,       -1,\n');
fprintf(fid,'EBLOCK,19,SOLID,%10d,%10d\n(19i9)\n',ne,ne);
E = double(db.elements);
head = [ones(4,ne); zeros(4,ne); repmat(order,1,ne); zeros(1,ne); 1:ne];
if order == 10
    fprintf(fid,[repmat('%9d',1,19) '\n' repmat('%9d',1,2) '\n'],[head; E]);
else
    fprintf(fid,[repmat('%9d',1,15) '\n'],[head; E]);
end
fprintf(fid,'       -1\n');
payloadKg = 0; if isfield(db,'payloadMass'), payloadKg = db.payloadMass; end
if payloadKg > 0
    pn = db.payload.nodes(:).'; pilot = n+1; x = mean(db.nodes(:,pn),2);
    w = []; if isfield(db.payload,'weights'), w = db.payload.weights; end
    fprintf(fid,'ET,2,21\nKEYOPT,2,3,2\nR,2,%.15g,%.15g,%.15g\n',payloadKg,payloadKg,payloadKg);
    fprintf(fid,'N,%d,%.15g,%.15g,%.15g\nTYPE,2\nREAL,2\nMAT,1\nE,%d\n',pilot,x,pilot);
    if isempty(w)
        writeComponent(fid,'PAYLOAD',pn);
        fprintf(fid,'RBE3,%d,ALL,PAYLOAD\n',pilot);
    else
        labs = ["UX" "UY" "UZ"];
        for d = 1:3
            fprintf(fid,'CE,%d,0,%d,%s,1\n',d,pilot,labs(d));
            for k = 1:3:numel(pn)
                j = k:min(k+2,numel(pn));
                fprintf(fid,'CE,%d,0,%s\n',d,strjoin(compose('%d,%s,%.15g',pn(j).',repmat(labs(d),numel(j),1),-w(j).'),','));
            end
        end
    end
end
if ~isempty(db.fixedNodes)
    writeComponent(fid,'FIXED',db.fixedNodes);
    fprintf(fid,'CMSEL,S,FIXED\nD,ALL,ALL,0\nALLSEL,ALL\n');
end
fprintf(fid,'FINISH\n/SOLU\nANTYPE,MODAL\nMODOPT,LANB,%d\nMXPAND,%d\nSOLVE\nFINISH\n',numel(db.omega),numel(db.omega));
end

function writeComponent(fid,name,ids)
ids = sort(ids(:).'); v = [];
k = 1;
while k <= numel(ids)
    j = k; while j < numel(ids) && ids(j+1) == ids(j)+1, j = j+1; end
    if j > k, v = [v ids(k) -ids(j)]; else, v = [v ids(k)]; end %#ok<AGROW>
    k = j+1;
end
fprintf(fid,'CMBLOCK,%s,NODE,%8d\n(8i10)\n',name,numel(v));
for k = 1:8:numel(v), fprintf(fid,'%10d',v(k:min(k+7,end))); fprintf(fid,'\n'); end
end

function v = ternary(c,a,b)
if c, v = a; else, v = b; end
end
