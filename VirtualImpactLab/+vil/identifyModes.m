function id = identifyModes(f,H,tau,opts)
% Natural frequencies, damping and modal constants from accelerance FRFs
% (paths x lines) that share poles. Poles: least-squares rational fraction
% (LSCF) over a range of model orders, keeping only poles that repeat between
% orders. Residues: least-squares fit of every FRF to those poles.
% tau is the exponential window time constant (Inf = none); the decay it added
% is removed from the reported damping.
arguments
    f (1,:) double
    H double
    tau (1,1) double = Inf
    opts.MinPeak (1,1) double = 1e-3
end
peak=sum(abs(H),1);
lines=fitLines(f);
fk=f(lines); Hk=H(:,lines);
scale=sqrt(mean(abs(Hk).^2,2)); keep=scale>0; Hk=Hk(keep,:)./scale(keep);
Ts=1/(2*max(f)*1.05);
nPeaks=nnz(peak(2:end-1)>peak(1:end-2) & peak(2:end-1)>peak(3:end) & peak(2:end-1)>opts.MinPeak*max(peak));
top=min(2*nPeaks+30,90); orders=max(4,top-16):2:top;
P=cell(numel(orders),1);
for k=1:numel(orders)
    P{k}=lscfPoles(fk,Hk,Ts,orders(k));
end
lambda=P{end};
hits=zeros(size(lambda));
for k=1:numel(orders)-1
    q=P{k}; if isempty(q), continue, end
    for j=1:numel(lambda)
        dw=abs(imag(q)-imag(lambda(j)))/imag(lambda(j));
        ds=abs(real(q)-real(lambda(j)))./abs(real(lambda(j)));
        hits(j)=hits(j)+any(dw<2e-3 & ds<0.05);
    end
end
lambda=dropDuplicates(lambda(hits>=3));
assert(~isempty(lambda),'vil:NoModesFound','No stable modes found in this band.');
r=residues(f,H,lambda);
% Modal constant A = phi_sensor*phi_hammer of each path.
A=2i*imag(lambda).'.*r;                      % paths x poles
strength=max(abs(A),[],1).'.*abs(lambda)./(-2*real(lambda));
strong=strength>=opts.MinPeak*max(strength);
lambda=lambda(strong);
[r,c]=residues(f,H,lambda);
A=2i*imag(lambda).'.*r;
sigma=-real(lambda)-1/tau; wd=imag(lambda);
wn=sqrt(sigma.^2+wd.^2);
id=struct('frequencyHz',wn/(2*pi),'zeta',sigma./wn,'A',real(A), ...
    'fit',synth(f,lambda,r,c));
end

function k=fitLines(f)
% Thin long records to lines 0.1 % apart: enough points on each resonance.
if numel(f)<=4000, k=1:numel(f); return, end
df=f(2)-f(1); list=zeros(1,numel(f)); g=f(1); n=0;
while g<=f(end)
    n=n+1; list(n)=g; g=g+max(df,1e-3*g);
end
k=unique(min(max(round((list(1:n)-f(1))/df)+1,1),numel(f)));
end

function lam=lscfPoles(f,H,Ts,n)
Om=exp(1i*2*pi*f(:)*Ts);
X=Om.^(0:n);
R=real(X'*X); M=zeros(n+1);
for o=1:size(H,1)
    Y=-H(o,:).'.*X;
    S=real(X'*Y); T=real(Y'*Y);
    M=M+T-S'*(R\S);
end
% Above the true order the system is rank deficient: that is expected here.
alpha=[lsqminnorm(M(1:n,1:n),-M(1:n,n+1));1];
z=roots(flip(alpha));
z=z(abs(z)<1 & imag(z)>0);
lam=log(z)/Ts;
fp=abs(lam)/(2*pi); zp=-real(lam)./abs(lam);
lam=lam(fp>=f(1) & fp<=f(end) & zp>0 & zp<0.3);
end

function lam=dropDuplicates(lam)
[~,o]=sort(imag(lam)); lam=lam(o);
if numel(lam)<2, return, end
lam=lam([true; diff(imag(lam))./imag(lam(2:end))>5e-4]);
end

function [r,c]=residues(f,H,lambda)
% H_acc = -w^2*(sum r/(jw-l) + conj(r)/(jw-conj(l)) + c); c stands in for the
% modes above the band. One real design matrix serves every path.
w=2*pi*f(:); s=1i*w; np=numel(lambda);
B1=-w.^2./(s-lambda.'); B2=-w.^2./(s-conj(lambda.'));
D=[B1+B2, 1i*(B1-B2), -w.^2+0i];
lines=fitLines(f);
D=D(lines,:); Y=H(:,lines).';
sc=max(abs(D),[],1); D=D./sc;
x=[real(D);imag(D)]\[real(Y);imag(Y)];
x=x./sc.';
r=(x(1:np,:)+1i*x(np+1:2*np,:)).'; c=x(end,:).';
end

function Hf=synth(f,lambda,r,c)
w=2*pi*f(:); s=1i*w;
B1=-w.^2./(s-lambda.'); B2=-w.^2./(s-conj(lambda.'));
Hf=(B1*r.'+B2*r'+(-w.^2)*c.').';
end
