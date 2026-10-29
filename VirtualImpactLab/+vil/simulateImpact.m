function out = simulateImpact(db,hammer,sensor,p)
% Exact linear state transition with piecewise-linear sampled force (FOH).
validateattributes(p.peakForce,{'numeric'},{'scalar','positive','finite'});
validateattributes(p.fs,{'numeric'},{'scalar','positive','finite'});
validateattributes(p.contactDuration,{'numeric'},{'scalar','positive','finite'});
validateattributes(p.duration,{'numeric'},{'scalar','>=',p.contactDuration,'finite'});
assert(p.fs*p.contactDuration>=20,'Resolve contact with at least 20 samples.');
assert(p.fs>=10*max(db.frequencyHz),'Use fs >= 10 times the highest retained modal frequency.');
z=vil.damping(db,p.zeta); dt=1/p.fs; t=(0:floor(p.duration*p.fs))*dt;
F=zeros(size(t)); active=t<=p.contactDuration;
F(active)=p.peakForce*sin(pi*t(active)/p.contactDuration);
b=vil.mapProbePoints(db,hammer{1},hammer{2});
c=vil.mapProbePoints(db,sensor{1},sensor{2});
x=zeros(size(t)); v=x; a=x;
for r=1:numel(db.omega)
    w=db.omega(r); A=[0 1;-w*w -2*z(r)*w]; B=[0;b(r)];
    % Augment by force and force slope, then propagate each linear segment.
    E=expm([A B zeros(2,1);zeros(1,3) 1;zeros(1,4)]*dt);
    state=[0;0];
    for k=1:numel(t)
        x(k)=x(k)+c(r)*state(1); v(k)=v(k)+c(r)*state(2);
        a(k)=a(k)+c(r)*(-w*w*state(1)-2*z(r)*w*state(2)+b(r)*F(k));
        if k<numel(t)
            next=E*[state;F(k);(F(k+1)-F(k))/dt]; state=next(1:2);
        end
    end
end
N=numel(t); idx=1:floor(N/2)+1; spectrum=abs(fft(a))/N;
spectrum=spectrum(idx); if rem(N,2)==0, spectrum(2:end-1)=2*spectrum(2:end-1); else, spectrum(2:end)=2*spectrum(2:end); end
out=struct('time',t,'force',F,'displacement',x,'velocity',v, ...
    'acceleration',a,'spectrumHz',(idx-1)*p.fs/N,'accelerationSpectrum',spectrum, ...
    'parameters',p,'hammer',{hammer},'sensor',{sensor});
end
