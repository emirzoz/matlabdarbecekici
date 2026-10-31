function r = flightResponse(db,f)
% Steady response of the part when its clamp shakes with the aircraft.
% f: rpm, rpmRange [lo hi], order, amplitudeG (tones), psd [Hz g^2/Hz],
%    axis (1-3, clamp motion), zeta, monitor {node, 3-vector}, marginPct.
% With relative coordinates the clamp acceleration a loads each mode as
%    q'' + 2 z w q' + w^2 q = -Gamma a,   Gamma = Phi'*M*r,
% so the absolute acceleration at the monitor per unit a is T(f):
assert(isfield(db,'participation'),'vil:OldProject', ...
    'This project predates flight simulation: solve the modes again.');
assert(~isfield(db,'fixedNodes') || ~isempty(db.fixedNodes),'vil:FreeFree', ...
    'Flight shakes the part through its clamp: solve with clamped faces, not free-free.');
assert(all(f.zeta>0),'vil:Flight','Damping must be above zero.');
assert(f.rpm>0 && f.rpmRange(1)>0 && f.rpmRange(2)>=f.rpmRange(1),'vil:Flight','Check the RPM values.');
z=vil.damping(db,f.zeta); wn=db.omega(:); fn=db.frequencyHz(:); nm=numel(wn);
gamma=db.participation(f.axis,:).';
phi=vil.mapProbePoints(db,f.monitor{:}).';
T=@(x)vil.baseTransmissibility(db,f.axis,f.monitor,x,z);

order=f.order(:); amp=f.amplitudeG(:);
tones=order*f.rpm/60;
out=amp.*abs(T(tones));
% Worst-case phasing: all tones peak together.
peakBase=sum(amp); peakResp=sum(out);

rpms=linspace(f.rpmRange(1),f.rpmRange(2),600).';
sweep=zeros(size(rpms));
for k=1:numel(rpms), sweep(k)=sum(amp.*abs(T(order*rpms(k)/60))); end

% Grid fine enough to integrate each resonance.
fLo=max(1,0.2*min([fn;tones;f.psd(1,1)])); fHi=max([fn;tones;f.psd(end,1)]);
grid=[logspace(log10(fLo),log10(fHi),1500) reshape(fn*(1+(-6:0.25:6)*mean(z)),1,[])];
grid=unique(grid(grid>0)); Tg=T(grid);
input=interpPsd(f.psd,grid);
output=abs(Tg).^2.*input;
inRms=sqrt(trapz(grid,input)); outRms=sqrt(trapz(grid,output));

% Per-mode verdict. A mode counts as excited if at resonance it adds at least
% 10 % of the clamp motion at the monitor.
gain=abs(phi.*gamma)./(2*z);
excited=gain>=0.1;
effMass=100*gamma.^2/db.totalMass;
nearest=nan(nm,1); marginPct=nan(nm,1); crossRpm=nan(nm,1); crossG=nan(nm,1); crossName=strings(nm,1);
status=strings(nm,1);
for k=1:nm
    [m,i]=min(abs(tones-fn(k))/fn(k));
    nearest(k)=tones(i); marginPct(k)=100*m;
    c=60*fn(k)./order;
    in=c>=f.rpmRange(1) & c<=f.rpmRange(2);
    if any(in)
        lvl=amp.*in*abs(T(fn(k)));
        [crossG(k),j]=max(lvl); crossRpm(k)=c(j); crossName(k)=string(order(j))+"×";
    end
    if ~excited(k), status(k)="Not excited";
    elseif marginPct(k)<=f.marginPct, status(k)="RESONANCE at cruise";
    elseif ~isnan(crossRpm(k)), status(k)="Crossed in RPM range";
    else, status(k)="Clear";
    end
end
outsideModes=max(tones)>0.8*max(fn);

% Steady time history at cruise, tones in phase at t = 0.
active=amp>0;
if ~any(active), active=true(size(amp)); end
fLow=min(tones(active)); fHigh=max(tones(active));
t=linspace(0,8/fLow,max(2000,ceil(320*fHigh/fLow)));
Tt=T(tones);
base=sum(amp.*cos(2*pi*tones*t),1);
resp=sum(amp.*abs(Tt).*cos(2*pi*tones*t+angle(Tt)),1);

r=struct('config',f,'toneHz',tones,'toneOutG',out,'peakBaseG',peakBase,'peakResponseG',peakResp, ...
    'rpmSweep',rpms,'sweepG',sweep,'frequencyHz',grid,'T',Tg,'inputPsd',input,'outputPsd',output, ...
    'inputRmsG',inRms,'outputRmsG',outRms,'naturalHz',fn,'effectiveMassPct',effMass,'gain',gain, ...
    'excited',excited,'nearestToneHz',nearest,'marginPct',marginPct,'crossingRpm',crossRpm, ...
    'crossingG',crossG,'crossingOrder',crossName,'status',status,'time',t,'baseG',base,'responseG',resp, ...
    'tonesAboveModes',outsideModes);
end


function y=interpPsd(psd,x)
% Straight lines on log-log axes between breakpoints, zero outside.
y=zeros(size(x)); in=x>=psd(1,1) & x<=psd(end,1);
y(in)=exp(interp1(log(psd(:,1)),log(psd(:,2)),log(x(in))));
end
