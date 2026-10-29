function app = VirtualImpactLab
% Virtual Impact Lab: import a part, solve its modes once, then run virtual
% impact-hammer tests from the cached modal database.
% Programmatic uifigure UI (MATLAB desktop and MATLAB Online); all numerical
% work lives in +vil. Returns a handle struct for scripted use and tests.

here = fileparts(mfilename('fullpath'));
S = struct('rawGeom',[],'geom',[],'info',[],'meshInfo',[],'db',[], ...
    'fixedFaces',[],'hammer',[],'sensor',[],'tests',{{}},'pickMode',"", ...
    'modeIndex',0,'phase',0,'source',"",'lastError',[]);
H = struct();   % graphics handles on the 3D view
C = palette();
materials = materialPresets();

% ---------------------------------------------------------------- layout --
fig = uifigure('Name','Virtual Impact Lab','Position',[60 50 1440 880], ...
    'Color',C.bg,'CloseRequestFcn',@onClose);
try, fig.Theme = 'light'; catch, end %#ok<NOCOM> older releases have no Theme
root = uigridlayout(fig,[3 1],'RowHeight',{60,'1x',26},'Padding',0,'RowSpacing',0,'BackgroundColor',C.bg);

header = uigridlayout(root,[2 6],'ColumnWidth',{'1x',110,110,110,110,16}, ...
    'RowHeight',{30,'1x'},'Padding',[18 8 12 8],'RowSpacing',0,'BackgroundColor',C.header);
t = uilabel(header,'Text','Virtual Impact Lab','FontSize',19,'FontWeight','bold','FontColor','w','VerticalAlignment','center');
t.Layout.Row = 1; t.Layout.Column = 1;
t = uilabel(header,'Text','Solve modes once  ·  hammer as often as you like','FontSize',11,'FontColor',C.headerMuted);
t.Layout.Row = 2; t.Layout.Column = 1;
chips = gobjects(1,4);
chipNames = ["Part","Mesh","Modes","Tests"];
for k = 1:4
    chips(k) = uilabel(header,'Text',chipNames(k),'HorizontalAlignment','center', ...
        'FontWeight','bold','FontColor',C.headerMuted,'BackgroundColor',C.chipOff);
    chips(k).Layout.Row = [1 2]; chips(k).Layout.Column = k+1;
end

body = uigridlayout(root,[1 2],'ColumnWidth',{390,'1x'},'Padding',[10 10 10 6],'ColumnSpacing',10,'BackgroundColor',C.bg);
footer = uigridlayout(root,[1 1],'Padding',[14 2 14 2],'BackgroundColor',C.footer);
status = uilabel(footer,'Text','Import a STEP part or open the demo cantilever to begin.','FontColor',C.text);

left = uitabgroup(body);
tPart = uitab(left,'Title','1  Part','BackgroundColor',C.panel);
tSolve = uitab(left,'Title','2  Solve','BackgroundColor',C.panel);
tModes = uitab(left,'Title','3  Modes','BackgroundColor',C.panel);
tImpact = uitab(left,'Title','4  Impact','BackgroundColor',C.panel);
tProject = uitab(left,'Title','5  Project','BackgroundColor',C.panel);
right = uitabgroup(body);
tView = uitab(right,'Title','3D model','BackgroundColor',C.panel);
tResp = uitab(right,'Title','Response','BackgroundColor',C.panel);
tVer = uitab(right,'Title','Verification','BackgroundColor',C.panel);

% --- 1 Part ---------------------------------------------------------------
g = formGrid(tPart,14);
section(g,'Geometry');
row = uigridlayout(g,[1 2],'Padding',0,'BackgroundColor',C.panel);
btnImport = primaryButton(row,'Import STEP / STL…',@onImport);
uibutton(row,'Text','Demo cantilever','ButtonPushedFcn',@onDemo);
partInfo = uilabel(g,'Text','No part loaded.','WordWrap','on','VerticalAlignment','top','FontColor',C.muted);
partInfo.Layout.Row = [3 6];
section(g,'Mesh',7);
[~,hField] = labelled(g,'Element size (mm)',numericField(g,8,[1e-3 Inf]),8);
hHint = uilabel(g,'Text','','FontColor',C.muted,'FontSize',11); hHint.Layout.Row = 9;
[~,maxNodesField] = labelled(g,'Node limit',numericField(g,150000,[1000 2e6]),10);
btnMesh = primaryButton(g,'Mesh part',@onMesh); btnMesh.Layout.Row = 11;
meshInfoLbl = uilabel(g,'Text','Quadratic tetrahedra (10-node). If the CAD surface will not mesh, the part is rebuilt from its tessellation and curved faces become faceted.', ...
    'WordWrap','on','FontColor',C.muted,'FontSize',11,'VerticalAlignment','top');
meshInfoLbl.Layout.Row = [12 14];

% --- 2 Solve --------------------------------------------------------------
g = formGrid(tSolve,17);
section(g,'Material (SI)');
[~,matDrop] = labelled(g,'Preset',uidropdown(g,'Items',[materials.name],'ValueChangedFcn',@onMaterial),2);
[~,EField] = labelled(g,'Young''s modulus (GPa)',numericField(g,210,[1e-6 Inf]),3);
[~,nuField] = labelled(g,'Poisson''s ratio',numericField(g,0.3,[-0.99 0.499]),4);
[~,rhoField] = labelled(g,'Density (kg/m³)',numericField(g,7850,[1e-6 Inf]),5);
section(g,'Fixture',6);
row = uigridlayout(g,[1 2],'Padding',0,'ColumnWidth',{'1x',70},'BackgroundColor',C.panel); row.Layout.Row = 7;
pickFixedBtn = uibutton(row,'state','Tag','pickFixed','Text','Pick fixed faces on model','ValueChangedFcn',@(s,~)setPickMode(s,"fixed"));
uibutton(row,'Text','Clear','ButtonPushedFcn',@(~,~)setFixed([]));
[~,facesField] = labelled(g,'Fixed face IDs',uieditfield(g,'text','ValueChangedFcn',@onFacesTyped),8);
section(g,'Modes',9);
[~,minModesField] = labelled(g,'Lowest modes to compute',numericField(g,12,[1 200]),10);
[~,hiField] = labelled(g,'…and all modes up to (Hz)',numericField(g,0,[0 Inf]),11);
btnSolve = primaryButton(g,'Solve modes',@onSolve); btnSolve.Layout.Row = 13;
solveHint = ['Computes the lowest modes of the clamped part. Include every mode up to ' ...
    'about 1.5× the highest frequency you want in the FRF; 0 means only the count above.'];
solveInfo = uilabel(g,'Text',solveHint,'WordWrap','on','FontColor',C.muted,'FontSize',11,'VerticalAlignment','top');
solveInfo.Layout.Row = [14 17];

% --- 3 Modes --------------------------------------------------------------
g = uigridlayout(tModes,[5 1],'RowHeight',{22,'1x',34,34,60},'Padding',12,'BackgroundColor',C.panel);
section(g,'Natural frequencies');
modeTable = uitable(g,'ColumnName',{'Mode','Frequency (Hz)','Eigen check'},'RowName',{}, ...
    'ColumnWidth',{50,'1x','1x'},'SelectionType','row','SelectionChangedFcn',@onModeSelected);
row = uigridlayout(g,[1 2],'Padding',0,'ColumnWidth',{110,'1x'},'BackgroundColor',C.panel);
uilabel(row,'Text','Deformation scale');
scaleSlider = uislider(row,'Limits',[0 0.3],'Value',0.08,'MajorTicks',[],'MinorTicks',[],'ValueChangingFcn',@(~,e)redrawMode(e.Value));
row = uigridlayout(g,[1 2],'Padding',0,'BackgroundColor',C.panel);
animateBtn = uibutton(row,'state','Text','Animate','ValueChangedFcn',@onAnimate);
uibutton(row,'Text','Show undeformed','ButtonPushedFcn',@(~,~)showUndeformed());
uilabel(g,'Text','Select a row to view the mode shape. Colour shows relative displacement magnitude; scale is exaggerated.', ...
    'WordWrap','on','FontColor',C.muted,'FontSize',11,'VerticalAlignment','top');

% --- 4 Impact -------------------------------------------------------------
g = formGrid(tImpact,17);
section(g,'Hammer');
row = uigridlayout(g,[1 3],'Padding',0,'ColumnWidth',{'1x','1x',60},'BackgroundColor',C.panel); row.Layout.Row = 2;
hammerLbl = uilabel(row,'Text','Node —','FontWeight','bold','FontColor',C.hammer);
hammerDir = uidropdown(row,'Items',directionItems(),'Value','Into surface','ValueChangedFcn',@(~,~)drawProbes());
pickHammerBtn = uibutton(row,'state','Tag','pickHammer','Text','Pick','ValueChangedFcn',@(s,~)setPickMode(s,"hammer"));
section(g,'Accelerometer',3);
row = uigridlayout(g,[1 3],'Padding',0,'ColumnWidth',{'1x','1x',60},'BackgroundColor',C.panel); row.Layout.Row = 4;
sensorLbl = uilabel(row,'Text','Node —','FontWeight','bold','FontColor',C.sensor);
sensorDir = uidropdown(row,'Items',directionItems(),'Value','Out of surface','ValueChangedFcn',@(~,~)drawProbes());
pickSensorBtn = uibutton(row,'state','Tag','pickSensor','Text','Pick','ValueChangedFcn',@(s,~)setPickMode(s,"sensor"));
section(g,'Excitation and damping',5);
[~,forceField] = labelled(g,'Peak force (N)',numericField(g,100,[1e-9 Inf]),6);
[~,contactField] = labelled(g,'Contact time (ms)',numericField(g,0.5,[1e-6 Inf]),7);
[~,zetaField] = labelled(g,'Damping ratio (all modes)',numericField(g,0.01,[0 0.99]),8);
[~,durField] = labelled(g,'Record length (s)',numericField(g,0.2,[1e-4 Inf]),9);
[~,fsField] = labelled(g,'Sample rate (Hz, 0 = auto)',numericField(g,0,[0 Inf]),10);
[~,cutField] = labelled(g,'Use modes up to (Hz, 0 = all)',numericField(g,0,[0 Inf]),11);
row = uigridlayout(g,[1 2],'Padding',0,'ColumnWidth',{'1x',90},'BackgroundColor',C.panel); row.Layout.Row = 12;
btnRun = primaryButton(row,'Run virtual hammer test',@onRunTest);
uibutton(row,'Text','Clear tests','ButtonPushedFcn',@onClearTests);
testTable = uitable(g,'ColumnName',{'#','Hammer','Sensor','ζ','Peak a (m/s²)'},'RowName',{}, ...
    'ColumnWidth',{30,'auto','auto',45,'auto'});
testTable.Layout.Row = [13 17];

% --- 5 Project ------------------------------------------------------------
g = formGrid(tProject,12);
section(g,'Project');
row = uigridlayout(g,[1 2],'Padding',0,'BackgroundColor',C.panel);
uibutton(row,'Text','Save project…','ButtonPushedFcn',@onSave);
uibutton(row,'Text','Load project…','ButtonPushedFcn',@onLoad);
section(g,'Export',3);
uibutton(g,'Text','Export last test (CSV)…','ButtonPushedFcn',@onExportCSV);
uibutton(g,'Text','Export Abaqus input (.inp)…','ButtonPushedFcn',@onExportInp);
about = uilabel(g,'WordWrap','on','VerticalAlignment','top','FontColor',C.muted,'FontSize',11,'Text', ...
    ['A project stores the modal database (mesh, mode shapes, frequencies) and all tests, so ' ...
     'impacts can be run later without the CAD file or another eigen solve. ' ...
     'The Abaqus export writes the same mesh, material and clamp with frequency, ' ...
     'steady-state and modal-dynamic steps for independent checking.']);
about.Layout.Row = [6 12];

% --- 3D view --------------------------------------------------------------
g = uigridlayout(tView,[2 1],'RowHeight',{30,'1x'},'Padding',[8 6 8 8],'BackgroundColor',C.panel);
row = uigridlayout(g,[1 5],'Padding',0,'ColumnWidth',{'1x',100,80,80,80},'BackgroundColor',C.panel);
viewHint = uilabel(row,'Text','Drag to rotate, scroll to zoom.','FontColor',C.muted);
faceIdsBox = uicheckbox(row,'Text','Face IDs','ValueChangedFcn',@(~,~)drawFaceIds());
uibutton(row,'Text','Iso view','ButtonPushedFcn',@(~,~)view(ax3,3));
uibutton(row,'Text','Flip','Tooltip','View from the opposite side (e.g. to see a clamped base)','ButtonPushedFcn',@(~,~)flipView());
uibutton(row,'Text','Fit','ButtonPushedFcn',@(~,~)axis(ax3,'tight'));
ax3 = uiaxes(g,'Tag','model','Color',C.panel,'XColor',C.muted,'YColor',C.muted,'ZColor',C.muted);
axis(ax3,'equal'); axis(ax3,'off'); view(ax3,3); ax3.Toolbar.Visible = 'off';
try, ax3.Interactions = [rotateInteraction zoomInteraction]; catch, end
colormap(ax3,turbo);
title(ax3,'No part','Color',C.muted,'FontWeight','normal');

% --- Response -------------------------------------------------------------
g = uigridlayout(tResp,[3 2],'Padding',8,'RowSpacing',6,'ColumnSpacing',8,'BackgroundColor',C.panel);
names = {'|Accelerance| (m/s²/N)','FRF phase (°)','Force (N)','Acceleration (m/s²)','Acceleration spectrum (m/s²)','Displacement (µm)'};
xl = {'Frequency (Hz)','Frequency (Hz)','Time (ms)','Time (ms)','Frequency (Hz)','Time (ms)'};
axR = gobjects(6,1);
for k = 1:6
    axR(k) = uiaxes(g); ylabel(axR(k),names{k}); xlabel(axR(k),xl{k}); grid(axR(k),'on'); box(axR(k),'on');
    axR(k).Toolbar.Visible = 'on'; hold(axR(k),'on');
end
set([axR(1) axR(5)],'YScale','log');

% --- Verification ---------------------------------------------------------
g = uigridlayout(tVer,[4 1],'RowHeight',{48,175,26,'1x'},'Padding',10,'BackgroundColor',C.panel);
uilabel(g,'WordWrap','on','FontColor',C.text,'Text', ...
    ['Results of verification/runVerification.m (desktop + Abaqus 2024). "Same mesh": Abaqus solves the ' ...
     'MATLAB mesh, isolating solver, mode normalization, FRF and impact integration. "Independent": Abaqus/CAE ' ...
     'imports and meshes the STEP file itself.']);
verTable = uitable(g,'RowName',{});
verDrop = uidropdown(g,'Items',{'(no results)'},'ValueChangedFcn',@(~,~)showVerificationImage());
verImage = uiimage(g,'ScaleMethod','fit');
loadVerification();

refreshUi();
app = struct('figure',fig,'importFile',@importFile,'demo',@()onDemo(),'mesh',@(h)meshNow(h), ...
    'setFixed',@setFixed,'solve',@()onSolve(),'pick',@pickAt,'runTest',@()onRunTest(), ...
    'selectMode',@selectMode,'state',@getState,'snapshot',@(f)exportapp(fig,f), ...
    'showTab',@showTab);
if nargout == 0, clear app; end

% =============================================================== actions ==
    function onImport(~,~)
        [f,p] = uigetfile({'*.step;*.stp;*.STEP;*.STP','STEP solid (*.step, *.stp)';'*.stl;*.STL','STL (*.stl)'},'Import part');
        figure(fig);
        if isequal(f,0), return; end
        importFile(fullfile(p,f));
    end

    function importFile(file)
        busy('Importing CAD…',@work);
        function work(progress)
            [S.rawGeom,S.info] = vil.importCAD(file);
            S.source = string(S.info.name);
            hField.Value = 1e3*vil.suggestMeshSize(S.rawGeom);
            hHint.Text = sprintf('Suggested from part size: %.3g mm',hField.Value);
            resetModel();
            meshWork(progress);
        end
    end

    function onDemo(~,~)
        busy('Building demo cantilever…',@work);
        function work(~)
            [S.geom,cfg,S.meshInfo] = vil.createDemoBeam(0.008);
            S.rawGeom = []; S.source = "Demo cantilever";
            S.info = struct('name','Demo cantilever 300 × 20 × 20 mm','fileUnits',"m", ...
                'span',[cfg.L cfg.width cfg.height],'numFaces',S.geom.NumFaces,'scaleNote',"");
            hField.Value = 8;
            resetModel();
            matDrop.Value = 'Structural steel'; onMaterial();
            minModesField.Value = 12; hiField.Value = 0;
            setFixed(cfg.fixedFaces);
            drawModel(); view(ax3,3);
            status.Text = 'Demo beam meshed and clamped at X = -150 mm. Solve modes next.';
        end
    end

    function onMesh(~,~)
        if isempty(S.rawGeom)
            if S.source == "Demo cantilever", onDemo(); return, end
            alert('Import a part first.'); return
        end
        busy('Meshing…',@meshWork);
    end

    function meshNow(hmm)
        hField.Value = hmm; onMesh();
    end

    function meshWork(progress)
        [S.geom,S.meshInfo] = vil.meshPart(S.rawGeom,hField.Value/1e3, ...
            MaxNodes=maxNodesField.Value,Progress=progress);
        resetModel();
        setFixed([]);
        drawModel(); view(ax3,3);
        msg = sprintf('Meshed: %s nodes, %s elements.',commas(S.meshInfo.numNodes),commas(S.meshInfo.numElements));
        if S.meshInfo.hmaxUsed < S.meshInfo.hmaxRequested*0.999
            msg = msg + sprintf(' Element size reduced to %.3g mm for the mesher.',1e3*S.meshInfo.hmaxUsed);
        end
        if S.meshInfo.fromTessellation
            msg = msg + " CAD meshing failed, so the tessellated surface was used (faceted curves).";
        end
        status.Text = msg + " Next: pick fixed faces on the Solve tab.";
        left.SelectedTab = tSolve;
    end

    function onSolve(~,~)
        if isempty(S.geom), alert('Mesh a part first.'); return, end
        if isempty(S.fixedFaces), alert('Pick at least one fixed face (Solve tab → Pick fixed faces on model).'); return, end
        busy('Solving modes…',@work);
        function work(progress)
            stopAnimation();
            cfg = struct('E',EField.Value*1e9,'nu',nuField.Value,'rho',rhoField.Value, ...
                'fixedFaces',S.fixedFaces,'rangeHz',[0 hiField.Value],'source',S.source);
            t0 = tic;
            S.db = vil.solveModes(S.geom,cfg,MeshInfo=S.meshInfo,MinModes=minModesField.Value,Progress=progress);
            S.db.info = S.info;
            S.tests = {}; clearResponse();
            fillModeTable();
            solveInfo.Text = sprintf(['%d modes, %.4g – %.4g Hz, solved in %.1f s.\nMeshed mass %.4g kg. ' ...
                'Mass-orthogonality error %.1e; worst eigen residual %.1e.'],numel(S.db.omega), ...
                S.db.frequencyHz(1),S.db.frequencyHz(end),toc(t0),S.db.totalMass, ...
                S.db.massOrthogonalityError,max(S.db.eigenResidual));
            defaultProbes();
            status.Text = sprintf('Modal database ready (%d modes). Pick hammer and sensor points, then run tests.',numel(S.db.omega));
            left.SelectedTab = tModes;
            selectMode(1);
        end
    end

    function onRunTest(~,~)
        if isempty(S.db), alert('Solve modes first.'); return, end
        if isempty(S.hammer) || isempty(S.sensor), alert('Pick hammer and accelerometer points.'); return, end
        busy('Running virtual hammer test…',@work);
        function work(~)
            hDir = probeDirection(S.hammer,hammerDir.Value,-1);
            sDir = probeDirection(S.sensor,sensorDir.Value,1);
            fmax = max(S.db.frequencyHz);
            if cutField.Value > 0, fmax = min(fmax,cutField.Value); end
            fs = fsField.Value;
            if fs == 0, fs = max(1000*ceil(2.56*fmax/1000),ceil(25/(contactField.Value/1e3))); end
            p = struct('peakForce',forceField.Value,'contactDuration',contactField.Value/1e3, ...
                'duration',durField.Value,'fs',fs,'zeta',zetaField.Value,'maxModeHz',[]);
            if cutField.Value > 0, p.maxModeHz = cutField.Value; end
            h = {S.hammer,hDir}; s = {S.sensor,sDir};
            resp = vil.simulateImpact(S.db,h,s,p);
            w = warning('off','vil:Truncation'); restore = onCleanup(@()warning(w));
            frf = vil.calculateFRF(S.db,h,s,linspace(0,fmax,4001),p.zeta);
            test = struct('response',resp,'frf',frf,'hammerNode',S.hammer,'sensorNode',S.sensor, ...
                'hammerDir',hammerDir.Value,'sensorDir',sensorDir.Value,'hammerVector',hDir,'sensorVector',sDir);
            S.tests{end+1} = test;
            plotTest(test,numel(S.tests));
            refreshTestTable();
            right.SelectedTab = tResp;
            status.Text = sprintf('Test %d: peak acceleration %.4g m/s² (fs = %.4g Hz, %d modes). No eigen solve was needed.', ...
                numel(S.tests),max(abs(resp.acceleration)),fs,nnz(S.db.frequencyHz<=fmax));
            % A half-sine of length Tc has its first spectral zero at 1.5/Tc.
            fZero = 1.5/p.contactDuration;
            if fZero < fmax
                status.Text = [status.Text sprintf(['  Note: a %.3g ms pulse barely excites modes above ~%.0f Hz ' ...
                    '(first spectral zero); use a shorter contact (harder tip) to reach higher modes.'],1e3*p.contactDuration,fZero)];
            end
        end
    end

    function onClearTests(~,~)
        S.tests = {}; clearResponse(); refreshTestTable(); refreshUi();
    end

    function onSave(~,~)
        if isempty(S.db), alert('Nothing to save yet: solve modes first.'); return, end
        [f,p] = uiputfile('*.mat','Save project','impact_project.mat'); figure(fig);
        if isequal(f,0), return, end
        busy('Saving…',@(~)vil.saveProject(fullfile(p,f),S.db,S.tests));
        status.Text = "Saved " + f;
    end

    function onLoad(~,~)
        [f,p] = uigetfile('*.mat','Load project'); figure(fig);
        if isequal(f,0), return, end
        busy('Loading…',@work);
        function work(~)
            [db,tests] = vil.loadProject(fullfile(p,f));
            resetModel(); S.rawGeom = []; S.geom = []; S.meshInfo = [];
            S.db = db; S.tests = tests;
            if isfield(db,'info'), S.info = db.info; else, S.info = struct('name',f,'fileUnits',"",'span',spanOf(db.nodes).','numFaces',max(db.surfaceFaceId),'scaleNote',""); end
            S.source = string(f);
            c = db.config;
            EField.Value = c.E/1e9; nuField.Value = c.nu; rhoField.Value = c.rho; matDrop.Value = 'Custom';
            minModesField.Value = numel(db.omega); hiField.Value = 0;
            S.fixedFaces = c.fixedFaces(:).'; facesField.Value = num2str(S.fixedFaces);
            fillModeTable(); defaultProbes(); clearResponse();
            for k = 1:numel(S.tests), plotTest(S.tests{k},k); end
            refreshTestTable(); drawModel(); view(ax3,3);
            status.Text = 'Project loaded: impacts can run from the cached modes. Re-import the CAD file to remesh.';
        end
    end

    function onExportCSV(~,~)
        if isempty(S.tests), alert('Run a test first.'); return, end
        [f,p] = uiputfile('*.csv','Export last test','impact_test.csv'); figure(fig);
        if isequal(f,0), return, end
        r = S.tests{end}.response; q = S.tests{end}.frf;
        writetable(table(r.time(:),r.force(:),r.acceleration(:),r.velocity(:),r.displacement(:), ...
            'VariableNames',{'time_s','force_N','acceleration_m_s2','velocity_m_s','displacement_m'}),fullfile(p,f));
        [~,base] = fileparts(f);
        writetable(table(q.frequencyHz(:),real(q.accelerance(:)),imag(q.accelerance(:)), ...
            'VariableNames',{'frequency_Hz','accelerance_re','accelerance_im'}),fullfile(p,base+"_frf.csv"));
        status.Text = "Exported " + f + " and " + base + "_frf.csv";
    end

    function onExportInp(~,~)
        if isempty(S.db), alert('Solve modes first.'); return, end
        [f,p] = uiputfile('*.inp','Export Abaqus input','vil_model.inp'); figure(fig);
        if isequal(f,0), return, end
        args = {};
        axisDir = @(v)find(abs(v(:).')==1 & v(:).'>0);
        if ~isempty(S.hammer) && ~isempty(S.sensor)
            hd = axisDir(probeDirection(S.hammer,hammerDir.Value,-1));
            sd = axisDir(probeDirection(S.sensor,sensorDir.Value,1));
            if isscalar(hd) && isscalar(sd)
                axes3 = 'XYZ';
                args = {'Hammer',{S.hammer,axes3(hd)},'Sensor',{S.sensor,axes3(sd)},'Zeta',zetaField.Value};
            end
        end
        vil.exportAbaqus(S.db,fullfile(p,f),args{:});
        note = '';
        if isempty(args), note = ' (frequency step only; use +X/+Y/+Z directions to include the FRF step)'; end
        status.Text = "Wrote " + f + note;
    end

% ============================================================= picking ==
    function setPickMode(src,mode)
        buttons = [pickFixedBtn pickHammerBtn pickSensorBtn];
        set(buttons(buttons~=src),'Value',false);
        if src.Value
            if mode ~= "fixed" && isempty(S.db)
                src.Value = false; alert('Solve modes before choosing hammer and sensor points.'); return
            end
            S.pickMode = mode; stopAnimation(); showUndeformed(); right.SelectedTab = tView;
            hints = struct('fixed',"Click faces to clamp or release them.", ...
                'hammer',"Click where the hammer strikes.",'sensor',"Click where the accelerometer sits.");
            viewHint.Text = hints.(mode); viewHint.FontColor = C.accent;
        else
            S.pickMode = ""; viewHint.Text = 'Drag to rotate, scroll to zoom.'; viewHint.FontColor = C.muted;
        end
    end

    function onModelClick(~,evt)
        if S.pickMode == "", return, end
        pickAt(evt.IntersectionPoint,S.pickMode);
    end

    function pickAt(point,mode)
        [nodes,tri,faceId] = surfaceData();
        point = point(:);
        switch mode
            case "fixed"
                cen = (nodes(:,tri(:,1))+nodes(:,tri(:,2))+nodes(:,tri(:,3)))/3;
                [~,k] = min(vecnorm(cen-point));
                f = faceId(k);
                if ismember(f,S.fixedFaces), setFixed(setdiff(S.fixedFaces,f)); else, setFixed([S.fixedFaces f]); end
            case {"hammer","sensor"}
                cand = S.db.surfaceNodes(~ismember(S.db.surfaceNodes,S.db.fixedNodes));
                [~,k] = min(vecnorm(S.db.nodes(:,cand)-point));
                if S.modeIndex > 0, showUndeformed(); end
                S.(mode) = cand(k);
                drawProbes(); refreshUi();
                status.Text = sprintf('%s at node %d (%.1f, %.1f, %.1f) mm.',capitalize(mode),cand(k),1e3*S.db.nodes(:,cand(k)));
        end
    end

    function setFixed(faces)
        faces = unique(round(faces(:).'));
        nf = numFaces();
        faces = faces(faces>=1 & faces<=nf);
        if ~isequal(faces,S.fixedFaces) && ~isempty(S.db) && isfield(S.db.config,'fixedFaces') ...
                && ~isequal(faces,S.db.config.fixedFaces(:).') && ~isempty(S.geom)
            invalidateModes('Fixture changed: solve modes again.');
        end
        S.fixedFaces = faces;
        facesField.Value = num2str(faces);
        if isempty(faces), facesField.Value = ''; end
        colourFaces(); refreshUi();
    end

    function onFacesTyped(src,~)
        v = str2num(src.Value); %#ok<ST2NM> accepts "1 4 7" or "1,4,7"
        setFixed(v);
    end

% ============================================================== drawing ==
    function drawModel()
        cla(ax3); H = struct();
        [nodes,tri] = surfaceData();
        if isempty(tri), title(ax3,'No part'); return, end
        H.patch = patch(ax3,'Vertices',nodes.','Faces',tri,'FaceColor','flat', ...
            'EdgeColor',C.edge,'EdgeAlpha',0.35,'LineWidth',0.25,'FaceLighting','gouraud', ...
            'AmbientStrength',0.55,'DiffuseStrength',0.6,'SpecularStrength',0.1, ...
            'ButtonDownFcn',@onModelClick,'PickableParts','visible');
        hold(ax3,'on');
        H.light = camlight(ax3,'headlight');
        axis(ax3,'equal'); axis(ax3,'off');
        span = spanOf(nodes(:,unique(tri(:))));
        title(ax3,sprintf('%s   ·   %.1f × %.1f × %.1f mm',S.info.name,1e3*span),'Color',C.text,'FontWeight','normal','Interpreter','none');
        colourFaces(); drawProbes(); drawFaceIds();
    end

    function colourFaces()
        if ~isfield(H,'patch') || ~isvalid(H.patch), return, end
        [~,~,faceId] = surfaceData();
        col = repmat(C.part,numel(faceId),1);
        col(ismember(faceId,S.fixedFaces),:) = repmat(C.fixed,nnz(ismember(faceId,S.fixedFaces)),1);
        H.patch.FaceColor = 'flat'; H.patch.FaceVertexCData = col;
        H.patch.Vertices = surfaceNodesMatrix().';
    end

    function drawProbes()
        if isfield(H,'probes'), delete(H.probes(isgraphics(H.probes))); end
        H.probes = gobjects(0);
        if isempty(S.db) || ~isfield(H,'patch'), return, end
        L = 0.12*max(spanOf(S.db.nodes));
        items = {S.hammer,hammerDir.Value,-1,C.hammer,'Hammer'; S.sensor,sensorDir.Value,1,C.sensor,'Accelerometer'};
        for k = 1:2
            node = items{k,1}; if isempty(node), continue, end
            x = S.db.nodes(:,node); d = probeDirection(node,items{k,2},items{k,3}); d = d(:)/norm(d);
            if k == 1, tail = x-L*d; else, tail = x; end
            H.probes(end+1) = quiver3(ax3,tail(1),tail(2),tail(3),L*d(1),L*d(2),L*d(3),0, ...
                'Color',items{k,4},'LineWidth',2.5,'MaxHeadSize',0.6,'PickableParts','none');
            H.probes(end+1) = plot3(ax3,x(1),x(2),x(3),'o','MarkerSize',8,'MarkerFaceColor',items{k,4}, ...
                'MarkerEdgeColor','w','LineWidth',1.2,'PickableParts','none');
            lp = tail; if k == 2, lp = x+L*d; end
            H.probes(end+1) = text(ax3,lp(1),lp(2),lp(3),"  "+items{k,5},'Color',items{k,4}, ...
                'FontWeight','bold','PickableParts','none');
        end
    end

    function drawFaceIds()
        if isfield(H,'faceIds'), delete(H.faceIds(isgraphics(H.faceIds))); end
        H.faceIds = gobjects(0);
        if ~faceIdsBox.Value || ~isfield(H,'patch'), return, end
        [nodes,tri,faceId] = surfaceData();
        for f = unique(faceId(faceId>0)).'
            T = tri(faceId==f,:);
            cen = (nodes(:,T(:,1))+nodes(:,T(:,2))+nodes(:,T(:,3)))/3;
            [~,k] = min(vecnorm(cen-mean(cen,2)));   % a point on the face itself
            H.faceIds(end+1) = text(ax3,cen(1,k),cen(2,k),cen(3,k),string(f),'FontSize',9, ...
                'FontWeight','bold','Color',C.text,'BackgroundColor',[1 1 1 0.7],'Margin',1, ...
                'HorizontalAlignment','center','PickableParts','none');
        end
    end

    function flipView()
        [az,el] = view(ax3); view(ax3,[az+180 -el]);
    end

    function selectMode(k)
        if isempty(S.db) || k < 1 || k > numel(S.db.omega), return, end
        S.modeIndex = k; S.phase = 0;
        if ~isequal(modeTable.Selection,k), modeTable.Selection = k; end
        right.SelectedTab = tView;
        redrawMode(scaleSlider.Value);
    end

    function redrawMode(scaleValue)
        if S.modeIndex == 0 || isempty(S.db) || ~isfield(H,'patch') || ~isvalid(H.patch), return, end
        k = S.modeIndex; n = size(S.db.nodes,2);
        U = reshape(S.db.Phi(:,k),n,3).';
        mag = vecnorm(U);
        factor = scaleValue*max(spanOf(S.db.nodes))/max(max(mag),eps);
        H.patch.Vertices = (S.db.nodes+factor*cos(S.phase)*U).';
        H.patch.FaceColor = 'interp'; H.patch.FaceVertexCData = mag(:)/max(mag);
        clim(ax3,[0 1]);
        title(ax3,sprintf('Mode %d  ·  %.2f Hz',k,S.db.frequencyHz(k)),'Color',C.text,'FontWeight','bold');
        set(H.probes(isgraphics(H.probes)),'Visible','off');
    end

    function showUndeformed()
        stopAnimation(); S.modeIndex = 0;
        if ~isfield(H,'patch') || ~isvalid(H.patch), return, end
        colourFaces();
        if isfield(H,'probes'), set(H.probes(isgraphics(H.probes)),'Visible','on'); end
        % Works before solving too (fixed faces are picked on the mesh alone).
        [nodes,tri] = surfaceData();
        span = spanOf(nodes(:,unique(tri(:))));
        title(ax3,sprintf('%s   ·   %.1f × %.1f × %.1f mm',S.info.name,1e3*span),'Color',C.text,'FontWeight','normal','Interpreter','none');
    end

    function onModeSelected(src,~)
        sel = src.Selection;
        if ~isempty(sel), selectMode(sel(1)); end
    end

    function onAnimate(src,~)
        if src.Value
            if S.modeIndex == 0, selectMode(1); end
            H.timer = timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
                'TimerFcn',@(~,~)stepAnimation());
            start(H.timer);
        else
            stopAnimation();
        end
    end

    function stepAnimation()
        if ~isvalid(fig) || S.modeIndex == 0, stopAnimation(); return, end
        S.phase = S.phase + pi/12;
        redrawMode(scaleSlider.Value); drawnow limitrate
    end

    function stopAnimation()
        if isfield(H,'timer') && isa(H.timer,'timer') && isvalid(H.timer)
            stop(H.timer); delete(H.timer);
        end
        if isvalid(animateBtn), animateBtn.Value = false; end
    end

    function plotTest(test,k)
        r = test.response; q = test.frf;
        label = sprintf('T%d  H%d→S%d',k,test.hammerNode,test.sensorNode);
        col = C.series(mod(k-1,size(C.series,1))+1,:);
        args = {'Color',col,'LineWidth',1.3,'DisplayName',label};
        plot(axR(1),q.frequencyHz,abs(q.accelerance),args{:});
        plot(axR(2),q.frequencyHz,angle(q.accelerance)*180/pi,args{:});
        plot(axR(3),1e3*r.time,r.force,args{:});
        plot(axR(4),1e3*r.time,r.acceleration,args{:});
        plot(axR(5),r.spectrumHz,r.accelerationSpectrum,args{:});
        plot(axR(6),1e3*r.time,1e6*r.displacement,args{:});
        xlim(axR(3),[0 max(5*1e3*r.parameters.contactDuration,1)]);
        % Show five decades below the largest spectral peak; FFT leakage floor is noise.
        top = max([r.accelerationSpectrum(:); axR(5).UserData]); axR(5).UserData = top;
        ylim(axR(5),[1e-5 2]*top); xlim(axR(5),[0 1.2*max(q.frequencyHz)]);
        for a = axR.', legend(a,'Location','best','FontSize',8,'Box','off'); end
        if ~isempty(S.db)
            xline(axR(1),S.db.frequencyHz(S.db.frequencyHz<=max(q.frequencyHz)),':','Color',[0.6 0.6 0.6],'HandleVisibility','off');
        end
    end

    function clearResponse()
        for a = axR.', cla(a); legend(a,'off'); end
        axR(5).UserData = [];
    end

% ============================================================== helpers ==
    function [nodes,tri,faceId] = surfaceData()
        if ~isempty(S.db)
            nodes = S.db.nodes; tri = S.db.surfaceFaces; faceId = S.db.surfaceFaceId;
        elseif ~isempty(S.geom)
            nodes = S.geom.Mesh.Nodes; tri = S.meshInfo.surface.tri; faceId = S.meshInfo.surface.faceId;
        else
            nodes = zeros(3,0); tri = zeros(0,3); faceId = zeros(0,1);
        end
    end

    function X = surfaceNodesMatrix()
        X = surfaceData();
    end

    function n = numFaces()
        if ~isempty(S.geom), n = S.geom.NumFaces;
        elseif ~isempty(S.db), n = max(S.db.surfaceFaceId);
        else, n = 0;
        end
    end

    function d = probeDirection(node,choice,normalSign)
        % normalSign: -1 for the hammer (force into the part), +1 for the sensor.
        switch string(choice)
            case {"Into surface","Out of surface"}
                d = normalSign*vil.surfaceNormal(S.db.nodes,S.db.surfaceFaces,node);
            otherwise
                axisIdx = find('XYZ'==extractAfter(choice,1));
                d = zeros(3,1); d(axisIdx) = 1;
                if startsWith(choice,'-'), d = -d; end
        end
        d = d(:).';
    end

    function defaultProbes()
        % Hammer on the free surface farthest from the clamp; sensor farthest from the hammer.
        cand = S.db.surfaceNodes(~ismember(S.db.surfaceNodes,S.db.fixedNodes));
        X = S.db.nodes(:,cand); clamp = mean(S.db.nodes(:,S.db.fixedNodes),2);
        [~,i] = max(vecnorm(X-clamp)); S.hammer = cand(i);
        [~,j] = max(vecnorm(X-X(:,i))); S.sensor = cand(j);
        drawModel();
    end

    function fillModeTable()
        modeTable.Data = table((1:numel(S.db.omega)).',compose("%.2f",S.db.frequencyHz(:)), ...
            compose("residual %.0e",S.db.eigenResidual(:)),'VariableNames',{'Mode','Frequency (Hz)','Check'});
    end

    function refreshTestTable()
        rows = cell(numel(S.tests),5);
        for k = 1:numel(S.tests)
            q = S.tests{k};
            rows(k,:) = {sprintf('%d',k),sprintf('%d %s',q.hammerNode,shortDir(q.hammerDir)),sprintf('%d %s',q.sensorNode,shortDir(q.sensorDir)), ...
                sprintf('%.3g',q.response.parameters.zeta),sprintf('%.4g',max(abs(q.response.acceleration)))};
        end
        testTable.Data = rows; refreshUi();
    end

    function resetModel()
        stopAnimation();
        S.db = []; S.tests = {}; S.hammer = []; S.sensor = []; S.modeIndex = 0;
        modeTable.Data = table(); testTable.Data = {}; clearResponse();
        solveInfo.Text = solveHint;
        updatePartInfo(); refreshUi();
    end

    function invalidateModes(msg)
        S.db = []; S.tests = {}; S.hammer = []; S.sensor = []; modeTable.Data = table();
        testTable.Data = {}; clearResponse(); status.Text = msg; drawModel(); refreshUi();
    end

    function updatePartInfo()
        if isempty(S.info), partInfo.Text = 'No part loaded.'; return, end
        lines = sprintf('%s\nSize: %.2f × %.2f × %.2f mm',S.info.name,1e3*S.info.span);
        if isfield(S.info,'fileUnits') && strlength(S.info.fileUnits) > 0
            lines = [lines sprintf('\nFile length unit: %s → converted to metres',S.info.fileUnits)];
        end
        if ~isempty(S.meshInfo)
            lines = [lines sprintf('\nMesh: %s nodes · %s elements · %d faces',commas(S.meshInfo.numNodes), ...
                commas(S.meshInfo.numElements),S.meshInfo.numFaces)];
        end
        partInfo.Text = lines; partInfo.FontColor = C.text;
    end

    function refreshUi()
        updatePartInfo();
        state = [~isempty(S.info), ~isempty(S.geom) || ~isempty(S.db), ~isempty(S.db), ~isempty(S.tests)];
        labels = ["Part","Mesh","Modes",sprintf("Tests %d",numel(S.tests))];
        if state(3), labels(3) = sprintf("%d modes",numel(S.db.omega)); end
        for k = 1:4
            chips(k).Text = labels(k);
            if state(k), chips(k).BackgroundColor = C.chipOn; chips(k).FontColor = 'w';
            else, chips(k).BackgroundColor = C.chipOff; chips(k).FontColor = C.headerMuted; end
        end
        btnMesh.Enable = onoff(~isempty(S.rawGeom) || S.source == "Demo cantilever");
        btnSolve.Enable = onoff(~isempty(S.geom) && ~isempty(S.fixedFaces));
        btnRun.Enable = onoff(~isempty(S.db) && ~isempty(S.hammer) && ~isempty(S.sensor));
        if ~isempty(S.db)
            hammerLbl.Text = "Node " + S.hammer; sensorLbl.Text = "Node " + S.sensor;
        else
            hammerLbl.Text = 'Node —'; sensorLbl.Text = 'Node —';
        end
    end

    function onMaterial(~,~)
        m = materials(strcmp([materials.name],matDrop.Value));
        if isempty(m.E), return, end
        EField.Value = m.E/1e9; nuField.Value = m.nu; rhoField.Value = m.rho;
        if ~isempty(S.db) && ~isempty(S.geom), invalidateModes('Material changed: solve modes again.'); end
    end

    function loadVerification()
        file = fullfile(here,'verification','results','summary.mat');
        if ~isfile(file), verTable.Data = table(); return, end
        R = load(file,'summary'); R = R.summary;
        ok = arrayfun(@(r)strlength(string(r.error))==0,R);
        R = R(ok);
        if isempty(R), return, end
        name = string({R.name}).'; nodes = [R.numNodes].'; modes = [R.numModes].';
        df = arrayfun(@(r)max(abs(r.sameMesh.modes.Error_pct)),R).';
        mac = arrayfun(@(r)min(r.sameMesh.modes.SubspaceMAC),R).';
        frf = arrayfun(@(r)r.sameMesh.frfError,R).'; imp = arrayfun(@(r)r.sameMesh.impactError,R).';
        ind = nan(numel(R),1); indMac = nan(numel(R),1);
        for k = 1:numel(R)
            if isfield(R(k),'independent') && ~isempty(R(k).independent)
                ind(k) = max(abs(R(k).independent.modes.Error_pct)); indMac(k) = min(R(k).independent.modes.SubspaceMAC);
            end
        end
        conv = nan(numel(R),1);
        for k = 1:numel(R)
            if isfield(R(k),'convergence') && ~isempty(R(k).convergence), conv(k) = max(abs(R(k).convergence.changePct)); end
        end
        verTable.Data = table(name,nodes,modes,round(df,4),round(mac,4),frf,imp,round(ind,2),round(indMac,3),round(conv,2), ...
            'VariableNames',{'Case','Nodes','Modes','Same-mesh max |Δf| %','Same-mesh min MAC', ...
            'FRF rel. error','Impact rel. error','Independent max |Δf| %','Independent min MAC','Refinement max |Δf| %'});
        verDrop.Items = cellstr(name);
        showVerificationImage();
    end

    function showVerificationImage()
        f = fullfile(here,'verification','results',verDrop.Value,'samemesh.png');
        if isfile(f), verImage.ImageSource = f; end
    end

    function showTab(name)
        tabs = struct('part',tPart,'solve',tSolve,'modes',tModes,'impact',tImpact,'project',tProject);
        views = struct('model',tView,'response',tResp,'verification',tVer);
        if isfield(tabs,name), left.SelectedTab = tabs.(name); end
        if isfield(views,name), right.SelectedTab = views.(name); end
        drawnow;
    end

    function busy(message,work)
        d = uiprogressdlg(fig,'Title','Working','Message',message,'Indeterminate','on');
        cleanup = onCleanup(@()delete(d));
        progress = @(msg)setMessage(d,msg);
        try
        S.lastError = [];
            work(progress);
        catch err
            S.lastError = err;
            fprintf(2,'%s\n',getReport(err,'extended','hyperlinks','off'));
            status.Text = "Error: " + err.message;
            delete(d);
            uialert(fig,err.message,'Virtual Impact Lab','Icon','error');
        end
        refreshUi();
    end

    function alert(msg)
        uialert(fig,msg,'Virtual Impact Lab','Icon','info');
    end

    function s = getState()
        s = S;
    end

    function onClose(~,~)
        stopAnimation(); delete(fig);
    end

% ============================================================ factories ==
    function g = formGrid(parent,n)
        g = uigridlayout(parent,[n 1],'RowHeight',repmat({30},1,n),'Padding',[14 12 14 12], ...
            'RowSpacing',6,'BackgroundColor',C.panel);
    end

    function section(g,text,rowIndex)
        l = uilabel(g,'Text',upper(text),'FontWeight','bold','FontSize',11,'FontColor',C.accent, ...
            'VerticalAlignment','bottom');
        if nargin > 2, l.Layout.Row = rowIndex; end
    end

    function b = primaryButton(parent,text,cb)
        b = uibutton(parent,'Text',text,'ButtonPushedFcn',cb,'BackgroundColor',C.accent, ...
            'FontColor','w','FontWeight','bold');
    end

    function f = numericField(parent,value,limits)
        f = uieditfield(parent,'numeric','Value',value,'Limits',limits,'ValueDisplayFormat','%.6g');
    end

    function [lbl,field] = labelled(g,text,field,rowIndex)
        row = uigridlayout(g,[1 2],'Padding',0,'ColumnWidth',{'1x',130},'BackgroundColor',C.panel);
        row.Layout.Row = rowIndex;
        lbl = uilabel(row,'Text',text,'FontColor',C.text);
        field.Parent = row;
        field.Layout.Row = 1; field.Layout.Column = 2;
    end
end

% ================================================================ local ==
function C = palette()
C = struct('bg',[0.94 0.95 0.96],'panel',[1 1 1],'header',[0.09 0.13 0.20], ...
    'headerMuted',[0.62 0.68 0.76],'chipOff',[0.15 0.20 0.28],'chipOn',[0.13 0.55 0.42], ...
    'footer',[0.89 0.91 0.93],'text',[0.13 0.16 0.20],'muted',[0.42 0.46 0.52], ...
    'accent',[0.12 0.42 0.78],'part',[0.80 0.82 0.85],'fixed',[0.20 0.45 0.85], ...
    'edge',[0.35 0.38 0.42],'hammer',[0.85 0.25 0.18],'sensor',[0.10 0.62 0.38], ...
    'series',[0.12 0.42 0.78; 0.85 0.33 0.10; 0.10 0.62 0.38; 0.55 0.25 0.70; 0.90 0.62 0.05; 0.30 0.30 0.30]);
end

function m = materialPresets()
mk = @(name,E,nu,rho) struct('name',string(name),'E',E,'nu',nu,'rho',rho);
m = [mk('Structural steel',210e9,0.30,7850), mk('Stainless steel 304',193e9,0.29,8000), ...
     mk('Aluminium 6061-T6',68.9e9,0.33,2700), mk('Titanium Ti-6Al-4V',113.8e9,0.342,4430), ...
     mk('Custom',[],[],[])];
end

function items = directionItems()
items = {'Into surface','Out of surface','+X','-X','+Y','-Y','+Z','-Z'};
end

function s = shortDir(choice)
map = containers.Map({'Into surface','Out of surface'},{'⊥in','⊥out'});
if isKey(map,choice), s = map(choice); else, s = choice; end
end

function s = onoff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function s = commas(n)
s = char(compose("%d",round(n)));
s = regexprep(s,'(\d)(?=(\d{3})+$)','$1,');
end

function s = capitalize(s)
s = char(s); s(1) = upper(s(1));
end

function setMessage(d,msg)
if isvalid(d), d.Message = msg; drawnow limitrate; end
end

function s = spanOf(X)
% Per-row extent (base MATLAB; range() needs Statistics Toolbox).
s = max(X,[],2)-min(X,[],2);
end
