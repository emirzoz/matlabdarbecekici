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
        function viewButtonsAndDragRotate(tc)
            % Arrow buttons step the view; a left-drag that starts on the
            % part rotates it (the built-in rotate used to ignore those).
            ax = tc.modelAxes();
            p0 = ax.CameraPosition;
            tc.press(tc.byTag('view1'));                       % rotate left
            tc.verifyGreaterThan(norm(ax.CameraPosition-p0),0);
            tc.press(tc.byTag('view12'));                      % iso
            p1 = ax.CameraPosition;
            tc.drag(ax,[-0.1 0 0.02],[0.1 0 0.02]);            % starts on the part
            tc.verifyGreaterThan(norm(ax.CameraPosition-p1),0);
            tc.verifyEmpty(tc.App.state().lastError);
        end
        function animateModeShape(tc)
            tc.App.solve();
            tc.App.showTab('modes');
            tc.choose(tc.byTag('modeTable'),[3 2]);         % click a cell in row 3
            patch = findobj(tc.modelAxes(),'Type','patch');
            tc.press(tc.byTag('animate')); drawnow
            tc.assertEmpty(tc.App.state().lastError);             % reports a failed frame
            anim = timerfindall('Tag','vilAnimation');
            tc.assertNumElements(anim,1);                         % animation started
            % Step one frame by hand: how often a timer fires during a test
            % depends on the machine (MATLAB Online can starve it).
            v1 = patch.Vertices;
            anim.TimerFcn(anim,[]); drawnow
            tc.verifyGreaterThan(max(abs(patch.Vertices-v1),[],'all'),0);   % shape moves
            % It stops by itself after four cycles; stop it now if still running.
            if tc.byTag('animate').Value, tc.press(tc.byTag('animate')); end
            % A finished timer is kept until the next start or stop; none may run.
            tc.verifyEmpty(timerfindall('Tag','vilAnimation','Running','on'));
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
