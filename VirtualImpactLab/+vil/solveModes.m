function db = solveModes(model,c)
validateattributes(c.rangeHz,{'numeric'},{'vector','numel',2,'positive','increasing'});
mesh = model.Geometry.Mesh;
span = max(mesh.Nodes,[],2)-min(mesh.Nodes,[],2);
fprintf('Mesh bounding-box dimensions (m): X=%.6g, Y=%.6g, Z=%.6g\n',span(1),span(2),span(3));
result = solve(model,FrequencyRange=2*pi*c.rangeHz);
% An empty frequency band may return ModeShapes as double([]).
% Inspect frequencies before accessing component fields.
omega = result.NaturalFrequencies;
if isempty(omega)
    error('vil:NoModes', ...
        ['No modes were found between %.6g and %.6g Hz. ' ...
         'Check CAD dimensions in metres, material density and stiffness, ' ...
         'and the selected fixed face. Then widen the modal frequency range. ' ...
         'For millimetre CAD coordinates, import with scale 0.001.'], ...
         c.rangeHz(1),c.rangeHz(2));
end
shapes = result.ModeShapes;
if isstruct(shapes)
    hasComponents = all(isfield(shapes,{'ux','uy','uz'}));
elseif isobject(shapes)
    hasComponents = all(cellfun(@(name)isprop(shapes,name),{'ux','uy','uz'}));
else
    hasComponents = false;
end
if ~hasComponents
    error('vil:ModeShapeFormat', ...
        ['Found %d frequencies but ModeShapes has unsupported type %s ' ...
         'and size %s in MATLAB %s. Component DOF ordering cannot be ' ...
         'assumed safely. Report this message for release-specific support.'], ...
         numel(omega),class(shapes),mat2str(size(shapes)),version('-release'));
end
% Structural assembly ordering is component-blocked: all X, then Y, then Z.
Phi = [shapes.ux;shapes.uy;shapes.uz];
assert(size(Phi,2)==numel(omega),'Mode shape count differs from frequency count.');
A = assembleFEMatrices(model);
mesh = model.Geometry.Mesh;
fixed = findNodes(mesh,'region','Face',c.fixedFaces);
n = size(mesh.Nodes,2);
free = setdiff(1:3*n,[fixed fixed+n fixed+2*n]);
db = vil.buildModalDatabase(mesh.Nodes,mesh.Elements,Phi, ...
    result.NaturalFrequencies,A.M,A.K,free,c);
end
