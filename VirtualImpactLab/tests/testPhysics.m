function tests=testPhysics
tests=functiontests(localfunctions);
end
function db=fixture
% Synthetic system: two known mass-normalized component-blocked modes.
db=struct('nodes',[0 1;0 0;0 0],'surfaceNodes',[1;2], ...
    'Phi',[1 0.2;0.5 -0.4;zeros(4,2)],'omega',2*pi*[10;25]);
db.frequencyHz=db.omega/(2*pi);
end
function reciprocity(t)
db=fixture; f=0:0.1:15;
a=vil.calculateFRF(db,{1,'X'},{2,'X'},f,0.02);
b=vil.calculateFRF(db,{2,'X'},{1,'X'},f,0.02);
verifyEqual(t,a.accelerance,b.accelerance,'AbsTol',1e-12);
verifyEqual(t,a.accelerance,-(2*pi*f).^2.*a.displacement,'AbsTol',1e-12);
verifyEqual(t,a.displacementUnits,'m/N');
end
function dampingAndTruncation(t)
db=fixture;
a=vil.calculateFRF(db,{1,'X'},{1,'X'},10,0.01);
b=vil.calculateFRF(db,{1,'X'},{1,'X'},10,0.05);
verifyGreaterThan(t,abs(a.displacement),abs(b.displacement));
short=db; short.Phi=short.Phi(:,1); short.omega=short.omega(1); short.frequencyHz=10;
c=vil.calculateFRF(short,{1,'X'},{1,'X'},0,0.01);
d=vil.calculateFRF(db,{1,'X'},{1,'X'},0,0.01);
verifyEqual(t,d.displacement-c.displacement,0.2^2/db.omega(2)^2,'AbsTol',1e-14);
end
function timeAndFrequency(t)
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
function massAndMapping(t)
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
