function T = reproducePayloadStudy(studyRoot,opts)
% Re-solve the antenna-carrier payload study through the app (no study scripts):
% the same ready TetGen meshes, AlSi10Mg (E 70 GPa, nu 0.33, rho 2670),
% clamp Ux=Uy=Uz=0 on Z = 0 mm +/- 0.05 mm, payload on Z = 80 mm +/- 0.05 mm,
% payload masses 0.5 and 1.0 kg, each a full eigen solve (mass sweep).
% studyRoot: the Yorulma folder. Writes payload_reproduction.csv there in
% verification/results and returns the table with the stored values beside.
arguments
    studyRoot (1,1) string
    opts.Names string = ["reference" "gyroid_r5_c10_t08" "schwarz_r5_c10_t08"]
    opts.Out (1,1) string = fullfile(fileparts(mfilename('fullpath')),'results')
    opts.SaveProjects (1,1) string = ""   % folder: also solve each mass in the GUI and save the projects
end
addpath(fileparts(fileparts(mfilename('fullpath'))));
expected = struct('reference',[914.21 657.58],'gyroid_r5_c10_t08',[266.69 190.38],'schwarz_r5_c10_t08',[384.76 275.23]);
rows = {};
for name = opts.Names
    if name == "reference"
        % The reference mesh exists only inside its project (linear tetrahedra).
        meshFile = fullfile(studyRoot,'variants_hollow','projects',name+"_VIL.mat");
    else
        meshFile = fullfile(studyRoot,'variants_hollow','cad',name+"_tetmesh.mat");
    end
    old05 = vil.loadProject(fullfile(studyRoot,'variants_hollow','projects',name+"_VIL.mat"));
    old10 = vil.loadProject(fullfile(studyRoot,'sunum_v2','payload',name+"_1kg_VIL.mat"));
    app = VirtualImpactLab; cleanup = onCleanup(@()close(app.figure));
    t0 = tic;
    app.importMesh(meshFile,"auto");
    s = app.state(); assert(isempty(s.lastError),'%s import: %s',name,errText(s));
    app.setMaterial('AM AlSi10Mg (LPBF)');
    app.setSupport(struct('boundary',"clamped",'method',"plane",'axis',3,'positionMm',0,'toleranceMm',0.05));
    app.setPayload(struct('enabled',true,'massKg',0.5,'method',"plane",'axis',3,'positionMm',80,'toleranceMm',0.05));
    s = app.state();
    sameFixed = isequal(sort(s.support.nodes(:)),sort(old05.fixedNodes(:)));
    sameTip = isequal(sort(s.payload.nodes(:)),sort(old05.payload.nodes(:)));
    app.runSweep([0.5 1.0]);
    s = app.state(); assert(isempty(s.lastError),'%s sweep: %s',name,errText(s));
    R = s.sweep.table;
    e = expected.(name);
    rows(end+1,:) = {name,s.meshInfo.order,s.meshInfo.numNodes,s.meshInfo.numElements,string(s.info.fileUnits), ...
        numel(s.support.nodes),sameFixed,numel(s.payload.nodes),sameTip, ...
        1e3*R.StructureMass_kg(1),1e3*old05.structureMass, ...
        R.f1_Hz(1),old05.frequencyHz(1),e(1),100*(R.f1_Hz(1)/old05.frequencyHz(1)-1), ...
        R.f1_Hz(2),old10.frequencyHz(1),e(2),100*(R.f1_Hz(2)/old10.frequencyHz(1)-1), ...
        max(R.MaxEigenResidual),toc(t0)}; %#ok<AGROW>
    fprintf('%s: f1(0.5 kg) %.4f Hz (stored %.4f), f1(1.0 kg) %.4f Hz (stored %.4f), %.0f s\n', ...
        name,R.f1_Hz(1),old05.frequencyHz(1),R.f1_Hz(2),old10.frequencyHz(1),toc(t0));
    if ~isfolder(opts.Out), mkdir(opts.Out); end
    app.exportSweep(fullfile(opts.Out,name+"_payload_sweep.csv"));
    app.snapshot(fullfile(opts.Out,name+"_sweep_gui.png"));
    if strlength(opts.SaveProjects) > 0
        % The GUI's own Solve modes + Save project for each mass (8 modes, as
        % in the study). The solver input files are written by makeImportFiles.
        P = opts.SaveProjects; if ~isfolder(P), mkdir(P); end
        app.setModes(8,0);
        for kg = [0.5 1.0]
            app.setPayload(struct('enabled',true,'massKg',kg));
            app.solve(); s = app.state(); assert(isempty(s.lastError),'%s solve: %s',name,errText(s));
            file = fullfile(P,name+sprintf("_%gkg_VIL.mat",kg));
            app.saveProject(file);
            chk = vil.loadProject(file);
            fprintf('saved %s: f1 %.4f Hz (sweep %.4f)\n',file,chk.frequencyHz(1),R.f1_Hz(R.Payload_kg==kg));
            assert(abs(chk.frequencyHz(1)/R.f1_Hz(R.Payload_kg==kg)-1) < 1e-9,'Saved project differs from the sweep.');
        end
    end
    clear cleanup old05 old10
end
T = cell2table(rows,'VariableNames',{'Model','MeshOrder','Nodes','Elements','MeshUnits', ...
    'SupportNodes','SupportNodesMatchStored','PayloadNodes','PayloadNodesMatchStored', ...
    'CarrierMass_g','StoredCarrierMass_g', ...
    'f1_0p5kg_Hz','Stored_0p5kg_Hz','Expected_0p5kg_Hz','Diff_0p5kg_pct', ...
    'f1_1p0kg_Hz','Stored_1p0kg_Hz','Expected_1p0kg_Hz','Diff_1p0kg_pct','MaxEigenResidual','Time_s'});
writetable(T,fullfile(opts.Out,'payload_reproduction.csv'));
disp(T);
end

function s = errText(state)
s = ''; if ~isempty(state.lastError), s = state.lastError.message; end
end
