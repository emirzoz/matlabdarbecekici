function model = setupModel(model,c)
validateattributes(c.E,{'numeric'},{'scalar','positive','finite'});
validateattributes(c.rho,{'numeric'},{'scalar','positive','finite'});
validateattributes(c.nu,{'numeric'},{'scalar','>',-1,'<',0.5});
assert(~isempty(c.fixedFaces),'Select at least one fixed face.');
model.MaterialProperties = materialProperties(YoungsModulus=c.E, ...
    PoissonsRatio=c.nu,MassDensity=c.rho);
model.FaceBC(c.fixedFaces) = faceBC(Constraint="fixed");
model = generateMesh(model,Hmax=c.hmax,GeometricOrder="quadratic");
end
