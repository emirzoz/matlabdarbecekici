function out = simulateImpact(db,hammer,sensor,p)
% Exact linear state transition with piecewise-linear sampled force (FOH).
% hammer/sensor = {nodeID, direction}. Half-sine pulse of peakForce over
% contactDuration. All modes are propagated together (vil.modalPropagate).
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
b=vil.mapProbePoints(db,hammer{1},hammer{2});
c=vil.mapProbePoints(db,sensor{1},sensor{2});
[t,F,a,x,v]=vil.modalPropagate(db.omega,z,b.*c,p);
N=numel(t);
idx=1:floor(N/2)+1; spectrum=abs(fft(a))/N;
spectrum=spectrum(idx); if rem(N,2)==0, spectrum(2:end-1)=2*spectrum(2:end-1); else, spectrum(2:end)=2*spectrum(2:end); end
out=struct('time',t,'force',F,'displacement',x,'velocity',v, ...
    'acceleration',a,'spectrumHz',(idx-1)*p.fs/N,'accelerationSpectrum',spectrum, ...
    'parameters',p,'hammer',{hammer},'sensor',{sensor});
end
