% Scripted workflow without the UI. Run from the VirtualImpactLab folder.
% 1) mesh convergence of the demo cantilever against beam theory
% 2) one modal solve, then 30 hammer/sensor FRFs and an impact from the cache
clear; clc;
h=[0.012 0.008 0.005]; first=zeros(size(h));
for k=1:numel(h)
    [g,c,mi]=vil.createDemoBeam(h(k)); db=vil.solveModes(g,c,MeshInfo=mi,MinModes=6);
    first(k)=db.frequencyHz(1);
end
I=c.width*c.height^3/12; area=c.width*c.height;
theory=1.875104068711961^2/(2*pi*c.L^2)*sqrt(c.E*I/(c.rho*area));
disp(table(h.',first.',100*(first.'/theory-1), ...
    'VariableNames',{'Hmax_m','FirstFrequency_Hz','TheoryError_percent'}));
assert(abs(first(end)/theory-1)<0.01,'Beam frequency differs from theory by >1%%.');

% One cached modal solution, 10 hammer nodes x 3 sensor nodes.
ids=setdiff(db.surfaceNodes,db.fixedNodes); ids=ids(round(linspace(1,numel(ids),30)));
f=linspace(0,0.7*max(db.frequencyHz),2001); frfs=cell(10,3);
tic
for i=1:10
    for j=1:3
        frfs{i,j}=vil.calculateFRF(db,{ids(i),'Z'},{ids(10+j),'Z'},f,0.01);
    end
end
fprintf('30 FRFs from one modal database in %.2f s (no eigen solve).\n',toc);

% Impact: 100 N, 0.5 ms half-sine on the free end, accelerometer on top.
tip=ids(end);
p=struct('peakForce',100,'contactDuration',5e-4,'duration',0.5,'fs',20000,'zeta',0.01);
r=vil.simulateImpact(db,{tip,'Z'},{tip,'Z'},p);
figure; tiledlayout(2,1);
nexttile; semilogy(f,abs(frfs{1,1}.accelerance)); xlabel('Frequency (Hz)'); ylabel('|Accelerance| (m/s^2/N)'); grid on
nexttile; plot(r.time,r.acceleration); xlabel('Time (s)'); ylabel('Acceleration (m/s^2)'); grid on
