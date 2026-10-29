function [model,config] = createDemoBeam(hmax)
% SI cantilever: length along X, square cross section.
if nargin < 1, hmax = 0.008; end
assert(~isempty(ver('pde')), 'VirtualImpactLab requires PDE Toolbox.');
config = struct('E',210e9,'nu',0.3,'rho',7800,'L',0.30, ...
    'width',0.02,'height',0.02,'hmax',hmax,'rangeHz',[1 2000]);
g = multicuboid(config.L,config.width,config.height);
model = femodel(AnalysisType="structuralModal",Geometry=g);
% Find the end face geometrically instead of assuming face numbering.
face = nearestFace(model.Geometry,[-config.L/2 0 config.height/2]);
config.fixedFaces = face;
model = vil.setupModel(model,config);
end
