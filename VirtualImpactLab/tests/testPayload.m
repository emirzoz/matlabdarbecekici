function tests=testPayload
% Payload (antenna) mass, node/plane supports, imported meshes and project
% round trips, on the small demo beam (300 x 20 x 20 mm, clamped at X = -150 mm).
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
[g,c,mi]=vil.createDemoBeam(0.01);
t.TestData.g=g; t.TestData.c=c; t.TestData.mi=mi;
t.TestData.base=vil.solveModes(g,c,MeshInfo=mi,MinModes=6);
end
function spec=plane(axis,mm,tol)
spec=struct('method',"plane",'axis',axis,'positionMm',mm,'toleranceMm',tol);
end
function ids=tipNodes(t)
ids=vil.selectNodes(t.TestData.g.Mesh.Nodes,t.TestData.g.Mesh.Elements,t.TestData.mi.surface,plane(1,150,1e-3));
end

function testZeroPayloadKeepsTheOldResult(t)
% Payload switched off (0 kg, or present but disabled) solves exactly as before.
g=t.TestData.g; c=t.TestData.c; mi=t.TestData.mi; base=t.TestData.base;
c.payload=struct('massKg',0,'nodes',tipNodes(t));
db=vil.solveModes(g,c,MeshInfo=mi,MinModes=6);
verifyEqual(t,db.frequencyHz,base.frequencyHz,'RelTol',1e-12);
verifyEqual(t,db.totalMass,base.totalMass,'RelTol',1e-14);
verifyEqual(t,db.structureMass,db.totalMass,'RelTol',1e-14);
verifyEqual(t,db.payloadMass,0);
end

function testPayloadMassMatrix(t)
% M_total = M + m*B'*B: total mass grows by m, and every mode satisfies the
% generalized problem with an independently built B.
g=t.TestData.g; c=t.TestData.c; mi=t.TestData.mi;
tip=tipNodes(t); m=0.5;
c.payload=struct('massKg',m,'nodes',tip);
[db,A]=vil.solveModes(g,c,MeshInfo=mi,MinModes=6);
n=size(g.Mesh.Nodes,2);
verifyEqual(t,db.totalMass,db.structureMass+m,'RelTol',1e-12);
verifyEqual(t,db.structureMass,t.TestData.base.totalMass,'RelTol',1e-12);
B=zeros(3,3*n);
for d=1:3, B(d,(d-1)*n+tip)=1/numel(tip); end
Mt=A.Mstructure+m*sparse(B.'*B);
verifyLessThan(t,full(max(abs(A.M-Mt),[],'all')),1e-12*full(max(abs(Mt),[],'all')));   % mats.M is the total
P=db.Phi(db.freeDofs,:); K=A.K(db.freeDofs,db.freeDofs); M=Mt(db.freeDofs,db.freeDofs);
verifyEqual(t,P.'*M*P,eye(numel(db.omega)),'AbsTol',1e-8);
r=vecnorm(K*P-M*P*diag(db.omega.^2))./vecnorm(K*P);
verifyLessThan(t,max(r),1e-6);
% Rigid translation of the payload nodes moves the payload by the same amount.
e=zeros(3*n,1); e(n+(1:n))=1; verifyEqual(t,B*e,[0;1;0],'AbsTol',1e-14);
% A tip mass lowers the first bending mode (Rayleigh: k/(m_eff + 0.5 kg)).
verifyLessThan(t,db.frequencyHz(1),t.TestData.base.frequencyHz(1));
% Participation uses M_total (effective masses consistent with totalMass).
for d=1:3
    rr=zeros(3*n,1); rr((d-1)*n+(1:n))=1;
    verifyEqual(t,db.participation(d,:),(db.Phi.'*(Mt*rr)).','AbsTol',1e-10);
end
% The payload is recorded under both the new and the older field names.
verifyEqual(t,db.config.payloadKg,m); verifyEqual(t,db.tipNodes,tip(:));
end

function testPlaneSupportEqualsFaceClamp(t)
% The clamped end face is the plane X = -150 mm: same nodes, same modes.
g=t.TestData.g; c=t.TestData.c; mi=t.TestData.mi; base=t.TestData.base;
[ids,info]=vil.selectNodes(g.Mesh.Nodes,g.Mesh.Elements,mi.surface,plane("X",-150,1e-3));
verifyEqual(t,sort(ids(:)),sort(base.fixedNodes(:)));
verifyEqual(t,info.rangeMm,[-150 150],'AbsTol',1e-9);
% Face selection includes midside nodes, exactly as findNodes does.
fn=vil.selectNodes(g.Mesh.Nodes,g.Mesh.Elements,mi.surface,struct('method',"faces",'faces',c.fixedFaces));
verifyEqual(t,sort(fn(:)),sort(findNodes(g.Mesh,'region','Face',c.fixedFaces)).');
c2=c; c2.fixedFaces=[]; c2.fixedNodes=ids;
db=vil.solveModes(g,c2,MeshInfo=mi,MinModes=6);
verifyEqual(t,db.frequencyHz,base.frequencyHz,'RelTol',1e-10);
end

function testSelectionErrors(t)
g=t.TestData.g; c=t.TestData.c; mi=t.TestData.mi;
X=g.Mesh.Nodes; E=g.Mesh.Elements; s=mi.surface;
verifyError(t,@()vil.selectNodes(X,E,s,plane(3,80,0.05)),'vil:EmptySelection');
verifyError(t,@()vil.selectNodes(X,E,s,struct('method',"faces",'faces',999)),'vil:BadFace');
end_=vil.selectNodes(X,E,s,plane(1,-150,1e-3));
c.payload=struct('massKg',0.5,'nodes',end_);                 % on the clamp
verifyError(t,@()vil.solveModes(g,c,MeshInfo=mi,MinModes=3),'vil:PayloadOnSupport');
c.payload=struct('massKg',-1,'nodes',tipNodes(t));
verifyError(t,@()vil.solveModes(g,c,MeshInfo=mi,MinModes=3),'vil:PayloadMass');
c.payload=struct('massKg',NaN,'nodes',tipNodes(t));
verifyError(t,@()vil.solveModes(g,c,MeshInfo=mi,MinModes=3),'vil:PayloadMass');
c.payload=struct('massKg',0.5,'nodes',[]);
verifyError(t,@()vil.solveModes(g,c,MeshInfo=mi,MinModes=3),'vil:EmptySelection');
c.fixedFaces=[]; c=rmfield(c,'payload');
verifyError(t,@()vil.solveModes(g,c,MeshInfo=mi,MinModes=3),'vil:NoFixture');
end

function testImportedMeshUnitsAndChecks(t)
g=t.TestData.g; base=t.TestData.base;
X=g.Mesh.Nodes.'; T=g.Mesh.Elements.';
f=[tempname '.mat']; cleanup=onCleanup(@()delete(f));
% Millimetres, guessed from the size and confirmed by an explicit unit.
nodes=1e3*X; elements=T; save(f,'nodes','elements');
[g2,info,mi2]=vil.importMesh(f);
verifyEqual(t,info.fileUnits,"mm"); verifyEqual(t,info.scaleApplied,1e-3);
verifyEqual(t,g2.Mesh.Nodes,g.Mesh.Nodes,'AbsTol',1e-12);
verifyEqual(t,mi2.order,"quadratic"); verifyEqual(t,mi2.numNodes,size(X,1));
verifyEqual(t,mi2.volume,0.3*0.02*0.02,'RelTol',1e-9);
[~,info]=vil.importMesh(f,"mm"); verifyEqual(t,info.scaleApplied,1e-3);
% The same mesh, solved without remeshing, with a plane clamp at X = -150 mm.
fixed=vil.selectNodes(g2.Mesh.Nodes,g2.Mesh.Elements,mi2.surface,plane(1,-150,1e-3));
c=struct('E',210e9,'nu',0.3,'rho',7800,'fixedNodes',fixed,'rangeHz',[0 0]);
db=vil.solveModes(g2,c,MeshInfo=mi2,MinModes=6);
verifyEqual(t,db.frequencyHz,base.frequencyHz,'RelTol',1e-9);
% Volume stored in mm^3 decides the unit when the size alone would not.
nodes=X; tetVolume_mm3=1e9*0.3*0.02*0.02; save(f,'nodes','elements','tetVolume_mm3');
[~,info]=vil.importMesh(f); verifyEqual(t,info.fileUnits,"m");
verifySubstring(t,info.scaleNote,"tetVolume_mm3");
% Midside nodes left without an element are refused (node IDs must stay).
elements=T(:,1:4); save(f,'nodes','elements');
verifyError(t,@()vil.importMesh(f,"m"),'vil:MeshNodes');
% Linear corners only; inverted elements are reordered; bad meshes refused.
[u,~,j]=unique(T(:,1:4)); nodes=X(u,:); L=reshape(j,[],4);
elements=L(:,[1 3 2 4]); save(f,'nodes','elements');
[g3,~,mi3]=vil.importMesh(f,"m");
verifyTrue(t,mi3.reordered); verifyEqual(t,mi3.order,"linear");
verifyEqual(t,mi3.volume,0.3*0.02*0.02,'RelTol',1e-9);
verifyEqual(t,size(g3.Mesh.Elements,1),4);
elements=L-1; save(f,'nodes','elements');
verifyError(t,@()vil.importMesh(f,"m"),'vil:MeshElements');
elements=L; elements(1,2)=size(nodes,1)+5; save(f,'nodes','elements');
verifyError(t,@()vil.importMesh(f,"m"),'vil:MeshElements');
elements=L; elements(1,[2 3])=elements(1,[3 2]); save(f,'nodes','elements');
verifyError(t,@()vil.importMesh(f,"m"),'vil:MeshVolume');
end

function testProjectRoundTripKeepsSettings(t)
g=t.TestData.g; c=t.TestData.c; mi=t.TestData.mi;
tip=tipNodes(t);
c.fixedFaces=[]; c.fixedNodes=vil.selectNodes(g.Mesh.Nodes,g.Mesh.Elements,mi.surface,plane(1,-150,1e-3));
c.support=struct('method',"plane",'faces',[],'axis',1,'positionMm',-150,'toleranceMm',1e-3);
c.payload=struct('massKg',0.75,'nodes',tip,'selection',struct('method',"plane",'faces',[],'axis',1,'positionMm',150,'toleranceMm',1e-3));
c.materialName="Structural steel";
db=vil.solveModes(g,c,MeshInfo=mi,MinModes=4);
f=[tempname '.mat']; cleanup=onCleanup(@()delete(f));
vil.saveProject(f,db,{});
[db2,tests,s]=vil.loadProject(f);
verifyEmpty(t,tests);
verifyEqual(t,db2.frequencyHz,db.frequencyHz);
verifyEqual(t,s.payload.enabled,true); verifyEqual(t,s.payload.massKg,0.75);
verifyEqual(t,s.payload.method,"plane"); verifyEqual(t,s.payload.positionMm,150);
verifyEqual(t,s.payload.nodes(:),tip(:));
verifyEqual(t,s.support.method,"plane"); verifyEqual(t,s.support.axis,1);
verifyEqual(t,s.support.positionMm,-150); verifyEqual(t,s.support.count,numel(c.fixedNodes));
verifyEqual(t,s.material.name,"Structural steel"); verifyEqual(t,s.material.rho,7800);
verifyEqual(t,db2.structureMass,db.structureMass); verifyEqual(t,db2.payloadMass,0.75);
end

function testLegacyPayloadProject(t)
% The earlier study layout: fixedFaces empty, fixedNodes on Z-like plane,
% payloadKg/payloadModel/tipZ/endPlaneTolerance in config, tipNodes in db.
g=t.TestData.g; c=t.TestData.c; mi=t.TestData.mi;
X=g.Mesh.Nodes;
fixed=find(abs(X(1,:)+0.15)<=5e-5); tip=find(abs(X(1,:)-0.15)<=5e-5);
c.fixedFaces=[]; c.fixedNodes=fixed; c.payload=struct('massKg',0.5,'nodes',tip);
db=vil.solveModes(g,c,MeshInfo=mi,MinModes=4);
old=db; old=rmfield(old,{'payload','payloadMass','structureMass'});
old.config=rmfield(old.config,{'payload','fixedNodes'}); old.config.fixedNodes=fixed;
old.config.payloadModel="Uniform average top translation, zero rotary inertia";
f=[tempname '.mat']; cleanup=onCleanup(@()delete(f));
db=old; tests={}; save(f,'db','tests','-v7.3');           % no settings variable
[db2,~,s]=vil.loadProject(f);
verifyEqual(t,db2.payloadMass,0.5);
verifyEqual(t,db2.structureMass,t.TestData.base.totalMass,'RelTol',1e-12);
verifyEqual(t,s.support.method,"plane"); verifyEqual(t,s.support.axis,1);
verifyEqual(t,s.support.positionMm,-150); verifyEqual(t,s.support.toleranceMm,0.05);
verifyEqual(t,s.support.count,numel(fixed));
verifyTrue(t,s.payload.enabled); verifyEqual(t,s.payload.nodes(:),tip(:));
end

function testSweepSolvesEachMass(t)
g=t.TestData.g; c=t.TestData.c; mi=t.TestData.mi;
c.payload=struct('massKg',0,'nodes',tipNodes(t));
r=vil.payloadSweep(g,c,[0 0.5 1],MeshInfo=mi,MinModes=3);
verifyFalse(t,r.cancelled); verifyEqual(t,height(r.table),3);
verifyEqual(t,r.table.f1_Hz(1),t.TestData.base.frequencyHz(1),'RelTol',1e-9);
verifyTrue(t,issorted(-r.table.f1_Hz));
c.payload.massKg=1; db=vil.solveModes(g,c,MeshInfo=mi,MinModes=3);
verifyEqual(t,r.table.f1_Hz(3),db.frequencyHz(1),'RelTol',1e-9);
% Cancel before the second solve.
calls=0; r=vil.payloadSweep(g,c,[0.5 1],MeshInfo=mi,MinModes=3,Cancel=@stop);
verifyTrue(t,r.cancelled); verifyEqual(t,height(r.table),1);
    function tf=stop(), calls=calls+1; tf=calls>1; end
end

function testCompareGroupsAssumptions(t)
g=t.TestData.g; c=t.TestData.c; mi=t.TestData.mi;
c.payload=struct('massKg',0.5,'nodes',tipNodes(t),'selection',struct('method',"plane",'faces',[],'axis',1,'positionMm',150,'toleranceMm',1e-3));
a=vil.solveModes(g,c,MeshInfo=mi,MinModes=3);
c.payload.massKg=1; b=vil.solveModes(g,c,MeshInfo=mi,MinModes=3);
[T,notes]=vil.compareProjects({a,a,b},Names=["a" "a2" "b"]);
verifyEqual(t,height(T),3);
verifyEqual(t,numel(unique(T.Group)),2);
verifySubstring(t,strjoin(notes),"Payload_kg");
end

function testAbaqusExportWritesPayload(t)
g=t.TestData.g; c=t.TestData.c; mi=t.TestData.mi;
c.payload=struct('massKg',0.5,'nodes',tipNodes(t));
db=vil.solveModes(g,c,MeshInfo=mi,MinModes=3);
f=[tempname '.inp']; cleanup=onCleanup(@()delete(f));
vil.exportAbaqus(db,f);
txt=fileread(f);
verifySubstring(t,txt,'*MASS, ELSET=PAYLOAD');
verifyEqual(t,numel(strfind(txt,'*EQUATION')),3);
end
