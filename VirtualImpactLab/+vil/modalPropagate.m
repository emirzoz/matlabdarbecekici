function [t,F,a,x,v] = modalPropagate(omega,zeta,W,p)
% Half-sine impact through uncoupled modes: exact state transition for a
% piecewise-linear sampled force (FOH). W is paths x modes: the product of the
% hammer and sensor modal amplitudes of each path, so every hammer/sensor pair
% shares one modal integration. Displacement and velocity only if requested.
dt=1/p.fs; t=(0:floor(p.duration*p.fs))*dt;
F=zeros(size(t)); active=t<=p.contactDuration;
F(active)=p.peakForce*sin(pi*t(active)/p.contactDuration);
w=omega(:); z=zeta(:); nm=numel(w);
E=zeros(nm,2,4);
for r=1:nm
    A=[0 1;-w(r)^2 -2*z(r)*w(r)]; B=[0;1];
    Er=expm([A B zeros(2,1);zeros(1,3) 1;zeros(1,4)]*dt);
    E(r,:,:)=Er(1:2,:);
end
N=numel(t); P=size(W,1); wantState=nargout>3;
a=zeros(P,N); if wantState, x=zeros(P,N); v=zeros(P,N); end
dF=[diff(F) 0]/dt; s1=zeros(nm,1); s2=s1;
k1=-w.^2; k2=-2*z.*w;
for k=1:N
    a(:,k)=W*(k1.*s1+k2.*s2+F(k));
    if wantState, x(:,k)=W*s1; v(:,k)=W*s2; end
    n1=E(:,1,1).*s1+E(:,1,2).*s2+E(:,1,3)*F(k)+E(:,1,4)*dF(k);
    s2=E(:,2,1).*s1+E(:,2,2).*s2+E(:,2,3)*F(k)+E(:,2,4)*dF(k);
    s1=n1;
end
end
