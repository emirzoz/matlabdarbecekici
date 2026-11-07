function sh = shellFromFaces(nodes,surf,faces,varargin)
% Shell mid-surface from picked faces of a meshed thin solid. nodes: solid
% mesh nodes (3 x N); surf: its exterior triangles (tri, faceId, outward
% normals as from vil.extractSurface); faces: CAD face IDs of one skin
% (e.g. the outer surface of a radome). Each face's wall thickness is
% measured by casting rays inward from its triangles to the opposite wall
% (median over the face). Nodes are moved inward by half the local
% thickness so the shell lies on the mid-surface. Faces of other skins,
% ribs and bosses are not part of the shell; holes stay holes.
% Options: 'Offset' (true), 'Samples' (rays per face, 25).
o = struct('Offset',true,'Samples',25);
for k = 1:2:numel(varargin), o.(varargin{k}) = varargin{k+1}; end
faces = unique(faces(:)).';
pick = ismember(surf.faceId,faces);
assert(any(pick),'vil:ShellFaces','Pick the faces of one skin to model as a shell.');
T = surf.tri(pick,:); fid = surf.faceId(pick);
[map,~,j] = unique(T(:)); tri = reshape(j,size(T));
X = nodes(:,map);
% Wall thickness per face.
A = nodes(:,surf.tri(:,1)); B = nodes(:,surf.tri(:,2)); C = nodes(:,surf.tri(:,3));
nrm = cross(B-A,C-A); nrm = nrm./vecnorm(nrm);
span = max(max(nodes,[],2)-min(nodes,[],2));
faceT = zeros(numel(faces),1);
for k = 1:numel(faces)
    own = find(surf.faceId == faces(k));
    s = own(round(linspace(1,numel(own),min(o.Samples,numel(own)))));
    d = zeros(numel(s),1);
    for q = 1:numel(s)
        i = s(q); p0 = (A(:,i)+B(:,i)+C(:,i))/3;
        d(q) = rayHit(p0-1e-9*span*nrm(:,i),-nrm(:,i),A,B,C,i);
    end
    d = d(isfinite(d));
    assert(~isempty(d),'vil:ShellThickness','No opposite wall found behind face %d: is it part of a closed solid?',faces(k));
    faceT(k) = median(d);
end
tTri = faceT(arrayfun(@(f)find(faces==f),fid));
% Node thickness and normal: mean over the picked triangles that touch it.
tn = accumarray(tri(:),repmat(tTri,3,1),[size(X,2) 1])./accumarray(tri(:),1,[size(X,2) 1]);
nTri = nrm(:,pick); area = vecnorm(cross(X(:,tri(:,2))-X(:,tri(:,1)),X(:,tri(:,3))-X(:,tri(:,1))));
nn = zeros(3,size(X,2));
for d = 1:3, nn(d,:) = accumarray(tri(:),repmat((nTri(d,:).*area).',3,1),[size(X,2) 1]).'; end
nn = nn./vecnorm(nn);
if o.Offset, X = X-nn.*(tn.'/2); end
piece = pieces(tri,size(X,2));
sh = struct('nodes',X,'tri',tri,'faceId',fid,'triThickness',tTri,'nodeThickness',tn, ...
    'faces',faces,'faceThickness',faceT,'solidNode',map(:),'normal',nn,'offset',o.Offset, ...
    'piece',piece,'numPieces',max(piece));
end

function c = pieces(tri,n)
% Connected pieces of the shell (union-find over triangle edges): a skin
% left out between faces splits the shell, and each piece moves on its own.
p = 1:n;
for e = [tri(:,[1 2]); tri(:,[2 3])].'
    a = e(1); while p(a) ~= a, a = p(a); end
    b = e(2); while p(b) ~= b, b = p(b); end
    if a ~= b, p(max(a,b)) = min(a,b); end
end
for k = 1:n, a = k; while p(a) ~= a, a = p(a); end, p(k) = a; end
[~,~,c] = unique(p); c = c(:);
end

function t = rayHit(p,d,A,B,C,self)
% Nearest positive hit of the ray p + t*d on the triangles (Moller-Trumbore).
e1 = B-A; e2 = C-A; h = cross(repmat(d,1,size(A,2)),e2); a = sum(e1.*h,1);
ok = abs(a) > 1e-14; f = zeros(size(a)); f(ok) = 1./a(ok);
s = p-A; u = f.*sum(s.*h,1); q = cross(s,e1); v = f.*sum(q.*d,1);
t = f.*sum(e2.*q,1);
hit = ok & u >= 0 & v >= 0 & u+v <= 1 & t > 0; hit(self) = false;
if any(hit), t = min(t(hit)); else, t = Inf; end
end
