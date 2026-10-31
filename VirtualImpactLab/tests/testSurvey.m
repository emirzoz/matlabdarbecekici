function tests=testSurvey
% Roving test processing and flight response on a system with known answers.
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
end
function db=fixture
% Three mass-normalized modes on five points. Point 5 is dead (on the clamp).
Phi=zeros(15,3); Phi(1:5,:)=[1 .8 .6;.7 -.5 .9;.4 .9 -.7;.9 .3 .5;0 0 0];
db=struct('nodes',[0 1 2 3 4;zeros(2,5)],'surfaceNodes',(1:5).','Phi',Phi, ...
    'omega',2*pi*[120;310;520]);
db.frequencyHz=db.omega/(2*pi);
db.participation=[0.5 -0.2 0.1;zeros(2,3)];
db.totalMass=1;
end
function c=roving(nodes)
c=struct('rove',"hammer",'fixed',{{1,'X'}},'roving',{arrayfun(@(n){n,'X'},nodes,'UniformOutput',false)});
end
function p=hit(zeta)
p=struct('peakForce',100,'contactDuration',4e-4,'zeta',zeta,'duration',0,'fs',0,'maxModeHz',[]);
end
function testFrfFromSignalsMatchesFormula(t)
db=fixture; s=vil.runSurvey(db,roving(2),hit(0.02));
f=vil.calculateFRF(db,{2,'X'},{1,'X'},s.frequencyHz,0.02);
verifyLessThan(t,norm(s.H-f.accelerance)/norm(f.accelerance),1e-3);
end
function testRecoversFrequencyAndDamping(t)
db=fixture;
for zeta=[0.005 0.02 0.05]
    s=vil.analyseSurvey(db,vil.runSurvey(db,roving(1:4),hit(zeta)));
    verifyEqual(t,s.modes.frequencyHz,db.frequencyHz,'RelTol',1e-5);
    verifyEqual(t,s.modes.zeta,zeta*ones(3,1),'RelTol',1e-3);
    verifyEqual(t,s.modes.mac,ones(3,1),'AbsTol',1e-6);
end
end
function testModalConstantsMatch(t)
db=fixture; s=vil.analyseSurvey(db,vil.runSurvey(db,roving(1:4),hit(0.02)));
verifyEqual(t,s.modes.A,s.W(1:4,:),'AbsTol',1e-3);
end
function testShortRecordIsWindowedAndCorrected(t)
db=fixture; p=hit(0.01); p.duration=0.15;       % far from rung down
s=vil.analyseSurvey(db,vil.runSurvey(db,roving(1:4),p));
verifyTrue(t,isfinite(s.tau));
verifyEqual(t,s.modes.zeta,0.01*ones(3,1),'RelTol',0.01);
verifyEqual(t,s.modes.frequencyHz,db.frequencyHz,'RelTol',1e-4);
end
function testDeadPointIsRemoved(t)
db=fixture; s=vil.analyseSurvey(db,vil.runSurvey(db,roving(1:5),hit(0.02)));
verifyEqual(t,s.use,[true;true;true;true;false]);
verifyEqual(t,s.modes.frequencyHz,db.frequencyHz,'RelTol',1e-5);
end
function testWeakPointIsRemovedButComparablePointKept(t)
db=fixture; db.Phi(4,:)=0.02*db.Phi(4,:);        % 34 dB down
s=vil.analyseSurvey(db,vil.runSurvey(db,roving(1:4),hit(0.02)));
verifyEqual(t,s.use,[true;true;true;false]);
db=fixture; db.Phi(4,:)=0.3*db.Phi(4,:);         % 10 dB down: a real signal
s=vil.analyseSurvey(db,vil.runSurvey(db,roving(1:4),hit(0.02)));
verifyTrue(t,all(s.use));
end
function testManualOverride(t)
db=fixture; s=vil.runSurvey(db,roving(1:4),hit(0.02));
s=vil.analyseSurvey(db,s,Use=[true;true;false;true]);
verifyEqual(t,nnz(s.use),3);
verifyError(t,@()vil.analyseSurvey(db,s,Use=false(4,1)),'vil:NoResponse');
end
function testFixedPointOnNodeReportsMissingMode(t)
db=fixture; db.Phi(1,2)=0;                       % fixed point on a node of mode 2
s=vil.analyseSurvey(db,vil.runSurvey(db,roving(2:4),hit(0.02)));
verifyEqual(t,[s.modes.missing.mode],2);
verifyTrue(t,s.modes.missing.weak);
end
function testBandLimitReported(t)
db=fixture; p=hit(0.02); p.contactDuration=2.5e-3;  % 1.2/Tc = 480 Hz
s=vil.analyseSurvey(db,vil.runSurvey(db,roving(1:4),p));
verifyEqual(t,s.modes.aboveBand,1);
end
function testHitBelowFirstModeHasClearError(t)
% A soft, long hit (1.2/Tc = 60 Hz) cannot reach the 120 Hz first mode.
db=fixture; p=hit(0.02); p.contactDuration=2e-2;
verifyError(t,@()vil.runSurvey(db,roving(1:4),p),'vil:BandBelowModes');
end
function testTransmissibilityLimits(t)
db=fixture; db.participation=[0.5 -0.2 0.1;zeros(2,3)];
% Below every mode the part follows the clamp.
verifyEqual(t,abs(vil.baseTransmissibility(db,1,{1,'X'},0.01,0.02)),1,'RelTol',1e-6);
% Cross-axis direct term is zero and one mode alone gives Q*phi*Gamma + direct.
one=db; one.Phi=db.Phi(:,1); one.omega=db.omega(1); one.frequencyHz=db.frequencyHz(1); one.participation=db.participation(:,1);
T=vil.baseTransmissibility(one,1,{1,'X'},one.frequencyHz,0.02);
verifyEqual(t,T,1+1*0.5/(2i*0.02),'RelTol',1e-12);
end
function testFlightVerdicts(t)
db=fixture;
f=struct('rpm',3600,'rpmRange',[1000 5000],'order',2,'amplitudeG',1,'psd',[10 .01;2000 .01], ...
    'axis',1,'zeta',0.02,'monitor',{{1,'X'}},'marginPct',10);
% 120 Hz tone sits exactly on mode 1.
r=vil.flightResponse(db,f);
verifyEqual(t,r.toneHz,120); verifyEqual(t,r.status(1),"RESONANCE at cruise");
verifyEqual(t,r.toneOutG,abs(1+0.5/(2i*0.02)),'RelTol',0.05);
% Off resonance but swept through it inside the RPM range.
f.rpm=2200; r=vil.flightResponse(db,f);
verifyEqual(t,r.status(1),"Crossed in RPM range"); verifyEqual(t,r.crossingRpm(1),3600,'RelTol',1e-9);
% No crossing at all.
f.rpm=1500; f.rpmRange=[1200 1800]; r=vil.flightResponse(db,f);
verifyEqual(t,r.status(1),"Clear");
end
function testRandomMatchesMilesForOneMode(t)
db=fixture; db.Phi=db.Phi(:,1); db.omega=db.omega(1); db.frequencyHz=db.frequencyHz(1);
% Unit participation at the monitor: a textbook single-degree-of-freedom mount.
db.Phi(1,1)=1; db.participation=[1;0;0];
w0=0.04; f=struct('rpm',100,'rpmRange',[100 100],'order',1,'amplitudeG',0,'psd',[1 w0;20000 w0], ...
    'axis',1,'zeta',0.05,'monitor',{{1,'X'}},'marginPct',10);
r=vil.flightResponse(db,f);
miles=sqrt(pi/2*db.frequencyHz*(1/(2*0.05))*w0);
verifyEqual(t,r.outputRmsG,miles,'RelTol',0.03);
end
function testResidualFlexibilityRestoresTruncatedFRF(t)
% Grounded 30-mass chain along X: every mode is known exactly. Keep only the
% modes below 400 Hz; the residual must restore what the rest contribute.
n=30; k=1e6; m=0.01;
fr=(2:n).';                                       % X DOFs, node 1 grounded
K=sparse(3*n,3*n); M=speye(3*n)*m;
for j=1:n-1, K([j j+1],[j j+1])=K([j j+1],[j j+1])+k*[1 -1;-1 1]; end
K(1,1)=K(1,1)+k;
[V,L]=eig(full(K(fr,fr)),full(M(fr,fr))); [l,o]=sort(diag(L)); V=V(:,o);
V=V./sqrt(diag(V.'*M(fr,fr)*V)).';
Phi=zeros(3*n,n-1); Phi(fr,:)=V;
db=struct('nodes',[1:n;zeros(2,n)]*0.01,'surfaceNodes',(1:n).','fixedNodes',1, ...
    'Phi',Phi,'omega',sqrt(l)); db.frequencyHz=db.omega/(2*pi);
mats=struct('K',K,'M',M,'free',fr);
cfg=struct('rove',"hammer",'fixed',{{15,'X'}},'roving',{{{n,'X'},{8,'X'}}});
p=struct('peakForce',10,'contactDuration',1e-3,'zeta',0.02,'duration',0,'fs',0,'maxModeHz',400);
plain=vil.runSurvey(db,cfg,p); fixed=vil.runSurvey(db,cfg,p,mats);
verifyLessThan(t,nnz(plain.modeKeep),n-1);
% Residual flexibility is static: judge it well below the first mode left
% out, where that mode's own dynamics do not matter yet.
fx=min(db.frequencyHz(~plain.modeKeep)); low=plain.frequencyHz<0.5*fx;
for j=1:2
    ref=vil.calculateFRF(db,cfg.roving{j},cfg.fixed,plain.frequencyHz(low),0.02).accelerance;
    e0=norm(plain.H(j,low)-ref)/norm(ref); e1=norm(fixed.H(j,low)-ref)/norm(ref);
    verifyLessThan(t,e1,0.25*e0);
end
% Static check: the residual is the exact flexibility minus the kept modes.
f=zeros(3*n,1); f(n)=1; g=zeros(3*n,1); g(15)=1;
G=zeros(3*n); G(fr,fr)=inv(full(K(fr,fr)));
keep=plain.modeKeep;
exact=g.'*(G-Phi(:,keep)*diag(1./db.omega(keep).^2)*Phi(:,keep).')*f;
verifyEqual(t,vil.residualFlexibility(db,mats,f,g,keep),exact,'RelTol',1e-9);
end
