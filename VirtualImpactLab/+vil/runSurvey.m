function s = runSurvey(db,cfg,p)
% Roving test: one fixed point, several roving points, one FRF per path.
% cfg.rove     "hammer" (fixed accelerometer) or "sensor" (fixed hammer)
% cfg.fixed    {node, 3-vector}
% cfg.roving   cell array of {node, 3-vector}
% cfg.fixed and roving locations are a surface node or a 3-vector point (m).
% p: peakForce, contactDuration, zeta, duration (0 = auto), fs (0 = auto),
%    maxModeHz ([] = all), maxSamples, tipRadius (m, 0 = point load).
% Signals are processed as a measurement would be: the FRF comes from the
% force and acceleration records, not from the modal formula.
arguments
    db struct
    cfg struct
    p struct
end
assert(ismember(cfg.rove,["hammer" "sensor"]),'vil:Survey','cfg.rove must be "hammer" or "sensor".');
assert(~isempty(cfg.roving),'vil:Survey','Add at least one roving point.');
assert(all(p.zeta>0),'vil:Survey','Damping must be above zero: an undamped part never stops ringing.');
if ~isfield(p,'maxSamples'), p.maxSamples=2e6; end
if ~isfield(p,'tipRadius'), p.tipRadius=0; end
z=vil.damping(db,p.zeta);
keep=true(size(db.omega));
if isfield(p,'maxModeHz') && ~isempty(p.maxModeHz) && p.maxModeHz>0
    keep=db.frequencyHz<=p.maxModeHz;
    assert(any(keep),'vil:Cutoff','No modes below the %.4g Hz cutoff.',p.maxModeHz);
end
w=db.omega(keep); z=z(keep); fTop=max(w)/(2*pi);
% A hit excites up to about 1.2/Tc. A mode above that never shows in the FRF,
% so a test whose band holds no mode cannot identify anything: say why now.
excitedHz=1.2/p.contactDuration;
if min(w)/(2*pi)>excitedHz
    error('vil:BandBelowModes',['The first mode (%.4g Hz) is above the %.4g Hz this %.3g ms hit excites. ' ...
        'Use a harder hammer tip (steel) or a contact time below %.3g ms.'], ...
        min(w)/(2*pi),excitedHz,1e3*p.contactDuration,1e3*1.2/(min(w)/(2*pi)));
end

if p.fs==0, p.fs=max(1000*ceil(2.56*fTop/1000),ceil(25/p.contactDuration)); end
assert(p.fs>2*fTop,'vil:SampleRate', ...
    'Sample rate must exceed twice the highest retained mode (%.4g Hz needs fs > %.4g Hz).',fTop,2*fTop);
assert(p.fs*p.contactDuration>=20,'vil:ContactSamples','Resolve contact with at least 20 samples (fs * contact duration >= 20).');
sigma=min(z.*w);                     % slowest decay rate
if p.duration==0, p.duration=log(1e3)/sigma; end
p.duration=max(min(p.duration,(p.maxSamples-1)/p.fs),p.contactDuration);
% A record that has not rung down gets an exponential window, as on a real
% analyser. It adds the same known decay 1/tau to every mode.
tau=Inf;
if exp(-sigma*p.duration)>1.01e-3, tau=p.duration/log(1e3); end

nr=numel(cfg.roving); W=zeros(nr,numel(w));
% The tip face spreads the force; the accelerometer is a point.
rFixed=p.tipRadius*(cfg.rove=="sensor"); rRove=p.tipRadius*(cfg.rove=="hammer");
fixedAmp=vil.mapProbePoints(db,cfg.fixed{:},Radius=rFixed); fixedAmp=fixedAmp(keep);
for k=1:nr
    r=vil.mapProbePoints(db,cfg.roving{k}{:},Radius=rRove);
    W(k,:)=r(keep).*fixedAmp;
end
[t,F,a]=vil.modalPropagate(w,z,W,p);

win=exp(-t/tau);
N=numel(t); nb=floor(N/2)+1; fAxis=(0:nb-1)*p.fs/N;
Ff=fft(F.*win); Af=fft(a.*win,[],2);
% Usable band: the half-sine is down 15 dB at 1.2/Tc, the usual analyser limit.
fBand=min([1.2/p.contactDuration 1.05*fTop p.fs/2.56]);
idx=find(fAxis>0 & fAxis<=fBand);
% The DFT force is the sampled pulse; the integrator saw its piecewise-linear
% interpolation, whose spectrum is lower by sinc^2.
x=fAxis(idx)/p.fs; hold1=(sin(pi*x)./(pi*x)).^2;
H=Af(:,idx)./(Ff(idx).*hold1);       % H1 = Gxf/Gff; one hit, no noise, so X/F
s=struct('rove',cfg.rove,'fixed',{cfg.fixed},'roving',{cfg.roving},'parameters',p, ...
    'time',t,'force',F,'acceleration',a,'frequencyHz',fAxis(idx),'H',H, ...
    'forceSpectrum',abs(Ff(idx)),'tau',tau,'bandHz',fBand,'modeKeep',keep,'W',W);
end
