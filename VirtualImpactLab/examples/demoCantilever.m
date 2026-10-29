% Run from the VirtualImpactLab folder. No external dependencies.
clear; clc;
h=[0.012 0.008 0.005]; first=zeros(size(h));
for k=1:numel(h)
    [model,c]=vil.createDemoBeam(h(k)); db=vil.solveModes(model,c);
    first(k)=db.frequencyHz(1);
end
I=c.width*c.height^3/12; area=c.width*c.height;
theory=1.875104068711961^2/(2*pi*c.L^2)*sqrt(c.E*I/(c.rho*area));
disp(table(h.',first.',100*(first.'/theory-1), ...
    'VariableNames',{'Hmax_m','FirstFrequency_Hz','TheoryError_percent'}));
assert(abs(first(end)/theory-1)<0.10,'Beam frequency differs from theory by >10%%.');
assert(abs(first(end)-first(end-1))/first(end)<0.05,'Mesh is not converged within 5%%.');
% One cached modal solution, 10 hammer nodes x 3 sensor nodes.
ids=db.surfaceNodes; ids=ids(round(linspace(1,numel(ids),30)));
f=linspace(0,0.7*max(db.frequencyHz),2001); frfs=cell(10,3);
for i=1:10
    for j=1:3
        frfs{i,j}=vil.calculateFRF(db,{ids(i),'Z'},{ids(10+j),'Z'},f,0.01);
    end
end
figure; plot(f,abs(frfs{1,1}.accelerance)); xlabel('Frequency (Hz)'); ylabel('Accelerance ((m/s^2)/N)');
disp('30 FRFs calculated from one cached modal database; no solve in the FRF loop.');
