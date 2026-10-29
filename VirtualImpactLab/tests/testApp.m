function tests=testApp
% Drives the UI through its scripting handle (no dialogs): demo part,
% clamp, solve, pick hammer/sensor on the model, run two impacts.
tests=functiontests(localfunctions);
end
function setupOnce(t)
% Run from any folder: put the app (package +vil) on the path.
t.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
end
function teardown(t)
if isfield(t.TestData,'app') && isvalid(t.TestData.app.figure), close(t.TestData.app.figure); end
end
function testDemoWorkflow(t)
app=VirtualImpactLab; t.TestData.app=app;
app.demo(); s=app.state();
verifyNotEmpty(t,s.fixedFaces);
app.solve(); s=app.state();
verifyNumElements(t,s.db.omega,12);
verifyEqual(t,s.db.frequencyHz(1),186.3,'RelTol',0.01);
% Picking snaps to the nearest free surface node.
tip=[0.15 0 0.02];
app.pick(tip,"hammer"); s=app.state();
verifyLessThan(t,norm(s.db.nodes(:,s.hammer).'-tip),0.005);
verifyFalse(t,ismember(s.hammer,s.db.fixedNodes));
app.pick([0 0.01 0.01],"sensor");
app.runTest(); app.runTest(); s=app.state();
verifyEmpty(t,s.lastError);
verifyNumElements(t,s.tests,2);
a=s.tests{1}.response.acceleration;
verifyGreaterThan(t,max(abs(a)),0);
verifyEqual(t,s.tests{2}.response.acceleration,a,'AbsTol',1e-12);
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
