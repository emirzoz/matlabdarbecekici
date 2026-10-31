function tests=testPhysics
tests=functiontests(localfunctions);
end
function setupOnce(t)
% Run from any folder: put the app (package +vil) on the path.
t.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
end
function db=fixture
% Synthetic system: two known mass-normalized component-blocked modes.
db=struct('nodes',[0 1;0 0;0 0],'surfaceNodes',[1;2], ...
    'Phi',[1 0.2;0.5 -0.4;zeros(4,2)],'omega',2*pi*[10;25]);
db.frequencyHz=db.omega/(2*pi);
end
function testReciprocity(t)
db=fixture; f=0:0.1:15;
a=vil.calculateFRF(db,{1,'X'},{2,'X'},f,0.02);
b=vil.calculateFRF(db,{2,'X'},{1,'X'},f,0.02);
verifyEqual(t,a.accelerance,b.accelerance,'AbsTol',1e-12);
verifyEqual(t,a.accelerance,-(2*pi*f).^2.*a.displacement,'AbsTol',1e-12);
verifyEqual(t,a.displacementUnits,'m/N');
end
function testDampingAndTruncation(t)
db=fixture;
a=vil.calculateFRF(db,{1,'X'},{1,'X'},10,0.01);
b=vil.calculateFRF(db,{1,'X'},{1,'X'},10,0.05);
verifyGreaterThan(t,abs(a.displacement),abs(b.displacement));
short=db; short.Phi=short.Phi(:,1); short.omega=short.omega(1); short.frequencyHz=10;
c=vil.calculateFRF(short,{1,'X'},{1,'X'},0,0.01);
d=vil.calculateFRF(db,{1,'X'},{1,'X'},0,0.01);
verifyEqual(t,d.displacement-c.displacement,0.2^2/db.omega(2)^2,'AbsTol',1e-14);
end
function testTimeAndFrequency(t)
db=fixture; before=db;
p=struct('peakForce',10,'contactDuration',0.02,'duration',4,'fs',4000,'zeta',0.05);
a=vil.simulateImpact(db,{1,'X'},{2,'X'},p);
p.peakForce=20; b=vil.simulateImpact(db,{1,'X'},{2,'X'},p);
verifyEqual(t,b.acceleration,2*a.acceleration,'AbsTol',1e-10);
verifyEqual(t,db,before); % Cache is immutable; no FEM solver dependency here.
% Transform finite records after damped ring-down; compare complex accelerance.
F=fft(a.force); Y=fft(a.acceleration); N=numel(a.time); idx=2:floor(N/2);
f=(idx-1)*p.fs/N; use=f<18 & abs(F(idx))>0.1*max(abs(F)); idx=idx(use); f=f(use);
h=vil.calculateFRF(db,{1,'X'},{2,'X'},f,p.zeta);
verifyLessThan(t,norm(Y(idx)./F(idx)-h.accelerance)/norm(h.accelerance),0.02);
end
function testMassAndMapping(t)
% Six DOFs, two constrained; known non-unit modal masses.
M=diag([2 3 4 5 6 7]); K=diag((1:6).^2); P=zeros(6,2); P(1,1)=3; P(4,2)=2;
w=sqrt([K(1,1)/M(1,1);K(4,4)/M(4,4)]);
% Tetrahedron for surface extraction, with 12 DOFs.
M=blkdiag(M,eye(6)); K=blkdiag(K,eye(6)); P=[P;zeros(6,2)];
db=vil.buildModalDatabase([0 1 0 0;0 0 1 0;0 0 0 1],[1;2;3;4],P,w,M,K,1:12,struct);
verifyEqual(t,db.Phi'*M*db.Phi,eye(2),'AbsTol',1e-12);
verifyEqual(t,vil.mapProbePoints(db,4,'X'),db.Phi(4,:));
verifyEqual(t,vil.mapProbePoints(db,1,'Y'),db.Phi(5,:));
end
function testSurfaceNodeRemapping(t)
% An unused point precedes the actual tetrahedron corners in global IDs.
nodes=[0.5 0 1 0 0;0.5 0 0 1 0;0.5 0 0 0 1];
M=speye(15); K=spdiags((1:15).',0,15,15);
P=zeros(15,1); P(2)=1;
db=vil.buildModalDatabase(nodes,[2;3;4;5],P,sqrt(2),M,K,1:15,struct);
verifyEqual(t,db.surfaceNodes,[2;3;4;5]);
verifyEqual(t,sort(unique(db.surfaceFaces(:))),[2;3;4;5]);
end
function testVectorDirection(t)
% A 3-vector direction is the projection of the X/Y/Z modal amplitudes.
db=fixture; db.Phi=[1 0.2;0.5 -0.4;0.3 0.1;0.7 0.6;-0.2 0.9;0.4 -0.5];
d=[1 2 2];
expected=(d/3)*[db.Phi(1,:);db.Phi(3,:);db.Phi(5,:)];
verifyEqual(t,vil.mapProbePoints(db,1,d),expected,'AbsTol',1e-14);
verifyEqual(t,vil.mapProbePoints(db,2,[0 0 5]),db.Phi(6,:),'AbsTol',1e-14);
end
function testSurfaceNormalPointsOutward(t)
% Unit tetrahedron: the origin node touches the x=0, y=0 and z=0 faces
% (equal areas), so its outward normal is -(1,1,1)/sqrt(3).
nodes=[0 1 0 0;0 0 1 0;0 0 0 1];
tr=triangulation([1 2 3 4],nodes.'); tri=freeBoundary(tr);
n=vil.surfaceNormal(nodes,tri,1);
verifyEqual(t,n,-[1;1;1]/sqrt(3),'AbsTol',1e-12);
end
function testModalCutoff(t)
% Dropping the 25 Hz mode leaves only the 10 Hz mode's response.
db=fixture;
p=struct('peakForce',10,'contactDuration',0.02,'duration',1,'fs',2000,'zeta',0.02,'maxModeHz',15);
a=vil.simulateImpact(db,{1,'X'},{2,'X'},p);
one=db; one.Phi=db.Phi(:,1); one.omega=db.omega(1); one.frequencyHz=10;
p.maxModeHz=[]; b=vil.simulateImpact(one,{1,'X'},{2,'X'},p);
verifyEqual(t,a.acceleration,b.acceleration,'AbsTol',1e-12);
end
function testCompareModes(t)
% Swapped, scaled and sign-flipped modes pair up with MAC 1.
A=[1 0;0 1;1 1]; B=[0 -2;3 0;3 -2];
T=vil.compareModes([10;20],A,[20.2;10],B);
verifyEqual(t,T.RefMode,[2;1]);
verifyEqual(t,T.MAC,[1;1],'AbsTol',1e-12);
verifyEqual(t,T.Error_pct,[0;100*(20/20.2-1)],'AbsTol',1e-12);
end
function testPointProbesInterpolate(t)
% Unit square in z = 0, two triangles, two modes with known nodal values.
db=struct('nodes',[0 1 1 0;0 0 1 1;0 0 0 0],'surfaceFaces',[1 2 3;1 3 4],'surfaceNodes',(1:4).');
db.Phi=[1:4 zeros(1,4) 10*(1:4); 4:-1:1 zeros(1,4) zeros(1,4)].';
% At a node: that node. Mid-edge: the mean of its ends. Off the surface: projected.
verifyEqual(t,vil.mapProbePoints(db,[1 0 0],'X'),vil.mapProbePoints(db,2,'X'),'AbsTol',1e-12);
verifyEqual(t,vil.mapProbePoints(db,[1 0.5 0],'X'),(db.Phi(2,:)+db.Phi(3,:))/2,'AbsTol',1e-12);
verifyEqual(t,vil.mapProbePoints(db,[0.5 0.5 0.3],'Z'),(db.Phi(9,:)+db.Phi(11,:))/2,'AbsTol',1e-12);
% A tip face covering the whole square: tributary-area mean (corners 1, 3
% touch two triangles, so they weigh twice as much as 2 and 4).
w=[2 1 2 1]/6;
verifyEqual(t,vil.mapProbePoints(db,[0.5 0.5 0],'X',Radius=2),w*db.Phi(1:4,:),'AbsTol',1e-12);
% A tiny face that holds no triangle centre falls back to the point.
verifyEqual(t,vil.mapProbePoints(db,[1 0 0],'X',Radius=1e-6),db.Phi(2,:),'AbsTol',1e-12);
end
function testRayleighDamping(t)
w=2*pi*[100;300;1000];
z=vil.rayleighDamping(w,0.01,0.03);
verifyEqual(t,z([1 3]),[0.01;0.03],'RelTol',1e-12);
% Rayleigh is lowest between the two anchors when both terms matter.
verifyLessThan(t,z(2),0.03);
verifyGreaterThan(t,vil.rayleighDamping(2*pi*[1;30;1000],0.5,1e-4),0);
end
