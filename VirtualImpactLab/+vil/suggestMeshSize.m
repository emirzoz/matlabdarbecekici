function h = suggestMeshSize(geometry)
% Default element size from the part's bounding box. The PDE mesher refines
% small features automatically; this sets the coarse global size only.
V = geometry.Vertices;
span = max(V,[],1)-min(V,[],1);
h = max(span)/15;
% Round to two significant figures so the UI shows a clean value.
p = 10^(floor(log10(h))-1);
h = round(h/p)*p;
end
