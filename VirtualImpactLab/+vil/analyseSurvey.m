function s = analyseSurvey(db,s,opts)
% Reject weak responses, identify modes from the FRFs that remain and compare
% them with the FE modes. Use = [] decides automatically; a logical vector
% overrides the automatic choice.
arguments
    db struct
    s struct
    opts.RejectDb (1,1) double = 20
    opts.Use = []
end
level=sqrt(mean(abs(s.H).^2,2));
assert(any(level>0),'vil:NoResponse','No response at any point: are they all on the clamp?');
s.levelDb=20*log10(level/median(level(level>0)));
s.autoUse=s.levelDb>=-opts.RejectDb;
s.rejectDb=opts.RejectDb;
if isempty(opts.Use), s.use=s.autoUse; else, s.use=logical(opts.Use(:)); end
assert(any(s.use),'vil:NoResponse','Every response is switched off; keep at least one.');
id=vil.identifyModes(s.frequencyHz,s.H(s.use,:),s.tau);
% Compare with the FE modes the survey retained.
fe=db.frequencyHz(s.modeKeep); fe=fe(:);
zeta=vil.damping(db,s.parameters.zeta); zeta=zeta(s.modeKeep);
W=s.W(s.use,:);
inKeep=find(s.modeKeep);
nid=numel(id.frequencyHz);
id.feMode=nan(nid,1); id.feHz=nan(nid,1); id.errorPct=nan(nid,1); id.mac=nan(nid,1);
seen=false(size(fe));
for k=1:nid
    [gap,j]=min(abs(fe-id.frequencyHz(k))./fe);
    if gap>0.03, continue, end
    id.feMode(k)=inKeep(j); id.feHz(k)=fe(j);
    id.errorPct(k)=100*(id.frequencyHz(k)-fe(j))/fe(j);
    seen(abs(fe-id.frequencyHz(k))./fe<0.03)=true;
    if size(W,1)>1
        a=id.A(:,k); b=W(:,j);
        id.mac(k)=abs(a'*b)^2/((a'*a)*(b'*b));
    end
end
strength=max(abs(W),[],1).'./(2*zeta);
strength=strength/max(strength);
missing=find(fe<=s.bandHz & ~seen);
id.missing=struct('mode',num2cell(inKeep(missing)),'frequencyHz',num2cell(fe(missing)), ...
    'weak',num2cell(strength(missing)<1e-3));
id.aboveBand=nnz(fe>s.bandHz);
s.modes=id;
end
