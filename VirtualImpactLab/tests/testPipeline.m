function tests=testPipeline
% FEM integration tests (need PDE Toolbox). STEP parts live in ../../imports.
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
t.TestData.imports=fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))),'imports');
end
function testStepIsAlreadyInMetres(t)
% block.step is 40 x 30 x 20 mm and declares millimetres. Import must not
% scale it again (the original 1e-3 default shrank parts 1000x).
f=fullfile(t.TestData.imports,'block.step');
assumeTrue(t,isfile(f),'block.step not available');
[g,info]=vil.importCAD(f);
verifyEqual(t,info.fileUnits,"mm");
verifyEqual(t,info.span,[0.04 0.03 0.02],'AbsTol',1e-9);
verifyEqual(t,g.NumCells,1);
end
function testBlockMassAndModes(t)
f=fullfile(t.TestData.imports,'block.step');
assumeTrue(t,isfile(f),'block.step not available');
g=vil.importCAD(f); [g,mi]=vil.meshPart(g,0.005);
V=g.Mesh.Nodes; lo=min(V,[],2); hi=max(V,[],2); mid=(lo+hi)/2;
c=struct('E',210e9,'nu',0.3,'rho',7800,'rangeHz',[0 0],'fixedFaces',nearestFace(g,[mid(1) mid(2) lo(3)-1e-6]));
db=vil.solveModes(g,c,MeshInfo=mi,MinModes=6);
verifyEqual(t,db.totalMass,7800*0.04*0.03*0.02,'RelTol',1e-9);
verifyNumElements(t,db.omega,6);
verifyTrue(t,issorted(db.omega));
verifyLessThan(t,db.massOrthogonalityError,1e-6);
% Clamped nodes carry no modal motion.
n=size(db.nodes,2); fixedDofs=[db.fixedNodes; db.fixedNodes+n; db.fixedNodes+2*n];
verifyEqual(t,max(abs(db.Phi(fixedDofs,:)),[],'all'),0);
% A saved project reloads unchanged and keeps running impacts.
f=[tempname '.mat']; cleanup=onCleanup(@()delete(f));
vil.saveProject(f,db,{}); [db2,tests]=vil.loadProject(f);
verifyEqual(t,db2.Phi,db.Phi); verifyEqual(t,db2.fixedNodes,db.fixedNodes); verifyEmpty(t,tests);
end
function testBeamMatchesTheory(t)
[g,c,mi]=vil.createDemoBeam(0.006); db=vil.solveModes(g,c,MeshInfo=mi,MinModes=4);
I=c.width*c.height^3/12;
theory=1.875104068711961^2/(2*pi*c.L^2)*sqrt(c.E*I/(c.rho*c.width*c.height));
% Square section: the first two bending modes are (nearly) repeated.
verifyEqual(t,db.frequencyHz(1:2),[theory;theory],'RelTol',0.01);
end
function testFreeFreeBeamMatchesTheory(t)
[g,c,mi]=vil.createDemoBeam(0.006);
c.boundary="free"; db=vil.solveModes(g,c,MeshInfo=mi,MinModes=4);
% Six rigid-body modes are found and removed; only elastic modes remain.
verifyNumElements(t,db.rigidBodyHz,6);
verifyLessThan(t,max(db.rigidBodyHz),1e-3*db.frequencyHz(1));
verifyEmpty(t,db.fixedNodes);
I=c.width*c.height^3/12;
theory=4.730040744862704^2/(2*pi*c.L^2)*sqrt(c.E*I/(c.rho*c.width*c.height));
verifyEqual(t,db.frequencyHz(1:2),[theory;theory],'RelTol',0.01);
% A free part cannot be shaken through a clamp.
f=struct('rpm',4000,'rpmRange',[1500 5500],'order',1,'amplitudeG',1,'psd',[20 1e-3;2000 1e-3], ...
    'axis',3,'zeta',0.01,'monitor',{{db.surfaceNodes(1),'Z'}},'marginPct',10);
verifyError(t,@()vil.flightResponse(db,f),'vil:FreeFree');
end
function testUnconstrainedPartIsRejected(t)
[g,c,mi]=vil.createDemoBeam(0.02);
% Clamping no face is refused before solving.
c.fixedFaces=[];
verifyError(t,@()vil.solveModes(g,c,MeshInfo=mi),'vil:NoFixture');
end
function testNonSolidStepHasClearError(t)
f=fullfile(t.TestData.imports,'nema17-mount-bracket.step');
assumeTrue(t,isfile(f),'nema17-mount-bracket.step not available');
verifyError(t,@()vil.importCAD(f),'vil:NotSolid');
end
function testTessellationFallback(t)
% bearing-housing.step never meshes from its B-rep in R2025b.
f=fullfile(t.TestData.imports,'bearing-housing.step');
assumeTrue(t,isfile(f),'bearing-housing.step not available');
g=vil.importCAD(f); [g,mi]=vil.meshPart(g,0.008);
verifyTrue(t,mi.fromTessellation);
verifyGreaterThan(t,size(g.Mesh.Nodes,2),1000);
verifyFalse(t,any(mi.surface.faceId==0));
end
