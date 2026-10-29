function VirtualImpactLab
% Programmatic UI; all numerical work lives in +vil.
model=[]; db=[]; tests={}; c=[];
fig=uifigure('Name','Virtual Impact Lab','Position',[40 40 1250 820]);
g=uigridlayout(fig,[2 1]); g.RowHeight={30,'1x'};
status=uilabel(g,'Text','No modal solution. Damping is assumed, not measured.');
tg=uitabgroup(g);
a=uitab(tg,'Title','Geometry'); b=uitab(tg,'Title','FE Setup');
d=uitab(tg,'Title','Modes'); e=uitab(tg,'Title','Impact Lab');
rt=uitab(tg,'Title','Results');
g1=uigridlayout(a,[3 2]); g1.RowHeight={35,35,'1x'};
uibutton(g1,'Text','Demo beam','ButtonPushedFcn',@beam);
uibutton(g1,'Text','Import STEP','ButtonPushedFcn',@cad);
uilabel(g1,'Text','CAD scale to metres (mm = 0.001)');
scaleField=uieditfield(g1,'numeric','Value',0.001,'Limits',[eps Inf]);
ax=uiaxes(g1); ax.Layout.Column=[1 2];
g2=uigridlayout(b,[9 2]);
uilabel(g2,'Text','Young modulus (Pa)'); E=uieditfield(g2,'numeric','Value',210e9);
uilabel(g2,'Text','Poisson ratio'); nu=uieditfield(g2,'numeric','Value',0.3);
uilabel(g2,'Text','Density (kg/m^3)'); rho=uieditfield(g2,'numeric','Value',7800);
uilabel(g2,'Text','Fixed face ID'); face=uieditfield(g2,'numeric','Value',1,'RoundFractionalValues','on');
uilabel(g2,'Text','Maximum element size (m)'); hm=uieditfield(g2,'numeric','Value',0.008);
uilabel(g2,'Text','Minimum modal frequency (Hz)'); lo=uieditfield(g2,'numeric','Value',1);
uilabel(g2,'Text','Maximum modal frequency (Hz)'); hi=uieditfield(g2,'numeric','Value',2000);
uibutton(g2,'Text','Mesh and solve modes','ButtonPushedFcn',@solveModel);
uibutton(g2,'Text','Save project','ButtonPushedFcn',@saveData);
uibutton(g2,'Text','Load project','ButtonPushedFcn',@loadData);
controls={E,nu,rho,face,hm,lo,hi};
for k=1:numel(controls), controls{k}.ValueChangedFcn=@invalidate; end
md=uigridlayout(d,[2 2]); md.RowHeight={40,'1x'};
mode=uieditfield(md,'numeric','Value',1,'Limits',[1 Inf],'RoundFractionalValues','on');
uibutton(md,'Text','Plot selected mode','ButtonPushedFcn',@showMode);
tableModes=uitable(md); modeAxes=uiaxes(md);
gi=uigridlayout(e,[10 2]);
uilabel(gi,'Text','Hammer surface node ID'); hn=uieditfield(gi,'numeric','Value',1);
uilabel(gi,'Text','Sensor surface node ID'); sn=uieditfield(gi,'numeric','Value',1);
uilabel(gi,'Text','Hammer direction'); hd=uidropdown(gi,'Items',{'X','Y','Z'},'Value','Z');
uilabel(gi,'Text','Sensor direction'); sd=uidropdown(gi,'Items',{'X','Y','Z'},'Value','Z');
uilabel(gi,'Text','Assumed damping ratio'); damp=uieditfield(gi,'numeric','Value',0.01);
uilabel(gi,'Text','Peak force (N)'); force=uieditfield(gi,'numeric','Value',100);
uilabel(gi,'Text','Contact duration (s)'); contact=uieditfield(gi,'numeric','Value',0.001);
uilabel(gi,'Text','Simulation duration (s)'); dur=uieditfield(gi,'numeric','Value',1);
uilabel(gi,'Text','Sample rate (Hz)'); fs=uieditfield(gi,'numeric','Value',25000);
uibutton(gi,'Text','Run cached virtual test','ButtonPushedFcn',@impact);
uibutton(gi,'Text','List surface nodes','ButtonPushedFcn',@listNodes);
gr=uigridlayout(rt,[3 2]); axesResults=gobjects(6,1);
for k=1:6, axesResults(k)=uiaxes(gr); end
    function invalidate(~,~)
        db=[]; tests={}; status.Text='Model changed: modal recalculation required.';
    end
    function beam(~,~)
        protect(@action);
        function action
            [model,c]=vil.createDemoBeam; face.Value=c.fixedFaces;
            invalidate; pdegplot(model.Geometry,'FaceLabels','on','Parent',ax);
        end
    end
    function cad(~,~)
        [f,p]=uigetfile({'*.step;*.stp','STEP solid'}); if isequal(f,0), return; end
        protect(@action);
        function action
            model=vil.importCAD(fullfile(p,f),scaleField.Value); c=struct('source',f,'scaleToMetres',scaleField.Value);
            invalidate; pdegplot(model.Geometry,'FaceLabels','on','Parent',ax);
        end
    end
    function solveModel(~,~)
        protect(@action);
        function action
            assert(~isempty(model),'Create a beam or import STEP first.');
            db=[]; tests={}; status.Text='Solving modes...'; drawnow;
            c.E=E.Value; c.nu=nu.Value; c.rho=rho.Value; c.fixedFaces=face.Value;
            c.hmax=hm.Value; c.rangeHz=[lo.Value hi.Value];
            % Reconstruct to remove previous boundary conditions.
            model=femodel(AnalysisType="structuralModal",Geometry=model.Geometry);
            status.Text='Applying material, boundary conditions and generating mesh...'; drawnow;
            model=vil.setupModel(model,c);
            status.Text='Solving modes and building modal database...'; drawnow;
            db=vil.solveModes(model,c);
            tableModes.Data=table((1:numel(db.omega)).',db.frequencyHz,'VariableNames',{'Mode','Hz'});
            hn.Value=db.surfaceNodes(end); sn.Value=db.surfaceNodes(end);
            status.Text='Modal cache available; impact changes reuse it. Damping is assumed.';
        end
    end
    function showMode(~,~)
        protect(@action);
        function action
            assert(~isempty(db),'Solve or load modes first.'); k=mode.Value;
            assert(k<=numel(db.omega),'Mode index exceeds available modes.');
            n=size(db.nodes,2); displacement=reshape(db.Phi(:,k),n,3).';
            amplitude=max(vecnorm(displacement)); factor=0.05*max(range(db.nodes,2))/max(amplitude,eps);
            xyz=db.nodes+factor*displacement;
            trisurf(db.surfaceFaces,xyz(1,:),xyz(2,:),xyz(3,:),vecnorm(displacement),'Parent',modeAxes,'EdgeColor','none');
            axis(modeAxes,'equal'); title(modeAxes,sprintf('Mode %d: %.2f Hz (scaled)',k,db.frequencyHz(k)));
        end
    end
    function listNodes(~,~)
        if isempty(db), return; end
        w=uifigure('Name','Selectable exterior corner nodes');
        t=uitable(w,'Data',[db.surfaceNodes db.nodes(:,db.surfaceNodes).'],'ColumnName',{'ID','X (m)','Y (m)','Z (m)'});
        t.Position=[10 10 540 390];
    end
    function impact(~,~)
        protect(@action);
        function action
            assert(~isempty(db),'Solve or load modes first.');
            h={hn.Value,hd.Value}; s={sn.Value,sd.Value};
            p=struct('peakForce',force.Value,'contactDuration',contact.Value,'duration',dur.Value,'fs',fs.Value,'zeta',damp.Value);
            response=vil.simulateImpact(db,h,s,p);
            frf=vil.calculateFRF(db,h,s,linspace(0,0.7*max(db.frequencyHz),2001),damp.Value);
            tests{end+1}=struct('response',response,'frf',frf);
            label=sprintf('Test %d',numel(tests));
            for q=1:6, hold(axesResults(q),'on'); end
            plot(axesResults(1),frf.frequencyHz,abs(frf.accelerance),'DisplayName',label);
            plot(axesResults(2),frf.frequencyHz,angle(frf.accelerance)*180/pi,'DisplayName',label);
            plot(axesResults(3),response.time,response.force,'DisplayName',label);
            plot(axesResults(4),response.time,response.acceleration,'DisplayName',label);
            plot(axesResults(5),response.spectrumHz,response.accelerationSpectrum,'DisplayName',label);
            plot(axesResults(6),response.time,response.displacement,'DisplayName',label);
            names={'Accelerance ((m/s^2)/N)','Phase (deg)','Force (N)','Acceleration (m/s^2)','Acceleration amplitude (m/s^2)','Displacement (m)'};
            for q=1:6, ylabel(axesResults(q),names{q}); legend(axesResults(q),'show'); grid(axesResults(q),'on'); end
            for q=[1 2 5], xlabel(axesResults(q),'Frequency (Hz)'); end
            for q=[3 4 6], xlabel(axesResults(q),'Time (s)'); end
            tg.SelectedTab=rt;
        end
    end
    function saveData(~,~)
        if isempty(db), return; end
        [f,p]=uiputfile('*.mat'); if ~isequal(f,0), protect(@()vil.saveProject(fullfile(p,f),db,tests)); end
    end
    function loadData(~,~)
        [f,p]=uigetfile('*.mat'); if isequal(f,0), return; end
        protect(@action);
        function action
            [db,tests]=vil.loadProject(fullfile(p,f)); model=[]; c=db.config;
            tableModes.Data=table((1:numel(db.omega)).',db.frequencyHz,'VariableNames',{'Mode','Hz'});
            hn.Value=db.surfaceNodes(end); sn.Value=db.surfaceNodes(end);
            status.Text='Loaded modal cache; impact engine ready. Import geometry again to remesh.';
        end
    end
    function protect(action)
        try
            action();
        catch err
            report=getReport(err,'extended','hyperlinks','off');
            fprintf(2,'%s\n',report);
            status.Text=err.message;
            uialert(fig,report,'Virtual Impact Lab error');
        end
    end
end
