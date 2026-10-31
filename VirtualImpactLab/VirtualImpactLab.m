function app = VirtualImpactLab
% Virtual Impact Lab: import a part, solve its modes once, then run virtual
% impact-hammer tests from the cached modal database.
% Programmatic uifigure UI (MATLAB desktop and MATLAB Online); all numerical
% work lives in +vil. Returns a handle struct for scripted use and tests.

here = fileparts(mfilename('fullpath'));
S = struct('rawGeom',[],'geom',[],'info',[],'meshInfo',[],'db',[], ...
    'fixedFaces',[],'boundary',"clamped",'rove',"hammer",'anchor',[],'roving',[],'rovingDir',{{}}, ...
    'survey',[],'flight',[],'monitor',[],'pickMode',"",'press',[], ...
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
chipNames = ["Part","Mesh","Modes","Test"];
for k = 1:4
    chips(k) = uilabel(header,'Text',chipNames(k),'HorizontalAlignment','center', ...
        'FontWeight','bold','FontColor',C.headerMuted,'BackgroundColor',C.chipOff);
    chips(k).Layout.Row = [1 2]; chips(k).Layout.Column = k+1;
end

body = uigridlayout(root,[1 2],'ColumnWidth',{450,'1x'},'Padding',[10 10 10 6],'ColumnSpacing',10,'BackgroundColor',C.bg);
footer = uigridlayout(root,[1 1],'Padding',[14 2 14 2],'BackgroundColor',C.footer);
status = uilabel(footer,'Text','Import a STEP part or open the demo cantilever to begin.','FontColor',C.text);

left = uitabgroup(body,'SelectionChangedFcn',@(~,~)clearPick());
tPart = uitab(left,'Title','1 Part','BackgroundColor',C.panel);
tSolve = uitab(left,'Title','2 Solve','BackgroundColor',C.panel);
tModes = uitab(left,'Title','3 Modes','BackgroundColor',C.panel);
tImpact = uitab(left,'Title','4 Test','BackgroundColor',C.panel);
tFlight = uitab(left,'Title','5 Flight','BackgroundColor',C.panel);
tProject = uitab(left,'Title','6 Project','BackgroundColor',C.panel);
right = uitabgroup(body);
tView = uitab(right,'Title','3D model','BackgroundColor',C.panel);
tResp = uitab(right,'Title','Response','BackgroundColor',C.panel);
tModal = uitab(right,'Title','Modal results','BackgroundColor',C.panel);
tFlightPlots = uitab(right,'Title','Flight','BackgroundColor',C.panel);
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
g = formGrid(tSolve,18);
section(g,'Material (SI)');
[~,matDrop] = labelled(g,'Preset',uidropdown(g,'Items',[materials.name],'ValueChangedFcn',@onMaterial),2);
[~,EField] = labelled(g,'Young''s modulus (GPa)',numericField(g,210,[1e-6 Inf]),3);
[~,nuField] = labelled(g,'Poisson''s ratio',numericField(g,0.3,[-0.99 0.499]),4);
[~,rhoField] = labelled(g,'Density (kg/m³)',numericField(g,7850,[1e-6 Inf]),5);
section(g,'Boundary condition',6);
[~,boundaryDrop] = labelled(g,'Supports',uidropdown(g,'Tag','boundary','Items',boundaryItems(), ...
    'ValueChangedFcn',@(src,~)setBoundary(boundaryMode(src.Value))),7);
row = uigridlayout(g,[1 2],'Padding',0,'ColumnWidth',{'1x',70},'BackgroundColor',C.panel); row.Layout.Row = 8;
pickFixedBtn = uibutton(row,'state','Tag','pickFixed','Text','Pick fixed faces on model','ValueChangedFcn',@(s,~)setPickMode(s,"fixed"));
clearFixedBtn = uibutton(row,'Text','Clear','ButtonPushedFcn',@(~,~)setFixed([]));
[~,facesField] = labelled(g,'Fixed face IDs',uieditfield(g,'text','ValueChangedFcn',@onFacesTyped),9);
section(g,'Modes',10);
[~,minModesField] = labelled(g,'Lowest modes to compute',numericField(g,12,[1 200]),11);
[~,hiField] = labelled(g,'…and all modes up to (Hz)',numericField(g,0,[0 Inf]),12);
fixedInfo = uilabel(g,'Text','No faces clamped.','FontColor',C.muted,'FontSize',11);
fixedInfo.Layout.Row = 13;
btnSolve = primaryButton(g,'Solve modes',@onSolve); btnSolve.Layout.Row = 14;
solveHint = ['Computes the lowest elastic modes of the part. Include every mode up to ' ...
    'about 1.5× the highest frequency you want in the FRF; 0 means only the count above. ' ...
    'Free-free: the part hangs on soft supports, as in a lab test; its 6 rigid-body modes are removed.'];
solveInfo = uilabel(g,'Text',solveHint,'WordWrap','on','FontColor',C.muted,'FontSize',11,'VerticalAlignment','top');
solveInfo.Layout.Row = [15 18];

% --- 3 Modes --------------------------------------------------------------
g = uigridlayout(tModes,[5 1],'RowHeight',{22,'1x',34,34,60},'Padding',12,'BackgroundColor',C.panel);
section(g,'Natural frequencies');
modeTable = uitable(g,'Tag','modeTable','ColumnName',{'Mode','Frequency (Hz)','Eigen check'},'RowName',{}, ...
    'ColumnWidth',{50,'1x','1x'},'SelectionType','row','SelectionChangedFcn',@onModeSelected);
row = uigridlayout(g,[1 2],'Padding',0,'ColumnWidth',{110,'1x'},'BackgroundColor',C.panel);
uilabel(row,'Text','Deformation scale');
scaleSlider = uislider(row,'Limits',[0 0.3],'Value',0.08,'MajorTicks',[],'MinorTicks',[],'ValueChangingFcn',@(~,e)redrawMode(e.Value));
row = uigridlayout(g,[1 2],'Padding',0,'BackgroundColor',C.panel);
animateBtn = uibutton(row,'state','Tag','animate','Text','Animate','ValueChangedFcn',@onAnimate);
uibutton(row,'Text','Show undeformed','ButtonPushedFcn',@(~,~)showUndeformed());
uilabel(g,'Text','Select a row to view the mode shape. Colour shows relative displacement magnitude; scale is exaggerated.', ...
    'WordWrap','on','FontColor',C.muted,'FontSize',11,'VerticalAlignment','top');

% --- 4 Test ---------------------------------------------------------------
g = formGrid(tImpact,23); g.Scrollable = 'on'; g.RowSpacing = 3; impactGrid = g;
section(g,'Test type');
roveDrop = uidropdown(g,'Tag','roveMode','Items',roveItems(),'ValueChangedFcn',@(~,~)setRove(roveMode()));
anchorTitle = section(g,'Fixed accelerometer',3);
row = uigridlayout(g,[1 3],'Padding',0,'ColumnWidth',{'1x','1x',60},'BackgroundColor',C.panel); row.Layout.Row = 4;
anchorLbl = uilabel(row,'Text','Node —','FontWeight','bold','FontColor',C.sensor);
anchorDir = uidropdown(row,'Items',directionItems(),'Value','Out of surface','ValueChangedFcn',@(~,~)onDirectionChanged());
pickAnchorBtn = uibutton(row,'state','Tag','pickAnchor','Text','Pick','ValueChangedFcn',@(s,~)setPickMode(s,"anchor"));
rovingTitle = section(g,'Hammer points',5);
row = uigridlayout(g,[1 3],'Padding',0,'ColumnWidth',{'1x','1x',60},'BackgroundColor',C.panel); row.Layout.Row = 6;
rovingLbl = uilabel(row,'Text','0 points','FontWeight','bold','FontColor',C.hammer);
rovingDirDrop = uidropdown(row,'Items',directionItems(),'Value','Into surface');
pickRovingBtn = uibutton(row,'state','Tag','pickRoving','Text','Add','ValueChangedFcn',@(s,~)setPickMode(s,"roving"));
row = uigridlayout(g,[1 2],'Padding',0,'BackgroundColor',C.panel); row.Layout.Row = 7;
uibutton(row,'Text','Remove last','ButtonPushedFcn',@(~,~)removeRoving(numel(S.roving)));
uibutton(row,'Text','Clear points','ButtonPushedFcn',@(~,~)removeRoving(1:numel(S.roving)));
pointTable = uitable(g,'Tag','pointTable','ColumnName',{'#','Node','Direction','dB','Use'},'RowName',{}, ...
    'ColumnWidth',{28,55,'1x',70,38},'ColumnEditable',[false false false false true],'CellEditCallback',@onUseEdited);
pointTable.Layout.Row = [8 11];
tips = hammerTips();
section(g,'Hit and analysis',12);
[~,forceField] = labelled(g,'Peak force (N)',numericField(g,100,[1e-9 Inf]),13);
[~,tipDrop] = labelled(g,'Hammer tip',uidropdown(g,'Tag','hammerTip','Items',tipItems(false),'Value','Rubber', ...
    'ValueChangedFcn',@(src,~)setTip(src.Value)),14);
[~,zetaField] = labelled(g,'Damping ratio (all modes)',numericField(g,0.01,[1e-5 0.99]),15);
bandInfo = uilabel(g,'Tag','bandInfo','Text','','FontSize',11,'FontColor',C.muted); bandInfo.Layout.Row = 16;
advancedBox = uicheckbox(g,'Tag','advanced','Text','Advanced: more tips, contact time, sampling, rejection', ...
    'ValueChangedFcn',@(src,~)setAdvanced(src.Value)); advancedBox.Layout.Row = 17;
[~,contactField] = labelled(g,'Contact time (ms)',numericField(g,1e3*tips(1).contact,[1e-6 Inf]),18);
contactField.ValueChangedFcn = @(~,~)onContactTyped();
[~,durField] = labelled(g,'Record length (s, 0 = auto)',numericField(g,0,[0 Inf]),19);
[~,rejectField] = labelled(g,'Reject if below median by (dB)',numericField(g,20,[1 200]),20);
[~,fsField] = labelled(g,'Sample rate (Hz, 0 = auto)',numericField(g,0,[0 Inf]),21);
[~,cutField] = labelled(g,'Use modes up to (Hz, 0 = all)',numericField(g,0,[0 Inf]),22);
advancedRows = [contactField durField rejectField fsField cutField];
row = uigridlayout(g,[1 2],'Padding',0,'ColumnWidth',{'1x',90},'BackgroundColor',C.panel); row.Layout.Row = 23;
btnRun = primaryButton(row,'Run test',@onRunTest);
uibutton(row,'Text','Clear results','ButtonPushedFcn',@onClearTests);

% --- 5 Flight -------------------------------------------------------------
[flightPresets] = vilFlightNames();
g = formGrid(tFlight,20); g.Scrollable = 'on'; g.RowSpacing = 3;
section(g,'Aircraft');
[~,flightDrop] = labelled(g,'Profile',uidropdown(g,'Tag','flightProfile','Items',flightPresets,'ValueChangedFcn',@(~,~)applyFlightPreset()),2);
[~,rpmField] = labelled(g,'Cruise speed (RPM)',numericField(g,4000,[1 Inf]),3);
[~,rpmLoField] = labelled(g,'Lowest speed (RPM)',numericField(g,1500,[1 Inf]),4);
[~,rpmHiField] = labelled(g,'Highest speed (RPM)',numericField(g,5500,[1 Inf]),5);
section(g,'Tones: order × shaft speed (example g, enter yours)',6);
toneTable = uitable(g,'Tag','toneTable','ColumnName',{'Source','Order','Amplitude (g)'},'RowName',{}, ...
    'ColumnEditable',[false true true],'ColumnWidth',{'1x',55,95});
toneTable.Layout.Row = [7 9];
section(g,'Random vibration (example PSD, enter yours)',10);
psdTable = uitable(g,'Tag','psdTable','ColumnName',{'Hz','g²/Hz'},'RowName',{},'ColumnEditable',[true true]);
psdTable.Layout.Row = [11 13];
section(g,'Mounting',14);
[~,axisDrop] = labelled(g,'Clamp shakes along',uidropdown(g,'Items',{'X','Y','Z'},'Value','Z'),15);
[~,flightZetaField] = labelled(g,'Damping ratio (all modes)',numericField(g,0.01,[1e-5 0.99]),16);
[~,marginField] = labelled(g,'Resonance margin (± %)',numericField(g,10,[0 100]),17);
section(g,'Monitor point',18);
row = uigridlayout(g,[1 3],'Padding',0,'ColumnWidth',{'1x','1x',60},'BackgroundColor',C.panel); row.Layout.Row = 19;
monitorLbl = uilabel(row,'Text','Node —','FontWeight','bold','FontColor',C.accent);
monitorDir = uidropdown(row,'Items',directionItems(),'Value','+Z','ValueChangedFcn',@(~,~)drawProbes());
pickMonitorBtn = uibutton(row,'state','Tag','pickMonitor','Text','Pick','ValueChangedFcn',@(s,~)setPickMode(s,"monitor"));
btnFlight = primaryButton(g,'Simulate flight vibration',@onRunFlight); btnFlight.Layout.Row = 20; btnFlight.Tag = 'flightRun';

% --- 6 Project ------------------------------------------------------------
g = formGrid(tProject,12);
section(g,'Project');
row = uigridlayout(g,[1 2],'Padding',0,'BackgroundColor',C.panel);
uibutton(row,'Text','Save project…','ButtonPushedFcn',@onSave);
uibutton(row,'Text','Load project…','ButtonPushedFcn',@onLoad);
section(g,'Export',3);
uibutton(g,'Text','Export test results (CSV)…','ButtonPushedFcn',@onExportCSV);
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
names = {'FRF |accelerance| (m/s²/N)','FRF phase (°)','Force (N)','Acceleration (m/s²)','Force spectrum','Summed FRF and fit (m/s²/N)'};
xl = {'Frequency (Hz)','Frequency (Hz)','Time (ms)','Time (ms)','Frequency (Hz)','Frequency (Hz)'};
axR = gobjects(6,1);
for k = 1:6
    axR(k) = uiaxes(g); ylabel(axR(k),names{k}); xlabel(axR(k),xl{k}); grid(axR(k),'on'); box(axR(k),'on');
    axR(k).Toolbar.Visible = 'on'; hold(axR(k),'on');
end
set([axR(1) axR(5) axR(6)],'YScale','log');

% --- Modal results --------------------------------------------------------
g = uigridlayout(tModal,[3 1],'RowHeight',{44,'1x',96},'Padding',10,'BackgroundColor',C.panel);
modalSummary = uilabel(g,'Text','Run a test to identify natural frequencies and damping from the FRFs.', ...
    'WordWrap','on','FontWeight','bold','FontColor',C.text);
modalTable = uitable(g,'Tag','modalTable','RowName',{},'ColumnName', ...
    {'Mode','Frequency (Hz)','Damping (%)','FE mode','FE (Hz)','Δf (%)','MAC'});
modalNotes = uilabel(g,'Text','','WordWrap','on','FontColor',C.muted,'VerticalAlignment','top');

% --- Flight plots ---------------------------------------------------------
g = uigridlayout(tFlightPlots,[4 2],'RowHeight',{24,'1x','1x','1x'},'Padding',8,'RowSpacing',6,'ColumnSpacing',8,'BackgroundColor',C.panel);
flightVerdict = uilabel(g,'Text','Run a flight simulation to check for resonance.','FontWeight','bold','FontColor',C.text);
flightVerdict.Layout.Row = 1; flightVerdict.Layout.Column = [1 2];
names = {'Frequency (Hz)','Response (g, tones)','|Transmissibility|','PSD (g²/Hz)','Acceleration (g)'};
xl = {'Shaft speed (RPM)','Shaft speed (RPM)','Frequency (Hz)','Frequency (Hz)','Time (ms)'};
axF = gobjects(5,1);
for k = 1:5
    axF(k) = uiaxes(g); ylabel(axF(k),names{k}); xlabel(axF(k),xl{k}); grid(axF(k),'on'); box(axF(k),'on');
    axF(k).Toolbar.Visible = 'on'; hold(axF(k),'on');
end
set(axF(3),'XScale','log','YScale','log'); set(axF(4),'XScale','log','YScale','log');
flightTable = uitable(g,'Tag','flightTable','RowName',{},'ColumnName', ...
    {'#','Hz','Mass %','Gap %','Cross RPM','Status'},'ColumnWidth',{30,62,58,52,74,'1x'});
applyFlightPreset();
setAdvanced(false);

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
    'setFixed',@setFixed,'setBoundary',@setBoundary,'solve',@()onSolve(),'pick',@pickAt,'runTest',@()onRunTest(), ...
    'setRove',@setRove,'setUse',@setUse,'runFlight',@()onRunFlight(),'setContact',@setContact,'setTip',@setTip, ...
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
            setBoundary("clamped"); setFixed(cfg.fixedFaces);
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
        status.Text = msg + " Next: pick fixed faces on the Solve tab, or choose free-free.";
        left.SelectedTab = tSolve;
    end

    function onSolve(~,~)
        if isempty(S.geom), alert('Mesh a part first.'); return, end
        if S.boundary == "clamped" && isempty(S.fixedFaces)
            alert('Pick at least one fixed face (Solve tab → Pick fixed faces on model), or choose free-free.'); return
        end
        clearPick();
        busy('Solving modes…',@work);
        function work(progress)
            stopAnimation();
            faces = S.fixedFaces; if S.boundary == "free", faces = []; end
            cfg = struct('E',EField.Value*1e9,'nu',nuField.Value,'rho',rhoField.Value, ...
                'fixedFaces',faces,'boundary',S.boundary,'rangeHz',[0 hiField.Value],'source',S.source);
            t0 = tic;
            S.db = vil.solveModes(S.geom,cfg,MeshInfo=S.meshInfo,MinModes=minModesField.Value,Progress=progress);
            S.db.info = S.info;
            S.survey = []; S.flight = []; clearResponse();
            fillModeTable();
            if S.boundary == "free"
                support = sprintf('free-free (6 rigid-body modes below %.2g Hz removed)',max(S.db.rigidBodyHz));
            else
                support = sprintf('faces %s clamped',num2str(S.fixedFaces));
            end
            solveInfo.Text = sprintf(['%d elastic modes, %.4g – %.4g Hz, solved in %.1f s, %s.\nMeshed mass %.4g kg. ' ...
                'Mass-orthogonality error %.1e; worst eigen residual %.1e.'],numel(S.db.omega), ...
                S.db.frequencyHz(1),S.db.frequencyHz(end),toc(t0),support,S.db.totalMass, ...
                S.db.massOrthogonalityError,max(S.db.eigenResidual));
            defaultProbes(); suggestTip();
            status.Text = sprintf('Modal database ready (%d modes). On the Test tab, pick the fixed point and add roving points.',numel(S.db.omega));
            left.SelectedTab = tModes;
            selectMode(1);
        end
    end

    function onRunTest(~,~)
        if isempty(S.db), alert('Solve modes first.'); return, end
        if isempty(S.anchor) || isempty(S.roving), alert('Pick the fixed point and add at least one roving point.'); return, end
        clearPick();
        busy('Running hammer test…',@work);
        function work(~)
            p = struct('peakForce',forceField.Value,'contactDuration',contactField.Value/1e3, ...
                'duration',durField.Value,'fs',fsField.Value,'zeta',zetaField.Value,'maxModeHz',[]);
            if cutField.Value > 0, p.maxModeHz = cutField.Value; end
            cfg = struct('rove',S.rove,'fixed',{{S.anchor,probeDirection(S.anchor,anchorDir.Value)}},'roving',{cell(1,numel(S.roving))});
            for k = 1:numel(S.roving)
                cfg.roving{k} = {S.roving(k),probeDirection(S.roving(k),S.rovingDir{k})};
            end
            S.survey = vil.runSurvey(S.db,cfg,p);
            analyse([]);
            right.SelectedTab = tModal;
        end
    end

    function analyse(use)
        S.survey = vil.analyseSurvey(S.db,S.survey,RejectDb=rejectField.Value,Use=use);
        showSurvey();
    end

    function onUseEdited(~,evt)
        use = S.survey.use; use(evt.Indices(1)) = logical(evt.NewData);
        setUse(use);
    end

    function setUse(use)
        if ~any(use), alert('Keep at least one response.'); showSurvey(); return, end
        busy('Updating…',@(~)analyse(use));
    end

    function onClearTests(~,~)
        S.survey = []; clearResponse(); fillPointTable(); drawProbes(); refreshUi();
    end

    function onRunFlight(~,~)
        if isempty(S.db), alert('Solve modes first.'); return, end
        if isempty(S.db.fixedNodes), alert('Flight shakes the part through its clamp: solve with clamped faces, not free-free.'); return, end
        if isempty(S.monitor), alert('Pick a monitor point.'); return, end
        clearPick();
        busy('Simulating flight vibration…',@work);
        function work(~)
            tones = toneTable.Data; psd = sortrows(psdTable.Data,1);
            assert(all(psd(:)>0),'vil:Flight','PSD values must be above zero.');
            f = struct('rpm',rpmField.Value,'rpmRange',[rpmLoField.Value rpmHiField.Value], ...
                'order',[tones{:,2}].','amplitudeG',[tones{:,3}].','psd',psd, ...
                'axis',find('XYZ'==axisDrop.Value),'zeta',flightZetaField.Value, ...
                'monitor',{{S.monitor,probeDirection(S.monitor,monitorDir.Value)}},'marginPct',marginField.Value);
            S.flight = vil.flightResponse(S.db,f);
            showFlight();
            right.SelectedTab = tFlightPlots;
        end
    end

    function onSave(~,~)
        if isempty(S.db), alert('Nothing to save yet: solve modes first.'); return, end
        [f,p] = uiputfile('*.mat','Save project','impact_project.mat'); figure(fig);
        if isequal(f,0), return, end
        tests = {}; if ~isempty(S.survey), tests = {S.survey}; end
        busy('Saving…',@(~)vil.saveProject(fullfile(p,f),S.db,tests));
        status.Text = "Saved " + f;
    end

    function onLoad(~,~)
        [f,p] = uigetfile('*.mat','Load project'); figure(fig);
        if isequal(f,0), return, end
        busy('Loading…',@work);
        function work(~)
            [db,tests] = vil.loadProject(fullfile(p,f));
            resetModel(); S.rawGeom = []; S.geom = []; S.meshInfo = [];
            S.db = db;
            if isfield(db,'info'), S.info = db.info; else, S.info = struct('name',f,'fileUnits',"",'span',spanOf(db.nodes).','numFaces',max(db.surfaceFaceId),'scaleNote',""); end
            S.source = string(f);
            c = db.config;
            EField.Value = c.E/1e9; nuField.Value = c.nu; rhoField.Value = c.rho; matDrop.Value = 'Custom';
            minModesField.Value = numel(db.omega); hiField.Value = 0;
            S.fixedFaces = c.fixedFaces(:).'; facesField.Value = num2str(S.fixedFaces);
            S.boundary = "clamped"; if isfield(c,'boundary'), S.boundary = string(c.boundary); end
            boundaryDrop.Value = boundaryItems(S.boundary); syncBoundaryControls();
            fillModeTable(); defaultProbes(); clearResponse();
            % Projects from before roving tests hold a different record: skip those.
            if ~isempty(tests) && isfield(tests{end},'modes')
                S.survey = tests{end}; S.rove = S.survey.rove;
                roveDrop.Value = roveDrop.Items{1+(S.rove=="sensor")}; setRoveLabels();
                S.anchor = S.survey.fixed{1};
                S.roving = cellfun(@(c)c{1},S.survey.roving);
                S.rovingDir = repmat({rovingDirDrop.Value},1,numel(S.roving));
                showSurvey();
            end
            drawModel(); view(ax3,3); refreshUi();
            status.Text = 'Project loaded: impacts can run from the cached modes. Re-import the CAD file to remesh.';
        end
    end

    function onExportCSV(~,~)
        if isempty(S.survey), alert('Run a test first.'); return, end
        [f,p] = uiputfile('*.csv','Export test results','impact_test.csv'); figure(fig);
        if isequal(f,0), return, end
        q = S.survey; n = numel(q.roving);
        ids = "node" + string(S.roving(:)).';
        T = array2table([q.time(:) q.force(:) q.acceleration.'],'VariableNames',["time_s" "force_N" "a_"+ids+"_m_s2"]);
        writetable(T,fullfile(p,f));
        [~,base] = fileparts(f);
        R = array2table([q.frequencyHz(:) reshape([real(q.H.') imag(q.H.')],numel(q.frequencyHz),2*n)], ...
            'VariableNames',["frequency_Hz" "re_"+ids "im_"+ids]);
        writetable(R,fullfile(p,base+"_frf.csv"));
        m = q.modes;
        writetable(table(m.frequencyHz,m.zeta,m.feMode,m.feHz,m.errorPct,m.mac, ...
            'VariableNames',{'frequency_Hz','damping_ratio','fe_mode','fe_Hz','error_pct','mac'}),fullfile(p,base+"_modes.csv"));
        status.Text = "Exported " + f + ", " + base + "_frf.csv and " + base + "_modes.csv";
    end

    function onExportInp(~,~)
        if isempty(S.db), alert('Solve modes first.'); return, end
        [f,p] = uiputfile('*.inp','Export Abaqus input','vil_model.inp'); figure(fig);
        if isequal(f,0), return, end
        args = {};
        axisDir = @(v)find(abs(v(:).')==1 & v(:).'>0);
        if ~isempty(S.anchor) && ~isempty(S.roving)
            ad = axisDir(probeDirection(S.anchor,anchorDir.Value));
            rd = axisDir(probeDirection(S.roving(1),S.rovingDir{1}));
            if isscalar(ad) && isscalar(rd)
                axes3 = 'XYZ';
                pa = {S.anchor,axes3(ad)}; pr = {S.roving(1),axes3(rd)};
                if S.rove == "hammer", args = {'Hammer',pr,'Sensor',pa}; else, args = {'Hammer',pa,'Sensor',pr}; end
                args = [args {'Zeta',zetaField.Value}];
            end
        end
        vil.exportAbaqus(S.db,fullfile(p,f),args{:});
        note = '';
        if isempty(args), note = ' (frequency step only; use +X/+Y/+Z directions to include the FRF step)'; end
        status.Text = "Wrote " + f + note;
    end

% ============================================================= picking ==
    function setPickMode(src,mode)
        buttons = pickButtons();
        set(buttons(buttons~=src),'Value',false);
        if src.Value
            if mode ~= "fixed" && isempty(S.db)
                src.Value = false; alert('Solve modes before choosing points.'); return
            end
            S.pickMode = mode; stopAnimation(); showUndeformed(); right.SelectedTab = tView;
            hints = struct('fixed',"Click faces to clamp or release them. Dragging only rotates.", ...
                'anchor',"Click the fixed point.",'roving',"Click each roving point. Dragging only rotates.", ...
                'monitor',"Click the point to monitor.");
            viewHint.Text = hints.(mode); viewHint.FontColor = C.accent;
        else
            clearPick();
        end
    end

    function b = pickButtons()
        b = [pickFixedBtn pickAnchorBtn pickRovingBtn pickMonitorBtn];
    end

    function clearPick()
        set(pickButtons(),'Value',false);
        S.pickMode = ""; viewHint.Text = 'Drag to rotate, scroll to zoom.'; viewHint.FontColor = C.muted;
    end

    % A pick happens on release, and only if the press did not turn into a
    % rotate: a drag starting on the part must never change the model.
    function onModelClick(~,evt)
        if S.pickMode == "", return, end
        S.press = struct('point',evt.IntersectionPoint,'pointer',fig.CurrentPoint,'view',ax3.View,'mode',S.pickMode);
        fig.WindowButtonUpFcn = @onModelRelease;
    end

    function onModelRelease(~,~)
        fig.WindowButtonUpFcn = '';
        p = S.press; S.press = [];
        if isempty(p) || p.mode ~= S.pickMode, return, end
        if norm(fig.CurrentPoint-p.pointer) > 4 || norm(ax3.View-p.view) > 0.1, return, end
        pickAt(p.point,p.mode);
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
            otherwise
                cand = S.db.surfaceNodes(~ismember(S.db.surfaceNodes,S.db.fixedNodes));
                [~,k] = min(vecnorm(S.db.nodes(:,cand)-point));
                if S.modeIndex > 0, showUndeformed(); end
                node = cand(k);
                switch mode
                    case "anchor", S.anchor = node; staleSurvey();
                    case "monitor", S.monitor = node;
                    case "roving"
                        if ~ismember(node,S.roving)
                            S.roving(end+1) = node; S.rovingDir{end+1} = rovingDirDrop.Value; staleSurvey();
                        end
                end
                drawProbes(); refreshUi();
                status.Text = sprintf('%s at node %d (%.1f, %.1f, %.1f) mm.',capitalize(mode),node,1e3*S.db.nodes(:,node));
        end
    end

    function removeRoving(which)
        S.roving(which) = []; S.rovingDir(which) = [];
        staleSurvey(); drawProbes(); refreshUi();
    end

    function staleSurvey()
        S.survey = []; clearResponse(); fillPointTable();
    end

    function onDirectionChanged()
        staleSurvey(); drawProbes();
    end

    function m = roveMode()
        m = "hammer"; if strcmp(roveDrop.Value,roveDrop.Items{2}), m = "sensor"; end
    end

    function setRove(mode)
        S.rove = string(mode);
        roveDrop.Value = roveDrop.Items{1+(S.rove=="sensor")};
        setRoveLabels();
        % The fixed point keeps its node and changes role, so its arrow flips.
        if S.rove == "hammer"
            anchorDir.Value = 'Out of surface'; rovingDirDrop.Value = 'Into surface';
        else
            anchorDir.Value = 'Into surface'; rovingDirDrop.Value = 'Out of surface';
        end
        S.rovingDir = repmat({rovingDirDrop.Value},1,numel(S.roving));
        staleSurvey(); drawProbes(); refreshUi();
    end

    function setRoveLabels()
        if S.rove == "hammer"
            anchorTitle.Text = 'FIXED ACCELEROMETER'; rovingTitle.Text = 'HAMMER POINTS';
            anchorLbl.FontColor = C.sensor; rovingLbl.FontColor = C.hammer;
        else
            anchorTitle.Text = 'FIXED HAMMER'; rovingTitle.Text = 'ACCELEROMETER POINTS';
            anchorLbl.FontColor = C.hammer; rovingLbl.FontColor = C.sensor;
        end
    end

    function setTip(name)
        name = char(name);
        if ~ismember(name,tipDrop.Items), setAdvanced(true); end
        tipDrop.Value = name;
        k = find(strcmp({tips.name},name));
        if ~isempty(k), contactField.Value = 1e3*tips(k).contact; end
        showBand();
    end

    function setContact(ms)
        setAdvanced(true); contactField.Value = ms; onContactTyped();
    end

    function onContactTyped()
        % A typed contact time is a tip of its own unless it matches one.
        k = find(abs(1e3*[tips.contact]-contactField.Value) < 1e-9,1);
        if isempty(k), tipDrop.Value = 'Custom'; else, tipDrop.Value = tips(k).name; end
        showBand();
    end

    function setAdvanced(on)
        advancedBox.Value = on;
        if ~on && ~ismember(tipDrop.Value,tipItems(false))
            % Back to the basic list: keep the nearest basic tip.
            basic = tips(ismember({tips.name},tipItems(false)));
            [~,k] = min(abs(log([basic.contact]/(contactField.Value/1e3))));
            tipDrop.Items = tipItems(false); setTip(basic(k).name);
        end
        tipDrop.Items = tipItems(on);
        parents = [advancedRows.Parent];
        rows = arrayfun(@(r)r.Layout.Row,parents);
        heights = impactGrid.RowHeight; heights(rows) = {30*on};
        impactGrid.RowHeight = heights;
        set(parents,'Visible',onoff(on));
    end

    function suggestTip()
        % The softest tip whose band still reaches the first three modes:
        % softer tips put more energy into the modes that matter.
        target = S.db.frequencyHz(min(3,numel(S.db.omega)));
        order = tips(ismember({tips.name},tipDrop.Items));
        [~,k] = sort([order.contact],'descend'); order = order(k);
        pick = order(end).name;
        for k = 1:numel(order)
            if 1.2/order(k).contact >= target, pick = order(k).name; break, end
        end
        setTip(pick);
    end

    function showBand()
        band = 1.2/(contactField.Value/1e3);
        if isempty(S.db)
            bandInfo.Text = sprintf('This hit excites 0 – %s.',hz(band)); bandInfo.FontColor = C.muted; return
        end
        n = nnz(S.db.frequencyHz <= band);
        bandInfo.Text = sprintf('Band 0 – %s: %d of %d modes inside.',hz(band),n,numel(S.db.omega));
        if n == 0
            bandInfo.Text = bandInfo.Text + " First mode " + hz(S.db.frequencyHz(1)) + ": use a harder tip.";
            bandInfo.FontColor = C.hammer;
        else
            bandInfo.FontColor = C.muted;
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
        showFixedInfo();
        colourFaces(); refreshUi();
    end

    function setBoundary(mode)
        mode = string(mode);
        if mode ~= S.boundary && ~isempty(S.db) && ~isempty(S.geom)
            invalidateModes('Boundary condition changed: solve modes again.');
        end
        S.boundary = mode;
        boundaryDrop.Value = boundaryItems(mode);
        if mode == "free", clearPick(); end
        syncBoundaryControls(); showFixedInfo(); colourFaces(); refreshUi();
    end

    function syncBoundaryControls()
        clamped = onoff(S.boundary == "clamped");
        set([pickFixedBtn clearFixedBtn facesField],'Enable',clamped);
    end

    function showFixedInfo()
        [nodes,tri,faceId] = surfaceData();
        if S.boundary == "free", fixedInfo.Text = 'Free-free: no face is fixed.'; fixedInfo.FontColor = C.muted; return, end
        if isempty(S.fixedFaces) || isempty(tri), fixedInfo.Text = 'No faces clamped.'; fixedInfo.FontColor = C.muted; return, end
        e = cross(nodes(:,tri(:,2))-nodes(:,tri(:,1)),nodes(:,tri(:,3))-nodes(:,tri(:,1)));
        area = vecnorm(e).'; pct = 100*sum(area(ismember(faceId,S.fixedFaces)))/sum(area);
        fixedInfo.Text = sprintf('%d face(s) clamped: %.0f%% of the part surface.',numel(S.fixedFaces),pct);
        % Clamping much of the surface stiffens the part far beyond a real fixture.
        if pct > 35, fixedInfo.FontColor = C.hammer; else, fixedInfo.FontColor = C.muted; end
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
        clamped = ismember(faceId,S.fixedFaces) & S.boundary == "clamped";
        col(clamped,:) = repmat(C.fixed,nnz(clamped),1);
        H.patch.FaceColor = 'flat'; H.patch.FaceVertexCData = col;
        H.patch.Vertices = surfaceNodesMatrix().';
    end

    function drawProbes()
        if isfield(H,'probes'), delete(H.probes(isgraphics(H.probes))); end
        H.probes = gobjects(0);
        if isempty(S.db) || ~isfield(H,'patch'), return, end
        L = 0.12*max(spanOf(S.db.nodes));
        isHammer = S.rove == "hammer";
        drawProbe(S.anchor,anchorDir.Value,~isHammer,L,'Fixed');
        for k = 1:numel(S.roving)
            drawProbe(S.roving(k),S.rovingDir{k},isHammer,0.6*L,string(k));
        end
        if ~isempty(S.monitor)
            x = S.db.nodes(:,S.monitor);
            H.probes(end+1) = plot3(ax3,x(1),x(2),x(3),'d','MarkerSize',9,'MarkerFaceColor',C.accent, ...
                'MarkerEdgeColor','w','LineWidth',1.2,'PickableParts','none');
        end
    end

    function drawProbe(node,choice,hammer,L,name)
        if isempty(node), return, end
        col = C.sensor; if hammer, col = C.hammer; end
        if ~isempty(S.survey)
            k = find(S.roving==node,1);
            if ~isempty(k) && name ~= "Fixed" && ~S.survey.use(k), col = C.rejected; end
        end
        x = S.db.nodes(:,node); d = probeDirection(node,choice); d = d(:)/norm(d);
        if hammer, tail = x-L*d; lp = tail; else, tail = x; lp = x+L*d; end
        H.probes(end+1) = quiver3(ax3,tail(1),tail(2),tail(3),L*d(1),L*d(2),L*d(3),0, ...
            'Color',col,'LineWidth',2.2,'MaxHeadSize',0.6,'PickableParts','none');
        H.probes(end+1) = plot3(ax3,x(1),x(2),x(3),'o','MarkerSize',7,'MarkerFaceColor',col, ...
            'MarkerEdgeColor','w','LineWidth',1.2,'PickableParts','none');
        H.probes(end+1) = text(ax3,lp(1),lp(2),lp(3),"  "+name,'Color',col, ...
            'FontWeight','bold','PickableParts','none');
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
            H.timer = timer('Tag','vilAnimation','ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
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

    function showSurvey()
        fillPointTable(); fillModalTable(); plotSurvey(); drawProbes(); refreshUi();
    end

    function fillPointTable()
        n = numel(S.roving);
        rows = cell(n,5);
        for k = 1:n
            level = '—'; use = true;
            if ~isempty(S.survey), level = sprintf('%.1f',S.survey.levelDb(k)); use = S.survey.use(k); end
            rows(k,:) = {k,S.roving(k),S.rovingDir{k},level,use};
        end
        pointTable.Data = rows;
    end

    function fillModalTable()
        q = S.survey; m = q.modes; n = numel(m.frequencyHz);
        rows = cell(n,7);
        for k = 1:n
            rows(k,:) = {k,sprintf('%.2f',m.frequencyHz(k)),sprintf('%.3f',100*m.zeta(k)),numOrDash('%d',m.feMode(k)), ...
                numOrDash('%.2f',m.feHz(k)),numOrDash('%.4f',m.errorPct(k)),numOrDash('%.3f',m.mac(k))};
        end
        modalTable.Data = rows;
        nUsed = nnz(q.use); nDrop = numel(q.use)-nUsed;
        modalSummary.Text = sprintf('%d natural frequencies identified from %d FRF(s) over 0 – %.0f Hz.',n,nUsed,q.bandHz);
        notes = strings(0,1);
        if nDrop > 0
            bad = find(~q.use).';
            notes(end+1) = sprintf('Removed %d response(s) (point %s): more than %.0f dB below the median, or switched off.', ...
                nDrop,strjoin(string(bad),', '),q.rejectDb);
        end
        if ~isempty(m.missing)
            weak = [m.missing.weak];
            names = compose('%.0f Hz',[m.missing.frequencyHz]);
            if any(weak), notes(end+1) = "Not seen: " + strjoin(names(weak),', ') + ". The chosen points sit near nodes of these modes; move the fixed point."; end
            if any(~weak), notes(end+1) = "Not separated: " + strjoin(names(~weak),', ') + ". Too close to a neighbouring mode for this set of points."; end
        end
        if m.aboveBand > 0
            notes(end+1) = sprintf('%d FE mode(s) lie above the %.0f Hz band this %.3g ms hit excites; shorten the contact time to reach them.', ...
                m.aboveBand,q.bandHz,1e3*q.parameters.contactDuration);
        end
        if isfinite(q.tau)
            notes(end+1) = sprintf('Exponential window applied (record too short to ring down); its %.2f /s decay is removed from the damping.',1/q.tau);
        end
        modalNotes.Text = strjoin(notes,newline);
        status.Text = sprintf('Test done: %d of %d responses used, %d modes identified.',nUsed,numel(q.use),n);
    end

    function plotSurvey()
        clearPlots();
        q = S.survey; f = q.frequencyHz; n = numel(q.use);
        ms = 1e3*q.time; step = max(1,ceil(numel(ms)/8000));
        nameRole = 'H'; if q.rove == "sensor", nameRole = 'S'; end
        for k = 1:n
            if q.use(k)
                args = {'Color',C.series(mod(k-1,size(C.series,1))+1,:),'LineWidth',1.1};
            else
                args = {'Color',C.rejected,'LineStyle','--','LineWidth',0.9};
            end
            args = [args {'DisplayName',sprintf('%s%d node %d',nameRole,k,S.roving(k))}]; %#ok<AGROW>
            plot(axR(1),f,abs(q.H(k,:)),args{:});
            if q.use(k), plot(axR(2),f,angle(q.H(k,:))*180/pi,args{:}); end
            plot(axR(4),ms(1:step:end),q.acceleration(k,1:step:end),args{:});
        end
        plot(axR(3),ms,q.force,'Color',C.hammer,'LineWidth',1.3);
        xlim(axR(3),[0 3*1e3*q.parameters.contactDuration]);
        tEnd = min(ms(end),max(ms(end)/4,20*1e3*q.parameters.contactDuration));
        xlim(axR(4),[0 tEnd]);
        plot(axR(5),f,q.forceSpectrum/max(q.forceSpectrum),'Color',C.hammer,'LineWidth',1.3);
        xline(axR(5),q.bandHz,'--','Band limit');
        data = abs(q.H(q.use,:)); fit = abs(q.modes.fit);
        plot(axR(6),f,sum(data,1),'Color',C.series(1,:),'LineWidth',1.4,'DisplayName','FRFs');
        plot(axR(6),f,sum(fit,1),'--','Color',C.series(2,:),'LineWidth',1.1,'DisplayName','Fit');
        xline(axR(6),q.modes.frequencyHz,':','Color',[0.6 0.6 0.6],'HandleVisibility','off');
        xline(axR(1),q.modes.frequencyHz,':','Color',[0.6 0.6 0.6],'HandleVisibility','off');
        if n <= 8, legend(axR(1),'Location','best','FontSize',8,'Box','off'); end
        legend(axR(6),'Location','best','FontSize',8,'Box','off');
    end

    function clearPlots()
        for a = axR.', cla(a); legend(a,'off'); end
    end

    function clearResponse()
        clearPlots();
        modalTable.Data = {}; modalNotes.Text = '';
        modalSummary.Text = 'Run a test to identify natural frequencies and damping from the FRFs.';
    end

    function applyFlightPreset()
        p = vil.flightProfile(flightDrop.Value);
        rpmLoField.Value = p.rpmRange(1); rpmHiField.Value = p.rpmRange(2); rpmField.Value = p.rpm;
        toneTable.Data = [cellstr(p.source) num2cell(p.order) num2cell(p.amplitudeG)];
        psdTable.Data = p.psd;
    end

    function showFlight()
        r = S.flight; c = r.config;
        for a = axF.', cla(a); legend(a,'off'); end
        % Campbell diagram.
        cols = C.series;
        for k = 1:numel(c.order)
            plot(axF(1),c.rpmRange,c.order(k)*c.rpmRange/60,'Color',cols(mod(k-1,size(cols,1))+1,:),'LineWidth',1.3, ...
                'DisplayName',sprintf('%g× shaft',c.order(k)));
        end
        top = 1.3*max(c.order)*c.rpmRange(2)/60;
        show = r.naturalHz<=top;
        if any(show), yline(axF(1),r.naturalHz(show),'-','Color',[0.55 0.55 0.6],'HandleVisibility','off'); end
        xline(axF(1),c.rpm,'--','Cruise','HandleVisibility','off');
        ylim(axF(1),[0 top]); xlim(axF(1),c.rpmRange+[-1 1]*max(1,0.02*c.rpmRange(2)));
        cross = ~isnan(r.crossingRpm) & r.excited;
        if any(cross)
            plot(axF(1),r.crossingRpm(cross),r.naturalHz(cross),'o','MarkerFaceColor',C.hammer,'MarkerEdgeColor','w','MarkerSize',8,'DisplayName','Crossing');
        end
        legend(axF(1),'Location','northwest','FontSize',8,'Box','off');
        plot(axF(2),r.rpmSweep,r.sweepG,'Color',C.series(1,:),'LineWidth',1.3);
        xline(axF(2),c.rpm,'--','Cruise');
        plot(axF(3),r.frequencyHz,abs(r.T),'Color',C.series(1,:),'LineWidth',1.2);
        if any(r.toneHz>0), xline(axF(3),r.toneHz,':','Color',C.hammer); end
        plot(axF(4),r.frequencyHz(r.inputPsd>0),r.inputPsd(r.inputPsd>0),'Color',C.muted,'LineWidth',1.2,'DisplayName',sprintf('Input %.2f g rms',r.inputRmsG));
        plot(axF(4),r.frequencyHz(r.outputPsd>0),r.outputPsd(r.outputPsd>0),'Color',C.series(2,:),'LineWidth',1.2,'DisplayName',sprintf('Response %.2f g rms',r.outputRmsG));
        legend(axF(4),'Location','best','FontSize',8,'Box','off');
        plot(axF(5),1e3*r.time,r.baseG,'Color',C.muted,'LineWidth',1,'DisplayName','Clamp');
        plot(axF(5),1e3*r.time,r.responseG,'Color',C.series(2,:),'LineWidth',1.2,'DisplayName','Monitor');
        legend(axF(5),'Location','best','FontSize',8,'Box','off');
        rows = cell(numel(r.naturalHz),6);
        for k = 1:numel(r.naturalHz)
            rows(k,:) = {k,sprintf('%.1f',r.naturalHz(k)),sprintf('%.2f',r.effectiveMassPct(k)), ...
                sprintf('%.1f',r.marginPct(k)),numOrDash('%.0f',r.crossingRpm(k)),char(r.status(k))};
        end
        flightTable.Data = rows;
        nRes = nnz(r.status=="RESONANCE at cruise"); nCross = nnz(r.status=="Crossed in RPM range");
        if nRes > 0
            flightVerdict.Text = sprintf('RESONANCE: %d mode(s) within ±%g%% of a tone at cruise.',nRes,c.marginPct);
            flightVerdict.FontColor = C.hammer;
        elseif nCross > 0
            flightVerdict.Text = sprintf('Clear at cruise, but %d mode(s) are crossed between %g and %g RPM.',nCross,c.rpmRange);
            flightVerdict.FontColor = C.warn;
        else
            flightVerdict.Text = 'No resonance: tones stay clear of every excited mode.';
            flightVerdict.FontColor = C.chipOn;
        end
        status.Text = sprintf('Flight: tones %.3g g at clamp → %.3g g at monitor; random %.3g → %.3g g rms. Levels are the values in the tables.', ...
            r.peakBaseG,r.peakResponseG,r.inputRmsG,r.outputRmsG);
        if r.tonesAboveModes
            status.Text = status.Text + " Highest tone is near the top solved mode: solve more modes.";
        end
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

    function d = probeDirection(node,choice)
        switch string(choice)
            case "Into surface"
                d = -vil.surfaceNormal(S.db.nodes,S.db.surfaceFaces,node);
            case "Out of surface"
                d = vil.surfaceNormal(S.db.nodes,S.db.surfaceFaces,node);
            otherwise
                axisIdx = find('XYZ'==extractAfter(choice,1));
                d = zeros(3,1); d(axisIdx) = 1;
                if startsWith(choice,'-'), d = -d; end
        end
        d = d(:).';
    end

    function defaultProbes()
        % Fixed and monitor points start on the free surface farthest from the clamp.
        cand = S.db.surfaceNodes(~ismember(S.db.surfaceNodes,S.db.fixedNodes));
        % Free-free: farthest from the centroid instead.
        if isempty(S.db.fixedNodes), clamp = mean(S.db.nodes,2); else, clamp = mean(S.db.nodes(:,S.db.fixedNodes),2); end
        X = S.db.nodes(:,cand);
        [~,i] = max(vecnorm(X-clamp));
        S.anchor = cand(i); S.monitor = cand(i); S.roving = []; S.rovingDir = {};
        fillPointTable();
        drawModel();
    end

    function fillModeTable()
        modeTable.Data = table((1:numel(S.db.omega)).',compose("%.2f",S.db.frequencyHz(:)), ...
            compose("residual %.0e",S.db.eigenResidual(:)),'VariableNames',{'Mode','Frequency (Hz)','Check'});
    end

    function clearPoints()
        S.survey = []; S.flight = []; S.anchor = []; S.monitor = []; S.roving = []; S.rovingDir = {};
        modeTable.Data = table(); pointTable.Data = {}; flightTable.Data = {}; flightVerdict.Text = '';
        clearResponse();
    end

    function resetModel()
        stopAnimation(); clearPick();
        S.db = []; S.modeIndex = 0; clearPoints();
        solveInfo.Text = solveHint;
        updatePartInfo(); refreshUi();
    end

    function invalidateModes(msg)
        S.db = []; S.modeIndex = 0; clearPoints();
        solveInfo.Text = solveHint; status.Text = msg; drawModel(); refreshUi();
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
        state = [~isempty(S.info), ~isempty(S.geom) || ~isempty(S.db), ~isempty(S.db), ~isempty(S.survey)];
        labels = ["Part","Mesh","Modes","Test"];
        if state(3), labels(3) = sprintf("%d modes",numel(S.db.omega)); end
        if state(4), labels(4) = sprintf("%d of %d used",nnz(S.survey.use),numel(S.survey.use)); end
        for k = 1:4
            chips(k).Text = labels(k);
            if state(k), chips(k).BackgroundColor = C.chipOn; chips(k).FontColor = 'w';
            else, chips(k).BackgroundColor = C.chipOff; chips(k).FontColor = C.headerMuted; end
        end
        btnMesh.Enable = onoff(~isempty(S.rawGeom) || S.source == "Demo cantilever");
        btnSolve.Enable = onoff(~isempty(S.geom) && (S.boundary == "free" || ~isempty(S.fixedFaces)));
        btnRun.Enable = onoff(~isempty(S.db) && ~isempty(S.anchor) && ~isempty(S.roving));
        btnFlight.Enable = onoff(~isempty(S.db) && ~isempty(S.monitor) && ~isempty(S.db.fixedNodes));
        if ~isempty(S.anchor), anchorLbl.Text = "Node " + S.anchor; else, anchorLbl.Text = 'Node —'; end
        if ~isempty(S.monitor), monitorLbl.Text = "Node " + S.monitor; else, monitorLbl.Text = 'Node —'; end
        rovingLbl.Text = sprintf('%d point(s)',numel(S.roving));
        showBand();
        if isempty(S.survey), fillPointTable(); end
    end

    function onMaterial(~,~)
        m = materials(strcmp([materials.name],matDrop.Value));
        if isempty(m.E), return, end
        EField.Value = m.E/1e9; nuField.Value = m.nu; rhoField.Value = m.rho;
        zetaField.Value = m.zeta; flightZetaField.Value = m.zeta;
        if ~isempty(S.db) && ~isempty(S.geom), invalidateModes('Material changed: solve modes again.'); end
        if strlength(m.note) > 0, status.Text = m.name + ": " + m.note; end
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
        tabs = struct('part',tPart,'solve',tSolve,'modes',tModes,'impact',tImpact,'flight',tFlight,'project',tProject);
        views = struct('model',tView,'response',tResp,'modal',tModal,'flightplots',tFlightPlots,'verification',tVer);
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

    function l = section(g,text,rowIndex)
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
    'rejected',[0.68 0.70 0.73],'warn',[0.78 0.50 0.05], ...
    'series',[0.12 0.42 0.78; 0.85 0.33 0.10; 0.10 0.62 0.38; 0.55 0.25 0.70; 0.90 0.62 0.05; 0.30 0.30 0.30]);
end

function m = materialPresets()
% Typical room-temperature values; replace them with supplier data. The
% solver is isotropic, so composites are quasi-isotropic laminate
% equivalents ([0/45/-45/90]s in-plane stiffness) and AM metals are
% as-built laser powder-bed fusion (LPBF) averages. zeta is a typical
% damping ratio for the hammer and flight fields.
mk = @(name,E,nu,rho,zeta,note) struct('name',string(name),'E',E,'nu',nu,'rho',rho,'zeta',zeta,'note',string(note));
iso = "Quasi-isotropic laminate equivalent: in-plane stiffness only. Through-thickness and ply-level effects are not modelled.";
am = "As-built LPBF average. Build direction, heat treatment and porosity shift E by several percent.";
m = [mk('Structural steel',210e9,0.30,7850,0.01,""), mk('Stainless steel 304',193e9,0.29,8000,0.01,""), ...
     mk('Aluminium 6061-T6',68.9e9,0.33,2700,0.01,""), mk('Titanium Ti-6Al-4V',113.8e9,0.342,4430,0.01,""), ...
     mk('Aero Al 2024-T3',73.1e9,0.33,2780,0.01,""), mk('Aero Al 7075-T6',71.7e9,0.33,2810,0.01,""), ...
     mk('Aero Al 7050-T7451',71.7e9,0.33,2830,0.01,""), ...
     mk('CFRP T300/epoxy (quasi-iso)',50e9,0.30,1550,0.02,iso), mk('CFRP IM7/epoxy (quasi-iso)',60e9,0.30,1580,0.02,iso), ...
     mk('GFRP E-glass/epoxy (quasi-iso)',20e9,0.28,1900,0.02,iso), ...
     mk('AM Ti-6Al-4V (LPBF)',110e9,0.34,4410,0.01,am), mk('AM AlSi10Mg (LPBF)',70e9,0.33,2670,0.01,am), ...
     mk('AM Inconel 718 (LPBF)',200e9,0.29,8190,0.01,am), mk('AM 316L (LPBF)',190e9,0.30,7950,0.01,am), ...
     mk('AM PA12 (SLS nylon)',1.7e9,0.39,1010,0.03,"Polymer: stiffness depends on temperature and moisture; damping is high."), ...
     mk('Custom',[],[],[],[],"")];
end

function items = boundaryItems(mode)
% With a mode, returns the dropdown item for it.
items = {'Clamped faces','Free-free'};
if nargin > 0, items = items{1+(string(mode)=="free")}; end
end

function m = boundaryMode(item)
m = "clamped"; if strcmp(item,'Free-free'), m = "free"; end
end

function t = hammerTips()
% Typical half-sine contact times on a metal part. The band reaches about
% 1.2/contact time (half-sine 15 dB down).
mk = @(name,ms) struct('name',name,'contact',ms/1e3);
t = [mk('Rubber',1.0), mk('Plastic',0.3), mk('Aluminium',0.12), mk('Steel',0.05)];
end

function items = tipItems(advanced)
if advanced, items = {'Rubber','Plastic','Aluminium','Steel','Custom'}; else, items = {'Rubber','Steel'}; end
end

function s = hz(f)
if f >= 1e3, s = sprintf('%.3g kHz',f/1e3); else, s = sprintf('%.3g Hz',f); end
end

function items = directionItems()
items = {'Into surface','Out of surface','+X','-X','+Y','-Y','+Z','-Z'};
end

function items = roveItems()
items = {'Roving hammer, fixed accelerometer','Roving accelerometer, fixed hammer'};
end

function names = vilFlightNames()
[~,names] = vil.flightProfile();
names = cellstr(names);
end

function s = numOrDash(format,v)
if isnan(v), s = '—'; else, s = sprintf(format,v); end
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
