function p = mapProbePoints(db,node,direction)
validateattributes(node,{'numeric'},{'scalar','integer','positive'});
assert(ismember(node,db.surfaceNodes),'Probe must be a selectable surface node.');
if ischar(direction) || isstring(direction)
    direction = find('XYZ'==upper(char(direction)));
end
validateattributes(direction,{'numeric'},{'scalar','integer','>=',1,'<=',3});
p=db.Phi(node+(direction-1)*size(db.nodes,2),:);
end
