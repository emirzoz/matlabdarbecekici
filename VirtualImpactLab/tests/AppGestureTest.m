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
        function clickPlacesHammerAndSensor(tc)
            tc.App.solve();
            tc.App.showTab('impact');
            tc.press(tc.byTag('pickHammer'));
            tc.press(tc.modelAxes(),[0.1 0 0.02]);
            tc.App.showTab('impact');
            tc.press(tc.byTag('pickSensor'));
            tc.press(tc.modelAxes(),[0 -0.01 0.01]);     % front (-Y) face, visible in iso view
            s = tc.App.state();
            tc.verifyLessThan(norm(s.db.nodes(:,s.hammer).'-[0.1 0 0.02]),0.006);
            tc.verifyLessThan(norm(s.db.nodes(:,s.sensor).'-[0 -0.01 0.01]),0.006);
            tc.verifyEmpty(s.lastError);
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
