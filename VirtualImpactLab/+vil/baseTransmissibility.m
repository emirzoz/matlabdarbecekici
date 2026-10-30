function H = baseTransmissibility(db,axis,monitor,frequencyHz,zeta)
% Absolute acceleration at the monitor per unit clamp acceleration along axis:
%    T(f) = u'r + sum phi*Gamma*w^2 / (w_r^2 - w^2 + 2i z w_r w)
% monitor = {node, direction}. Valid well below the highest solved mode.
z=vil.damping(db,zeta); wn=db.omega(:);
phi=vil.mapProbePoints(db,monitor{:}).';
weight=phi.*db.participation(axis,:).';
if isnumeric(monitor{2}) && ~isscalar(monitor{2})
    u=monitor{2}(:)/norm(monitor{2}); direct=u(axis);
else
    d=monitor{2}; if ~isnumeric(d), d=find('XYZ'==upper(char(d))); end
    direct=double(d==axis);
end
w=2*pi*frequencyHz(:);
H=direct+((w.^2)./(wn.'.^2-w.^2+2i*w.*(z.*wn).'))*weight;
H=reshape(H,size(frequencyHz));
end
