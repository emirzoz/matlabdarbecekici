function tests=testAppPayload
% Drives the payload, plane-support, mesh-import, sweep and project features
% through the app's scripting handle (no dialogs), on the demo cantilever.
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
end
function teardown(t)
if isfield(t.TestData,'app') && isvalid(t.TestData.app.figure), close(t.TestData.app.figure); end
end
function app=demo(t)
app=VirtualImpactLab; t.TestData.app=app; app.demo();
end

function testPayloadOffMatchesFaceClamp(t)
% Default: payload off, face clamp. Same result as the previous version.
app=demo(t); app.solve(); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,s.db.frequencyHz(1),186.3,'RelTol',0.01);
verifyEqual(t,s.db.payloadMass,0); verifyEqual(t,s.db.structureMass,s.db.totalMass);
end

function testPlaneSupportAndPayloadWorkflow(t)
app=demo(t); s=app.state(); faceDb=[];
app.solve(); faceDb=app.state().db;
% Support by plane X = -150 mm: the same nodes as the clamped end face.
app.setSupport(struct('method',"plane",'axis',1,'positionMm',-150,'toleranceMm',0.001));
s=app.state(); verifyEmpty(t,s.db);                       % modes retired
verifyEqual(t,sort(s.support.nodes(:)),sort(faceDb.fixedNodes(:)));
verifyEqual(t,findobj(app.figure,'Tag','sweepRun').Enable,matlab.lang.OnOffSwitchState.on);
info=findobj(app.figure,'Tag','supportInfo').Text;
verifySubstring(t,info,sprintf('%d nodes clamped',numel(faceDb.fixedNodes)));
% 0.5 kg payload on the free end plane.
app.setPayload(struct('enabled',true,'massKg',0.5,'method',"plane",'axis',1,'positionMm',150,'toleranceMm',0.001));
s=app.state(); verifyNotEmpty(t,s.payload.nodes);
verifyNotEmpty(t,findobj(app.figure,'Tag','payloadMass'));     % drawn in 3D
app.solve(); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,s.db.payloadMass,0.5);
verifyEqual(t,s.db.totalMass,faceDb.totalMass+0.5,'RelTol',1e-12);
verifyLessThan(t,s.db.frequencyHz(1),faceDb.frequencyHz(1));
verifySubstring(t,findobj(app.figure,'Tag','solveInfo').Text,'payload 0.5 kg');
% Flight and hammer tests run on the payload database.
app.showTab('flight'); app.runFlight(); s=app.state(); verifyEmpty(t,s.lastError);
verifyEqual(t,s.flight.effectiveMassPct,100*s.db.participation(3,:).'.^2/s.db.totalMass,'RelTol',1e-12);
app.pick([0.14 0 0.02],"anchor"); app.pick([0.05 0 0.02],"roving"); app.runTest();
verifyEmpty(t,app.state().lastError);
% Changing the mass retires the solution.
app.setPayload(struct('massKg',1)); verifyEmpty(t,app.state().db);
end

function testPayloadOnSupportIsRefused(t)
app=demo(t);
app.setPayload(struct('enabled',true,'massKg',0.5,'method',"faces",'faces',app.state().fixedFaces));
verifySubstring(t,findobj(app.figure,'Tag','payloadInfo').Text,'support nodes');
app.solve(); s=app.state();
verifyEmpty(t,s.db);                                       % alert, no solve
end

function testEmptyPlaneHasClearMessage(t)
app=demo(t);
app.setSupport(struct('method',"plane",'axis',3,'positionMm',80,'toleranceMm',0.05));
txt=findobj(app.figure,'Tag','supportInfo').Text;
verifySubstring(t,txt,'No mesh node lies within');
verifySubstring(t,txt,'The model spans Z');
verifyEqual(t,findobj(app.figure,'Tag','sweepRun').Enable,matlab.lang.OnOffSwitchState.off);
end

function testMaterialEditRetiresModes(t)
app=demo(t); app.solve();
f=findobj(app.figure,'Tag','material');
verifyNotEmpty(t,app.state().db);
app.setMaterial('AM AlSi10Mg (LPBF)'); verifyEmpty(t,app.state().db);
verifyEqual(t,f.Value,'AM AlSi10Mg (LPBF)');
end

function testSaveLoadRestoresSettings(t)
app=demo(t);
app.setSupport(struct('method',"plane",'axis',1,'positionMm',-150,'toleranceMm',0.001));
app.setPayload(struct('enabled',true,'massKg',0.75,'method',"plane",'axis',1,'positionMm',150,'toleranceMm',0.001));
app.setMaterial('Aero Al 7075-T6');
app.solve(); s1=app.state();
f=[tempname '.mat']; cleanup=onCleanup(@()delete(f));
app.saveProject(f);
close(app.figure);
app=VirtualImpactLab; t.TestData.app=app;
app.loadProject(f); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,s.origin,"loaded");
verifyEqual(t,s.db.frequencyHz,s1.db.frequencyHz);
verifyEqual(t,s.support.method,"plane"); verifyEqual(t,s.support.positionMm,-150);
verifyEqual(t,sort(s.support.nodes(:)),sort(s1.db.fixedNodes(:)));
verifyTrue(t,s.payload.enabled); verifyEqual(t,s.payload.massKg,0.75);
verifyEqual(t,s.payload.positionMm,150); verifyEqual(t,s.payload.nodes(:),s1.db.payload.nodes(:));
verifyEqual(t,findobj(app.figure,'Tag','material').Value,'Aero Al 7075-T6');
verifyTrue(t,findobj(app.figure,'Tag','payloadOn').Value);
verifyEqual(t,findobj(app.figure,'Tag','payloadKg').Value,0.75);
verifyNotEmpty(t,findobj(app.figure,'Tag','payloadMass'));
verifyNotEmpty(t,findobj(app.figure,'Tag','supportNodes'));
verifySubstring(t,findobj(app.figure,'Tag','solveInfo').Text,'LOADED');
% Re-solve on the stored mesh: same answer, shown against the loaded one.
app.solve(); s=app.state();
verifyEmpty(t,s.lastError); verifyEqual(t,s.origin,"solved");
verifyEqual(t,s.db.frequencyHz,s1.db.frequencyHz,'RelTol',1e-9);
verifySubstring(t,findobj(app.figure,'Tag','solveInfo').Text,'New vs loaded');
verifyTrue(t,ismember("Loaded (Hz)",string(findobj(app.figure,'Tag','modeTable').ColumnName)));
end

function testImportMeshAndSweep(t)
[g,~,~]=vil.createDemoBeam(0.01);
nodes=1e3*g.Mesh.Nodes.'; elements=g.Mesh.Elements.';
f=[tempname '.mat']; cleanup=onCleanup(@()delete(f)); save(f,'nodes','elements');
app=VirtualImpactLab; t.TestData.app=app;
app.importMesh(f,"mm"); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,s.meshInfo.numNodes,size(nodes,1));
verifyEqual(t,s.info.scaleApplied,1e-3);
app.setMaterial('Structural steel');
app.setSupport(struct('method',"plane",'axis',1,'positionMm',-150,'toleranceMm',0.001));
app.setPayload(struct('enabled',false,'method',"plane",'axis',1,'positionMm',150,'toleranceMm',0.001));
app.runSweep([0 0.5]); s=app.state();
verifyEmpty(t,s.lastError);
verifyEqual(t,height(s.sweep.table),2);
verifyGreaterThan(t,s.sweep.table.f1_Hz(1),s.sweep.table.f1_Hz(2));
verifyEqual(t,s.sweep.table.f1_Hz(1),186.3,'RelTol',0.01);
csv=[tempname '.csv']; c2=onCleanup(@()delete(csv));
app.exportSweep(csv); T=readtable(csv); verifyEqual(t,height(T),2);
end

function testAdvancedModeToggle(t)
% Classic screens by default; the Advanced mode button shows the tet-mesh,
% plane-support, payload, sweep and compare controls; scripted use of an
% advanced feature turns it on.
app=VirtualImpactLab; t.TestData.app=app;
vis=@(tag)findobj(app.figure,'Tag',tag).Parent.Visible;
right=findobj(app.figure,'Tag','results');
verifyFalse(t,app.state().advanced);
verifyEqual(t,vis('importModel'),matlab.lang.OnOffSwitchState.on);
verifyEqual(t,vis('payloadOn'),matlab.lang.OnOffSwitchState.off);
verifyEqual(t,vis('compareRun'),matlab.lang.OnOffSwitchState.off);
verifyEqual(t,findobj(app.figure,'Tag','demoRadome').Visible,matlab.lang.OnOffSwitchState.on);
app.showTab('project'); verifyFalse(t,any(strcmp({right.Children.Title},'Compare projects')));
b=findobj(app.figure,'Tag','advancedMode'); b.Value=true; b.ValueChangedFcn(b,[]);
verifyTrue(t,app.state().advanced);
verifyEqual(t,vis('importModel'),matlab.lang.OnOffSwitchState.on);
verifyEqual(t,vis('payloadOn'),matlab.lang.OnOffSwitchState.on);
verifyEqual(t,vis('compareRun'),matlab.lang.OnOffSwitchState.on);
verifyTrue(t,any(strcmp({right.Children.Title},'Compare projects')));
app.setAdvanced(false); app.demo();
app.setPayload(struct('enabled',true,'massKg',0.5,'method',"plane",'axis',1,'positionMm',150,'toleranceMm',0.001));
verifyTrue(t,app.state().advanced);
% Radome -> cantilever goes back to a solid model.
app.demoRadome(); verifyEqual(t,app.state().section,"shell");
app.demo(); verifyEqual(t,app.state().section,"solid");
end
