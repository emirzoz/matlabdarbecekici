function out = calculateFRF(db,hammer,sensor,frequencyHz,zeta)
% hammer/sensor = {nodeID, direction}; receptance m/N, accelerance (m/s^2)/N.
f=frequencyHz(:).'; validateattributes(f,{'numeric'},{'nonnegative','finite'});
zeta=vil.damping(db,zeta);
b=vil.mapProbePoints(db,hammer{1},hammer{2});
c=vil.mapProbePoints(db,sensor{1},sensor{2});
w=2*pi*f;
D=db.omega.^2-w.^2+2i*(zeta.*db.omega)*w;
Hx=sum((c.*b).'./D,1);
if max(w)>0.8*max(db.omega)
    warning('vil:Truncation','Response near modal cutoff may require additional modes.');
end
out=struct('frequencyHz',f,'displacement',Hx,'accelerance',-w.^2.*Hx, ...
    'displacementUnits','m/N','acceleranceUnits','(m/s^2)/N');
end
