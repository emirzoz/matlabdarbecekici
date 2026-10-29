function db = solveModes(model,c)
validateattributes(c.rangeHz,{'numeric'},{'vector','numel',2,'positive','increasing'});
result = solve(model,FrequencyRange=2*pi*c.rangeHz);
A = assembleFEMatrices(model);
mesh = model.Geometry.Mesh;
% Structural assembly ordering is component-blocked: all X, then Y, then Z.
Phi = [result.ModeShapes.ux;result.ModeShapes.uy;result.ModeShapes.uz];
fixed = findNodes(mesh,'region','Face',c.fixedFaces);
n = size(mesh.Nodes,2);
free = setdiff(1:3*n,[fixed fixed+n fixed+2*n]);
db = vil.buildModalDatabase(mesh.Nodes,mesh.Elements,Phi, ...
    result.NaturalFrequencies,A.M,A.K,free,c);
end
