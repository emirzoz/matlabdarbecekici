function [geometry,config,meshInfo] = createDemoBeam(hmax)
% SI cantilever: length along X, square cross section, meshed.
if nargin < 1, hmax = 0.008; end
assert(~isempty(ver('pde')),'vil:NoPDE','VirtualImpactLab requires PDE Toolbox.');
config = struct('E',210e9,'nu',0.3,'rho',7800,'L',0.30, ...
    'width',0.02,'height',0.02,'hmax',hmax,'rangeHz',[1 2000]);
geometry = fegeometry(multicuboid(config.L,config.width,config.height));
% Find the end face geometrically instead of assuming face numbering.
config.fixedFaces = nearestFace(geometry,[-config.L/2 0 config.height/2]);
[geometry,meshInfo] = vil.meshPart(geometry,hmax);
end
