function tests=testApp
% Drives the UI through its scripting handle (no dialogs): demo part, clamp,
% solve, roving test with a dead point, flight simulation.
tests=functiontests(localfunctions);
end
function setupOnce(t)
% Run from any folder: put the app (package +vil) on the path.
t.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
end
function teardown(t)
if isfield(t.TestData,'app') && isvalid(t.TestData.app.figure), close(t.TestData.app.figure); end
end
function app=solvedDemo(t)
app=VirtualImpactLab; t.TestData.app=app;
app.demo(); app.solve();
end
function testRovingHammerWorkflow(t)
app=solvedDemo(t); s=app.state();
verifyNumElements(t,s.db.omega,12);
verifyEqual(t,s.db.frequencyHz(1),186.3,'RelTol',0.01);
% Picking snaps to the nearest free surface node.
tip=[0.15 0 0.02];
app.pick(tip,"anchor"); s=app.state();
verifyLessThan(t,norm(s.db.nodes(:,s.anchor).'-tip),0.005);
verifyFalse(t,ismember(s.anchor,s.db.fixedNodes));
app.pick([0.05 0 0.02],"roving"); app.pick([0.1 0 0.02],"roving"); app.pick([0.14 0 0.02],"roving");
app.pick([0.1 0 0.02],"roving");                 % same point twice counts once
s=app.state(); verifyNumElements(t,s.roving,3);
app.runTest(); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,s.survey.use,true(3,1));
verifyGreaterThan(t,numel(s.survey.modes.frequencyHz),0);
% The results must reach the screen, not only the state.
shown=findobj(app.figure,'Tag','modalTable').Data;
verifyEqual(t,size(shown,1),numel(s.survey.modes.frequencyHz));
% Switching a response off refits without simulating again.
app.setUse([true;true;false]); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,nnz(s.survey.use),2);
end
function testRovingAccelerometerMatchesReciprocity(t)
app=solvedDemo(t);
% Reciprocity holds for point loads; a finite tip face averages only the hammer end.
findobj(app.figure,'Tag','tipSize').Value=0;
a=[0.14 0 0.02]; b=[0.08 0 0.02];
app.pick(a,"anchor"); app.pick(b,"roving"); app.runTest();
h1=app.state().survey.H;
app.setRove("sensor");
s=app.state(); verifyEqual(t,s.rove,"sensor"); verifyEmpty(t,s.survey);
app.runTest(); s=app.state();
verifyEmpty(t,s.lastError);
% Same pair, roles swapped: the arrows flip, so both signs flip and H is equal.
verifyEqual(t,s.survey.H,h1,'RelTol',1e-9);
end
function testFlightSimulation(t)
app=solvedDemo(t);
app.showTab('flight'); app.runFlight(); s=app.state();
verifyEmpty(t,s.lastError);
verifyNumElements(t,s.flight.status,12);
end
function testFixedFaceToggle(t)
app=VirtualImpactLab; t.TestData.app=app;
app.demo(); s=app.state(); f=s.fixedFaces;
% Clicking the clamped end face again releases it.
app.pick([-0.15 0 0.01],"fixed"); s=app.state();
verifyEmpty(t,intersect(s.fixedFaces,f));
app.pick([-0.15 0 0.01],"fixed"); s=app.state();
verifyEqual(t,s.fixedFaces,f);
verifyEmpty(t,s.lastError);
end
function testFreeFreeWorkflow(t)
app=VirtualImpactLab; t.TestData.app=app;
app.demo(); app.setBoundary("free"); app.solve(); s=app.state();
verifyEmpty(t,s.lastError);
verifyEmpty(t,s.db.fixedNodes);
verifyNumElements(t,s.db.rigidBodyHz,6);
% Free-free bending is (4.730/1.875)^2 = 6.36 times the clamped frequency
% by Euler-Bernoulli; shear lowers the free-free mode by about 2 %.
verifyEqual(t,s.db.frequencyHz(1),6.36*186.3,'RelTol',0.04);
app.pick([0.15 0 0.02],"anchor"); app.pick([-0.1 0 0.02],"roving"); app.pick([0.05 0 0.02],"roving");
app.runTest(); s=app.state();
verifyEmpty(t,s.lastError);
verifyGreaterThan(t,numel(s.survey.modes.frequencyHz),0);
verifyEqual(t,findobj(app.figure,'Tag','flightRun').Enable,matlab.lang.OnOffSwitchState.off);
end
function testHammerTips(t)
app=solvedDemo(t);
% After solving, the softest tip that reaches the first three modes is chosen.
tip=findobj(app.figure,'Tag','hammerTip');
verifyEqual(t,tip.Value,'Rubber');
verifyEqual(t,tip.Items,{'Rubber','Steel'});
verifySubstring(t,findobj(app.figure,'Tag','bandInfo').Text,'of 12 modes inside');
app.setTip('Steel');
verifyEqual(t,findobj(app.figure,'Tag','advanced').Value,false);
app.pick([0.14 0 0.02],"anchor"); app.pick([0.08 0 0.02],"roving"); app.runTest(); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,s.survey.parameters.contactDuration,5e-5,'RelTol',1e-12);
% Typing a contact time opens the advanced options and makes a custom tip.
app.setContact(0.2);
verifyEqual(t,tip.Value,'Custom');
verifyTrue(t,findobj(app.figure,'Tag','advanced').Value);
end
function testMaterialPresets(t)
app=VirtualImpactLab; t.TestData.app=app;
drop=findobj(app.figure,'Tag','material');
for name=["Aero Al 7075-T6" "CFRP T300/epoxy (quasi-iso)" "AM Ti-6Al-4V (LPBF)"]
    verifyTrue(t,ismember(name,drop.Items));
end
app.demo(); drop.Value='CFRP T300/epoxy (quasi-iso)'; drop.ValueChangedFcn(drop,[]);
app.solve(); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,[s.db.config.E s.db.config.rho],[50e9 1550]);
% Same beam, stiffness/density ratio sqrt((50/1550)/(210/7850)) = 1.098 of steel.
verifyEqual(t,s.db.frequencyHz(1),186.3*sqrt((50e9/1550)/(210e9/7850)),'RelTol',0.01);
end
function testHammerAndFlightResultsAreSeparate(t)
app=solvedDemo(t);
right=app.figure.findobj('Tag','results');
names=@()string({right.Children.Title});
app.showTab('impact');
verifyTrue(t,any(contains(names(),"Hammer")));
verifyFalse(t,any(contains(names(),"Flight")));
app.pick([0.14 0 0.02],"anchor"); app.pick([0.08 0 0.02],"roving"); app.runTest();
verifyEqual(t,string(right.SelectedTab.Title),"Hammer: modal ID");
app.showTab('flight');
verifyFalse(t,any(contains(names(),"Hammer")));
app.runFlight();
verifyEqual(t,string(right.SelectedTab.Title),"Flight: response");
app.showTab('modes');
verifyEqual(t,names(),["3D model" "Verification"]);
end
function testProbesUseTheClickedPoint(t)
app=solvedDemo(t);
% Between nodes: the probe sits where clicked, not on the nearest node.
x=[0.1003 0.0021 0.02];
app.pick(x,"anchor"); s=app.state();
verifyEqual(t,s.anchorAt,x(:),'AbsTol',1e-12);
app.pick([0.05 0 0.02],"roving"); app.runTest(); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,s.survey.fixed{1},x(:),'AbsTol',1e-12);
verifyGreaterThan(t,s.survey.parameters.tipRadius,0);   % rubber tip face
end
