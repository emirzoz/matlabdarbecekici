function [p,names] = flightProfile(name)
% Aircraft vibration presets. Tone frequencies are physics: order x shaft speed
% (blade-pass order = number of blades). The C-130 class speed gives the
% 68 Hz blade-pass frequency quoted with MIL-STD-810 Method 514.
% AMPLITUDES AND PSD VALUES ARE EXAMPLES, NOT STANDARD LEVELS: replace them
% with measured data or the levels of the specification that applies.
exampleRandom=[10 0.001; 40 0.01; 500 0.01; 2000 0.0025];
mk=@(rpm,lo,hi,src,ord,amp) struct('rpm',rpm,'rpmRange',[lo hi], ...
    'source',{src},'order',ord,'amplitudeG',amp,'psd',exampleRandom);
list=struct('name',{},'data',{});
list(end+1)=struct('name',"2-blade propeller (piston)",'data', ...
    mk(4000,1500,5500,{"Shaft";"Blade pass";"2× blade pass";"3× blade pass"},[1;2;4;6],[0.5;2;1;0.5]));
list(end+1)=struct('name',"3-blade propeller (piston)",'data', ...
    mk(2400,1200,2700,{"Shaft";"Blade pass";"2× blade pass";"3× blade pass"},[1;3;6;9],[0.5;2;1;0.5]));
list(end+1)=struct('name',"4-blade turboprop (C-130 class)",'data', ...
    mk(1020,1000,1040,{"Shaft";"Blade pass";"2× blade pass";"3× blade pass"},[1;4;8;12],[0.2;2;1;0.5]));
list(end+1)=struct('name',"Turbofan",'data', ...
    mk(5000,2000,6000,{"Fan shaft";"2× fan shaft"},[1;2],[1;0.3]));
names=[list.name];
if nargin==0, p=[]; return, end
k=find(names==string(name),1);
assert(~isempty(k),'vil:Profile','Unknown aircraft profile %s.',name);
p=list(k).data;
end
