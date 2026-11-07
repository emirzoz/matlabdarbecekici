function tests=testModelImport
% Abaqus / Ansys input files with supports and payload, on the demo beam
% (clamped at X = -150 mm, 0.5 kg on the X = +150 mm end): every route must
% give the frequencies of the same model solved directly.
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
[g,c,mi]=vil.createDemoBeam(0.01);
tip=vil.selectNodes(g.Mesh.Nodes,g.Mesh.Elements,mi.surface,struct('method',"plane",'axis',1,'positionMm',150,'toleranceMm',1e-3));
c.payload=struct('massKg',0.5,'nodes',tip);
db=vil.solveModes(g,c,MeshInfo=mi,MinModes=6);
t.TestData.g=g; t.TestData.c=c; t.TestData.mi=mi; t.TestData.db=db; t.TestData.tip=tip;
t.TestData.dir=tempname; mkdir(t.TestData.dir);
end
function teardownOnce(t)
rmdir(t.TestData.dir,'s');
end
function teardown(t)
if isfield(t.TestData,'app') && isvalid(t.TestData.app.figure), close(t.TestData.app.figure); end
end
function f=file(t,name)
f=fullfile(t.TestData.dir,name);
end
function db=solveImported(file,units)
if nargin<2, units="auto"; end
[g,~,mi,m]=vil.importModel(file,units);
c=struct('E',m.E,'nu',m.nu,'rho',m.rho,'boundary',m.boundary,'fixedNodes',m.fixedNodes, ...
    'payload',struct('massKg',m.payload.massKg,'nodes',m.payload.nodes,'weights',m.payload.weights));
db=vil.solveModes(g,c,MeshInfo=mi,MinModes=6);
end
function checkSame(t,db)
ref=t.TestData.db;
verifyEqual(t,db.frequencyHz(1:6),ref.frequencyHz(1:6),'RelTol',1e-9);
verifyEqual(t,sort(db.fixedNodes(:)),sort(ref.fixedNodes(:)));
verifyEqual(t,sort(db.payload.nodes(:)),sort(t.TestData.tip(:)));
verifyEqual(t,db.payloadMass,0.5,'RelTol',1e-12);
verifyEqual(t,db.totalMass,ref.totalMass,'RelTol',1e-9);
end

function testAbaqusRoundTrip(t)
% exportAbaqus -> importModel: same mesh, clamp (ENCASTRE), point mass on a
% reference node tied by three *EQUATION averages.
f=file(t,'beam.inp');
vil.exportAbaqus(t.TestData.db,f);
[~,info,~,m]=vil.importModel(f);
verifyEqual(t,info.format,"ABAQUS"); verifyEqual(t,m.units,"SI");
verifyEqual(t,m.boundary,"clamped"); verifyEmpty(t,m.payload.weights);
checkSame(t,solveImported(f));
end

function testAbaqusCaeStyleMmTonne(t)
% Abaqus/CAE layout in mm-t-s: part nodes shifted, the instance translation
% puts them back; assembly reference point numbered 1 like a part node;
% node surface + distributing coupling; ENCASTRE inside the frequency step.
f=file(t,'cae.inp'); writeCae(t,f);
[~,~,~,m]=vil.importModel(f);
verifyEqual(t,m.units,"mm-t-s");
verifyEqual(t,m.E,t.TestData.c.E,'RelTol',1e-12); verifyEqual(t,m.rho,t.TestData.c.rho,'RelTol',1e-12);
verifyEqual(t,m.nModes,6);
checkSame(t,solveImported(f));
% Units forced the wrong way: refused, with the reason.
verifyError(t,@()vil.importModel(f,"SI"),'vil:Units');
end

function testAnsysCdbWithRbe3(t)
% CDWRITE-style blocks (node IDs offset, trailing zero coordinates omitted),
% MASS21 on a pilot node, RBE3 to the tip component, CMSEL + D,ALL,ALL.
f=file(t,'beam.cdb'); writeCdb(t,f,"rbe3");
[~,info,~,m]=vil.importModel(f);
verifyEqual(t,info.format,"ANSYS"); verifyEqual(t,m.nModes,6);
checkSame(t,solveImported(f));
end

function testAnsysCeAndNodeSupports(t)
% Same model with CE averaging equations and D on each node (mm-t-s, /UNITS,MPA).
f=file(t,'beam_ce.dat'); writeCdb(t,f,"ce");
[~,~,~,m]=vil.importModel(f);
verifyEqual(t,m.units,"mm-t-s");
checkSame(t,solveImported(f));
end

function testWeightedEquationsAreKept(t)
% Unequal *EQUATION coefficients are a weighted average, not replaced by a uniform one.
f=file(t,'w.inp'); vil.exportAbaqus(t.TestData.db,f);
txt=fileread(f); tip=sort(t.TestData.tip); n=numel(tip); ref=size(t.TestData.db.nodes,2)+1;
w=linspace(1,2,n); w=w/sum(w);
eq='';
for d=1:3
    eq=[eq sprintf('*EQUATION\n%d\n%d, %d, 1\n',n+1,ref,d)]; %#ok<AGROW>
    eq=[eq sprintf('%d, %d, %.15g\n',[tip(:).'; repmat(d,1,n); -w])]; %#ok<AGROW>
end
k1=strfind(txt,'*EQUATION'); k2=strfind(txt,'*NSET, NSET=FIXED');
txt=[txt(1:k1(1)-1) eq txt(k2(1):end)];
fid=fopen(f,'w'); fwrite(fid,txt); fclose(fid);
[g,~,mi,m]=vil.importModel(f);
verifyEqual(t,m.payload.weights,w,'AbsTol',1e-12);
c=struct('E',m.E,'nu',m.nu,'rho',m.rho,'fixedNodes',m.fixedNodes, ...
    'payload',struct('massKg',0.5,'nodes',m.payload.nodes,'weights',m.payload.weights));
db=vil.solveModes(g,c,MeshInfo=mi,MinModes=6);
verifyEqual(t,db.payload.weights,w,'AbsTol',1e-12);
verifyEqual(t,db.totalMass,db.structureMass+0.5,'RelTol',1e-12);
verifyNotEqual(t,db.frequencyHz(1),t.TestData.db.frequencyHz(1));
end

function testRefusedModels(t)
% What the model cannot represent is refused with a reason, never skipped.
base=fileread(file2(t));
cases={ ...
    strrep(base,'FIXED, ENCASTRE','FIXED, 1, 1'),'vil:PartialBoundary'; ...
    strrep(base,'FIXED, ENCASTRE','FIXED, 1, 3, 0.001'),'vil:PrescribedMotion'; ...
    strrep(base,'TYPE=C3D10,','TYPE=C3D20,'),'vil:ElementType'; ...
    strrep(base,'*DENSITY',sprintf('*TIE, NAME=T\nA, B\n*DENSITY')),'vil:Unsupported'};
for k=1:size(cases,1)
    f=file(t,sprintf('bad%d.inp',k)); fid=fopen(f,'w'); fwrite(fid,cases{k,1}); fclose(fid);
    verifyError(t,@()vil.importModel(f),cases{k,2});
end
f=file(t,'kin.inp'); writeCae(t,f,"kinematic");
verifyError(t,@()vil.importModel(f),'vil:RigidTie');
f=file(t,'cerig.cdb'); writeCdb(t,f,"cerig");
verifyError(t,@()vil.importModel(f),'vil:RigidTie');
f=file(t,'partial.cdb'); writeCdb(t,f,"partial");
verifyError(t,@()vil.importModel(f),'vil:PartialBoundary');
end

function testStudyFileReproducesStoredResult(t)
% The antenna-carrier reference model as written for Abaqus: the same f1 as
% the stored study project (no fitting).
root='C:/Users/Emir Yusuf Uytun/Documents/BAYKAR/Yorulma';
f=fullfile(root,'abaqus','hollow','reference','reference_modal.inp');
p=fullfile(root,'variants_hollow','projects','reference_VIL.mat');
assumeTrue(t,isfile(f) && isfile(p),'Study files not on this machine.');
[g,~,mi,m]=vil.importModel(f);
old=vil.loadProject(p);
verifyEqual(t,sort(m.fixedNodes(:)),sort(old.fixedNodes(:)));
verifyEqual(t,sort(m.payload.nodes(:)),sort(old.payload.nodes(:)));
c=struct('E',m.E,'nu',m.nu,'rho',m.rho,'fixedNodes',m.fixedNodes,'payload',struct('massKg',m.payload.massKg,'nodes',m.payload.nodes));
db=vil.solveModes(g,c,MeshInfo=mi,MinModes=8);
verifyEqual(t,db.frequencyHz(1:8),old.frequencyHz(1:8),'RelTol',1e-9);
end

function testAppImportsModelReadyToSolve(t)
% In the app: one import sets material, supports and payload; Solve gives
% the reference result without any picking.
f=file(t,'app.cdb'); writeCdb(t,f,"rbe3");
app=VirtualImpactLab; t.TestData.app=app;
app.importModel(f);
s=app.state(); verifyEmpty(t,s.lastError);
verifyTrue(t,s.advanced);
verifyEqual(t,s.support.method,"nodes"); verifyEqual(t,s.payload.method,"nodes");
verifyEqual(t,s.payload.massKg,0.5,'RelTol',1e-12);
verifySubstring(t,findobj(app.figure,'Tag','supportInfo').Text,'ANSYS file');
verifySubstring(t,findobj(app.figure,'Tag','payloadInfo').Text,'RBE3');
app.solve(); s=app.state(); verifyEmpty(t,s.lastError);
verifyEqual(t,s.db.frequencyHz(1:6),t.TestData.db.frequencyHz(1:6),'RelTol',1e-9);
end

% ------------------------------------------------------------ writers ---
function f=file2(t)
f=file(t,'base.inp');
if ~isfile(f), vil.exportAbaqus(t.TestData.db,f); end
end

function writeCae(t,f,kind)
% Abaqus/CAE-style file in mm, tonne, s, MPa.
if nargin<3, kind="distributing"; end
g=t.TestData.g; c=t.TestData.c; X=1e3*g.Mesh.Nodes; T=double(g.Mesh.Elements);
shift=[100;0;0];
fid=fopen(f,'w'); cl=onCleanup(@()fclose(fid));
fprintf(fid,'*Heading\n** Job name: beam Model name: Model-1\n*Preprint, echo=NO\n**\n*Part, name=Beam\n*Node\n');
fprintf(fid,'%7d, %.12g, %.12g, %.12g\n',[1:size(X,2); X-shift]);
fprintf(fid,'*Element, type=C3D10\n');
fprintf(fid,'%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d\n',[1:size(T,2); T]);
fprintf(fid,'*Nset, nset=Fixed\n'); fprintf(fid,'%s\n',strjoin(string(t.TestData.db.fixedNodes(:).'),', '));
fprintf(fid,'*Nset, nset=Tip\n'); fprintf(fid,'%s\n',strjoin(string(t.TestData.tip(:).'),', '));
fprintf(fid,'*Elset, elset=All, generate\n 1, %d, 1\n',size(T,2));
fprintf(fid,'** Section: Section-1\n*Solid Section, elset=All, material=Steel\n,\n*End Part\n**\n');
fprintf(fid,'*Assembly, name=Assembly\n*Instance, name=Beam-1, part=Beam\n %.12g, %.12g, %.12g\n*End Instance\n',shift);
fprintf(fid,'*Node\n      1, 150., 0., 0.\n*Nset, nset=RP\n 1,\n');
fprintf(fid,'*Element, type=MASS, elset=PM\n1, 1\n*Mass, elset=PM\n0.0005,\n');
fprintf(fid,'*Surface, type=NODE, name=TipSurf, internal\nBeam-1.Tip, 1.\n');
fprintf(fid,'*Coupling, constraint name=Antenna, ref node=RP, surface=TipSurf\n');
if kind=="kinematic", fprintf(fid,'*Kinematic\n'); else, fprintf(fid,'*Distributing, weighting method=UNIFORM\n1, 3\n'); end
fprintf(fid,'*End Assembly\n*Material, name=Steel\n*Density\n%.12g,\n*Elastic\n%.12g, %.12g\n',c.rho*1e-12,c.E*1e-6,c.nu);
fprintf(fid,'*Step, name=Modes, nlgeom=NO, perturbation\n*Frequency, eigensolver=Lanczos, normalization=mass\n6, , , , ,\n');
fprintf(fid,'*Boundary\nBeam-1.Fixed, ENCASTRE\n*Output, field, variable=PRESELECT\n*End Step\n');
fprintf(fid,'*Step, name=Static\n*Static\n*Boundary\nBeam-1.Tip, 1, 1, 0.5\n*End Step\n');   % other step: ignored
end

function writeCdb(t,f,kind)
% Ansys blocked input. kind: "rbe3" (SI), "ce" (mm-t-s, D per node),
% "cerig", "partial".
g=t.TestData.g; c=t.TestData.c; X=g.Mesh.Nodes; T=double(g.Mesh.Elements);
n=size(X,2); off=1000; L=1; M=1; P=1; R=1;
if kind=="ce", L=1e3; M=1e-3; P=1e-6; R=1e-12; end
X=L*X; pilot=off+n+5;
fid=fopen(f,'w'); cl=onCleanup(@()fclose(fid));
fprintf(fid,'/COM,ANSYS RELEASE 2024 R1\n/PREP7\n');
if kind=="ce", fprintf(fid,'/UNITS,MPA\n'); end
fprintf(fid,'ET,       1,187\nET,       2,21\nKEYOPT,       2,  3,       2\n');
fprintf(fid,'R,       2,%.12g,%.12g,%.12g\n',0.5*M,0.5*M,0.5*M);
fprintf(fid,'MP,EX  ,       1, %.15g\nMP,PRXY,       1, %.15g\nMP,DENS,       1, %.15g\n',P*c.E,c.nu,R*c.rho);
fprintf(fid,'NBLOCK,6,SOLID,%10d,%10d\n(3i9,6e21.13e3)\n',n,n);
for k=1:n
    x=X(:,k).'; last=find(x~=0,1,'last'); if isempty(last), last=0; end
    fprintf(fid,'%9d%9d%9d%s\n',off+k,0,0,sprintf('%21.13E',x(1:last)));
end
fprintf(fid,'N,R5.3,LOC,       -1,\n');
fprintf(fid,'EBLOCK,19,SOLID,%10d,%10d\n(19i9)\n',size(T,2),size(T,2));
for e=1:size(T,2)
    fprintf(fid,'%9d',[1 1 1 1 0 0 0 0 10 0 e off+T(1:8,e).']); fprintf(fid,'\n');
    fprintf(fid,'%9d',off+T(9:10,e).'); fprintf(fid,'\n');
end
fprintf(fid,'       -1\n');
fprintf(fid,'N,%d,%.12g,%.12g,%.12g\nTYPE,2\nREAL,2\nMAT,1\nE,%d\n',pilot,L*0.150,0,0,pilot);
cm(fid,'FIXED',off+t.TestData.db.fixedNodes); cm(fid,'TIP',off+t.TestData.tip);
switch kind
    case {"rbe3","partial"}
        fprintf(fid,'RBE3,%d,ALL,TIP\n',pilot);
        if kind=="partial", fprintf(fid,'CMSEL,S,FIXED\nD,ALL,UX,0\nALLSEL\n');
        else, fprintf(fid,'CMSEL,S,FIXED\nD,ALL,ALL,0\nALLSEL,ALL\n'); end
    case "cerig"
        fprintf(fid,'CERIG,%d,%d,ALL\nCMSEL,S,FIXED\nD,ALL,ALL,0\n',pilot,off+t.TestData.tip(1));
    case "ce"
        tip=off+t.TestData.tip(:).'; w=1/numel(tip); labs=["UX" "UY" "UZ"];
        for d=1:3
            fprintf(fid,'CE,%d,0,%d,%s,1\n',d,pilot,labs(d));
            for k=1:3:numel(tip)
                j=tip(k:min(k+2,end)); s=strjoin(compose('%d,%s,%.15g',j(:),repmat(labs(d),numel(j),1),repmat(-w,numel(j),1)),',');
                fprintf(fid,'CE,%d,0,%s\n',d,s);
            end
        end
        for k=off+t.TestData.db.fixedNodes(:).', fprintf(fid,'D,%d,UX,0,,,,UY,UZ\n',k); end
end
fprintf(fid,'FINISH\n/SOLU\nANTYPE,MODAL\nMODOPT,LANB,6\nSOLVE\nFINISH\n');
end

function cm(fid,name,ids)
% CMBLOCK with ranges written as negative ends.
ids=sort(ids(:).'); v=[];
k=1;
while k<=numel(ids)
    j=k; while j<numel(ids) && ids(j+1)==ids(j)+1, j=j+1; end
    if j>k, v=[v ids(k) -ids(j)]; else, v=[v ids(k)]; end %#ok<AGROW>
    k=j+1;
end
fprintf(fid,'CMBLOCK,%s,NODE,%8d\n(8i10)\n',name,numel(v));
for k=1:8:numel(v), fprintf(fid,'%10d',v(k:min(k+7,end))); fprintf(fid,'\n'); end
end
