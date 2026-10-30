classdef AppGestureTest < matlab.uitest.TestCase
    % Real UI gestures: press the pick buttons, then click on the 3D model.
    properties
        App
    end
    methods (TestClassSetup)
        function addAppToPath(tc)
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
        end
    end
    methods (TestMethodSetup)
        function launch(tc)
            tc.App = VirtualImpactLab;
            tc.addTeardown(@close,tc.App.figure);
            tc.App.demo();
        end
    end
    methods (Test)
        function clickTogglesFixedFace(tc)
            s = tc.App.state(); before = s.fixedFaces;
            tc.App.showTab('solve');
            tc.press(tc.byTag('pickFixed'));
            tc.press(tc.modelAxes(),[0.15 0 0.02]);        % free end, top edge region
            s = tc.App.state();
            tc.verifyNumElements(s.fixedFaces,numel(before)+1);
            tc.verifyEmpty(s.lastError);
        end
        function dragOnModelRotatesOnly(tc)
            % Regression: a rotate that started on the part used to toggle a
            % clamped face, wiping the modes and changing the next solve.
            tc.App.solve(); s = tc.App.state();
            before = s.fixedFaces; f1 = s.db.frequencyHz(1);
            tc.App.showTab('solve');
            tc.press(tc.byTag('pickFixed'));
            tc.drag(tc.modelAxes(),[0.1 0 0.02],[0 0 0.02]);
            s = tc.App.state();
            tc.verifyEqual(s.fixedFaces,before);
            tc.verifyNotEmpty(s.db);
            tc.verifyEqual(s.db.frequencyHz(1),f1);
        end
        function solveTurnsPickingOff(tc)
            tc.App.showTab('solve');
            tc.press(tc.byTag('pickFixed'));
            tc.App.solve(); s = tc.App.state();
            tc.verifyEqual(s.pickMode,"");
            tc.verifyFalse(logical(tc.byTag('pickFixed').Value));
            tc.press(tc.modelAxes(),[0.1 0 0.02]);         % a plain click after solving
            tc.verifyNotEmpty(tc.App.state().db);
        end
        function clickPlacesFixedAndRovingPoints(tc)
            tc.App.solve();
            tc.App.showTab('impact');
            tc.press(tc.byTag('pickAnchor'));
            tc.press(tc.modelAxes(),[0.1 0 0.02]);
            tc.App.showTab('impact');
            tc.press(tc.byTag('pickRoving'));
            tc.press(tc.modelAxes(),[0 -0.01 0.01]);     % front (-Y) face, visible in iso view
            tc.press(tc.modelAxes(),[0.05 -0.01 0.01]);
            s = tc.App.state();
            tc.verifyLessThan(norm(s.db.nodes(:,s.anchor).'-[0.1 0 0.02]),0.006);
            tc.verifyNumElements(s.roving,2);
            tc.verifyLessThan(norm(s.db.nodes(:,s.roving(1)).'-[0 -0.01 0.01]),0.006);
            tc.verifyEmpty(s.lastError);
        end
        function animateModeShape(tc)
            tc.App.solve();
            tc.App.showTab('modes');
            tc.choose(tc.byTag('modeTable'),[3 2]);         % click a cell in row 3
            patch = findobj(tc.modelAxes(),'Type','patch');
            tc.press(tc.byTag('animate')); pause(0.6); drawnow
            v1 = patch.Vertices; pause(0.3); drawnow; v2 = patch.Vertices;
            tc.verifyGreaterThan(max(abs(v1-v2),[],'all'),0);   % shape is moving
            tc.press(tc.byTag('animate'));                        % stop
            tc.verifyEmpty(timerfindall('Tag','vilAnimation'));
            tc.verifyEmpty(tc.App.state().lastError);
        end
    end
    methods
        function ax = modelAxes(tc)
            ax = tc.byTag('model');
        end
        function h = byTag(tc,tag)
            h = findobj(tc.App.figure,'Tag',tag);
        end
    end
end
