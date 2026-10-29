function z = damping(db,z)
validateattributes(z,{'numeric'},{'real','finite','nonnegative'});
if isscalar(z), z=repmat(z,numel(db.omega),1); else, z=z(:); end
assert(numel(z)==numel(db.omega),'Provide one damping ratio or one per mode.');
end
