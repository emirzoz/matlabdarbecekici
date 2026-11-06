function [ids,info] = selectNodes(nodes,elements,surf,spec)
% Resolve a node selection used for supports or a payload attachment.
% nodes 3 x N (m), elements 4|10 x E, surf from vil.extractSurface (tri,
% faceId). spec.method:
%   "plane": spec.axis (1-3 or "X"/"Y"/"Z"), spec.positionMm, spec.toleranceMm.
%            Every mesh node with |x_axis - position| <= tolerance.
%   "faces": spec.faces (surface face IDs). Corner nodes of the face
%            triangles plus, on 10-node meshes, the midside nodes of their
%            edges, i.e. the same nodes findNodes(mesh,'region','Face',f) gives.
%   "nodes": spec.nodes (explicit node IDs, e.g. from an older project).
% info: count, axis range of the model (mm), centroid (m) and a description.
arguments
    nodes (3,:) double
    elements double
    surf struct
    spec struct
end
n = size(nodes,2);
method = string(spec.method);
info = struct('method',method,'count',0,'centroid',nan(3,1),'description',"");
switch method
    case "plane"
        ax = axisIndex(spec.axis); name = 'XYZ'; name = name(ax);
        validateattributes(spec.positionMm,{'numeric'},{'scalar','finite','real'});
        validateattributes(spec.toleranceMm,{'numeric'},{'scalar','finite','real','nonnegative'});
        x = nodes(ax,:);
        ids = find(abs(x-spec.positionMm/1e3) <= spec.toleranceMm/1e3);
        info.rangeMm = 1e3*[min(x) max(x)];
        info.description = sprintf('%s = %.4g mm \x00B1 %.4g mm',name,spec.positionMm,spec.toleranceMm);
        if isempty(ids)
            [~,k] = min(abs(x-spec.positionMm/1e3));
            error('vil:EmptySelection',['No mesh node lies within %s. The model spans %s = %.4g to %.4g mm; ' ...
                'the nearest node is at %s = %.6g mm. Check the position against the imported coordinates, ' ...
                'or widen the tolerance.'],info.description,name,info.rangeMm(1),info.rangeMm(2),name,1e3*x(k));
        end
    case "faces"
        faces = unique(round(spec.faces(:))).';
        assert(~isempty(faces),'vil:EmptySelection','Select at least one face.');
        known = unique(surf.faceId(surf.faceId>0)).';
        bad = setdiff(faces,known);
        assert(isempty(bad),'vil:BadFace','Face ID(s) %s do not exist on this mesh (valid: 1 to %d).', ...
            num2str(bad),max([known 0]));
        tri = surf.tri(ismember(surf.faceId,faces),:);
        ids = unique(tri(:)).';
        if size(elements,1) == 10
            ids = union(ids,midsideNodes(elements,tri));
        end
        info.description = "face(s) " + strjoin(string(faces),' ');
    case "nodes"
        ids = unique(round(spec.nodes(:))).';
        assert(~isempty(ids),'vil:EmptySelection','The stored node list is empty.');
        assert(all(ids>=1 & ids<=n),'vil:BadNode','Node IDs must lie between 1 and %d.',n);
        info.description = sprintf('stored list of %d node(s)',numel(ids));
    otherwise
        error('vil:Selection','Unknown selection method "%s".',method);
end
ids = ids(:).';
info.count = numel(ids);
info.centroid = mean(nodes(:,ids),2);
end

function ax = axisIndex(a)
if isstring(a) || ischar(a), ax = find('XYZ'==upper(char(a))); else, ax = a; end
assert(isscalar(ax) && any(ax==1:3),'vil:Axis','Axis must be X, Y or Z.');
end

function mids = midsideNodes(elements,tri)
% PDE Toolbox / C3D10 order: corners 1-4, midsides 12,23,13,14,24,34.
pairs = [1 2;2 3;1 3;1 4;2 4;3 4];
E = double(elements);
ends = [reshape(E(pairs(:,1),:).',[],1) reshape(E(pairs(:,2),:).',[],1)];
mid = reshape(E(5:10,:).',[],1);
key = sort(ends,2);
faceEdges = sort([tri(:,[1 2]); tri(:,[2 3]); tri(:,[1 3])],2);
[hit,loc] = ismember(faceEdges,key,'rows');
mids = unique(mid(loc(hit))).';
end
