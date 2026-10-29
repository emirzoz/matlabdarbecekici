function out = simulateImpact(db,hammer,sensor,p)
% Exact linear state transition with piecewise-linear sampled force (FOH).
% hammer/sensor = {nodeID, direction}. Half-sine pulse of peakForce over
% contactDuration. All modes are propagated together, one time step at a time.
validateattributes(p.peakForce,{'numeric'},{'scalar','positive','finite'});
validateattributes(p.fs,{'numeric'},{'scalar','positive','finite'});
validateattributes(p.contactDuration,{'numeric'},{'scalar','positive','finite'});
validateattributes(p.duration,{'numeric'},{'scalar','>=',p.contactDuration,'finite'});
assert(p.fs*p.contactDuration>=20,'vil:ContactSamples','Resolve contact with at least 20 samples (fs * contact duration >= 20).');
z=vil.damping(db,p.zeta);
% Optional modal cutoff: keep modes up to maxModeHz (default: all modes).
if isfield(p,'maxModeHz') && ~isempty(p.maxModeHz)
    keep=db.frequencyHz<=p.maxModeHz;
    assert(any(keep),'vil:Cutoff','No modes below the %.4g Hz cutoff.',p.maxModeHz);
    db.Phi=db.Phi(:,keep); db.omega=db.omega(keep); db.frequencyHz=db.frequencyHz(keep); z=z(keep);
end
% The transition is exact for piecewise-linear force at any step, so fs only
% needs to sample the retained response without aliasing.
assert(p.fs>2*max(db.frequencyHz),'vil:SampleRate', ...
    'Sample rate must exceed twice the highest retained mode (%.4g Hz needs fs > %.4g Hz).', ...
    max(db.frequencyHz),2*max(db.frequencyHz));
dt=1/p.fs; t=(0:floor(p.duration*p.fs))*dt;
F=zeros(size(t)); active=t<=p.contactDuration;
F(active)=p.peakForce*sin(pi*t(active)/p.contactDuration);
b=vil.mapProbePoints(db,hammer{1},hammer{2}).';
c=vil.mapProbePoints(db,sensor{1},sensor{2}).';
w=db.omega(:); nm=numel(w);
% Per-mode transition of the state augmented by force and force slope.
E=zeros(nm,2,4);
for r=1:nm
    A=[0 1;-w(r)^2 -2*z(r)*w(r)]; B=[0;b(r)];
    Er=expm([A B zeros(2,1);zeros(1,3) 1;zeros(1,4)]*dt);
    E(r,:,:)=Er(1:2,:);
end
N=numel(t); q=zeros(nm,N); qd=zeros(nm,N);
dF=[diff(F) 0]/dt; s1=zeros(nm,1); s2=s1;
for k=1:N-1
    n1=E(:,1,1).*s1+E(:,1,2).*s2+E(:,1,3)*F(k)+E(:,1,4)*dF(k);
    n2=E(:,2,1).*s1+E(:,2,2).*s2+E(:,2,3)*F(k)+E(:,2,4)*dF(k);
    s1=n1; s2=n2; q(:,k+1)=s1; qd(:,k+1)=s2;
end
qdd=-(w.^2).*q-2*(z.*w).*qd+b*F;
x=c.'*q; v=c.'*qd; a=c.'*qdd;
idx=1:floor(N/2)+1; spectrum=abs(fft(a))/N;
spectrum=spectrum(idx); if rem(N,2)==0, spectrum(2:end-1)=2*spectrum(2:end-1); else, spectrum(2:end)=2*spectrum(2:end); end
out=struct('time',t,'force',F,'displacement',x,'velocity',v, ...
    'acceleration',a,'spectrumHz',(idx-1)*p.fs/N,'accelerationSpectrum',spectrum, ...
    'parameters',p,'hammer',{hammer},'sensor',{sensor});
end
