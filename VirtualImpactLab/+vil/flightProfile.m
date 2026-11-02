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
% Rotax 912 ULS (100 hp flat-four, 4-stroke) through its 2.43:1 reduction
% gearbox to a 3-blade propeller. Speeds are PROPELLER rpm: idle 1400,
% cruise ~5000, max continuous 5500, take-off 5800 engine rpm / 2.43.
% Engine tones are orders of the propeller: crank 1x = 2.43, firing (two
% firings per crank revolution) = 4.86.
g912=2.43;
list(end+1)=struct('name',"Rotax 912 ULS + 3-blade prop",'data', ...
    mk(round(5000/g912),round(1400/g912),round(5800/g912), ...
    {"Propeller 1×";"Blade pass (3 blades)";"2× blade pass";"Crankshaft 1× (2.43:1 gearbox)";"Firing (2× crank)";"2× firing"}, ...
    [1;3;6;g912;2*g912;4*g912],[0.5;2;1;0.3;1.5;0.5]));
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
