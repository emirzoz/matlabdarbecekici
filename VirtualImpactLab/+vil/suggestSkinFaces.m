function [faces,info] = suggestSkinFaces(nodes,surf,maxThickness)
% Faces of one skin of a thin-walled solid, as a starting pick for
% vil.shellFromFaces. A face qualifies if its wall is thin (the inward ray
% meets the opposite wall within maxThickness) and it looks outward (most
% outward rays escape the part). Of the two skins of a wall that both look
% outward (a flange), the one facing away from the part centre is kept.
% info: per CAD face [faceId thickness escapeFraction opposite].
A = nodes(:,surf.tri(:,1)); B = nodes(:,surf.tri(:,2)); C = nodes(:,surf.tri(:,3));
nrm = cross(B-A,C-A); area = vecnorm(nrm)/2; nrm = nrm./vecnorm(nrm);
cen = (A+B+C)/3; mid = (max(nodes,[],2)+min(nodes,[],2))/2;
span = max(max(nodes,[],2)-min(nodes,[],2));
ids = unique(surf.faceId(surf.faceId>0)).';
info = zeros(numel(ids),4);
for k = 1:numel(ids)
    own = find(surf.faceId == ids(k));
    s = own(round(linspace(1,numel(own),min(9,numel(own)))));
    t = zeros(numel(s),1); out = false(numel(s),1); opp = zeros(numel(s),1);
    for q = 1:numel(s)
        i = s(q); p = cen(:,i);
        [t(q),j] = hit(p-1e-9*span*nrm(:,i),-nrm(:,i),A,B,C,i);
        if isfinite(t(q)), opp(q) = surf.faceId(j); end
        out(q) = ~isfinite(hit(p+1e-9*span*nrm(:,i),nrm(:,i),A,B,C,i));
    end
    info(k,:) = [ids(k) median(t) mean(out) mode(opp)];
end
cand = info(:,2) <= maxThickness & info(:,3) >= 0.5;
% Both skins of one wall look outward: keep the one facing away from the centre.
away = zeros(numel(ids),1);
for k = 1:numel(ids)
    own = surf.faceId == ids(k);
    away(k) = sum(area(own).*sum(nrm(:,own).*(cen(:,own)-mid),1))/sum(area(own));
end
for k = find(cand).'
    o = find(ids == info(k,4));
    if ~isempty(o) && cand(o) && (away(o) > away(k) || (away(o) == away(k) && o < k)), cand(k) = false; end
end
% One connected skin: add thin faces that join separate pieces (a step or a
% fillet left out), then keep only the largest piece (drops islands such as
% the top of a boss).
faceArea = arrayfun(@(f)sum(area(surf.faceId==f)),ids);
fn = arrayfun(@(f)unique(surf.tri(surf.faceId==f,:)),ids,'UniformOutput',false);
touch = false(numel(ids));
for a = 1:numel(ids)
    for b = a+1:numel(ids)
        touch(a,b) = ~isempty(intersect(fn{a},fn{b})); touch(b,a) = touch(a,b);
    end
end
thin = info(:,2) <= maxThickness;
while true
    pc = piecesOf(cand,touch);
    if max(pc) <= 1, break, end
    join = find(~cand & thin & arrayfun(@(k)numel(unique(pc(touch(k,:) & cand.'))) > 1,(1:numel(ids)).'));
    if isempty(join), break, end
    [~,i] = min(faceArea(join)); cand(join(i)) = true;
end
pc = piecesOf(cand,touch);
if max(pc) > 1
    big = accumarray(pc(cand),faceArea(cand)); [~,keep] = max(big);
    cand = cand & pc == keep;
end
faces = ids(cand);
end

function pc = piecesOf(cand,touch)
% Piece number of each candidate face (0 for others) over shared nodes.
pc = zeros(numel(cand),1); n = 0;
for k = find(cand(:)).'
    if pc(k), continue, end
    n = n+1; stack = k; pc(k) = n;
    while ~isempty(stack)
        j = stack(end); stack(end) = [];
        nb = find(touch(j,:).' & cand(:) & pc == 0);
        pc(nb) = n; stack = [stack; nb]; %#ok<AGROW>
    end
end
end

function [t,j] = hit(p,d,A,B,C,self)
e1 = B-A; e2 = C-A; h = cross(repmat(d,1,size(A,2)),e2); a = sum(e1.*h,1);
ok = abs(a) > 1e-14; f = zeros(size(a)); f(ok) = 1./a(ok);
s = p-A; u = f.*sum(s.*h,1); q = cross(s,e1); v = f.*sum(q.*d,1);
tt = f.*sum(e2.*q,1);
good = ok & u >= 0 & v >= 0 & u+v <= 1 & tt > 0; good(self) = false;
tt(~good) = Inf; [t,j] = min(tt);
if ~isfinite(t), j = 0; end
end
