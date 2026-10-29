function model = importCAD(filename,scaleToMetres)
% Require explicit CAD-to-SI conversion, e.g. 1e-3 for millimetres.
validateattributes(scaleToMetres,{'numeric'},{'scalar','positive','finite'});
g = fegeometry(filename);
assert(g.NumCells == 1,'Import must contain exactly one solid cell.');
g = scale(g,scaleToMetres);
model = femodel(AnalysisType="structuralModal",Geometry=g);
end
