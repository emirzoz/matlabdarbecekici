function T = meshConvergence(dbA,dbB)
% Compare the modes of one part on two meshes (B usually finer). Shapes of B
% are sampled at A's surface nodes (nearest B surface node) and paired by
% MAC, so reordered or swapped modes still match. Returns the
% vil.compareModes table: Error_pct is A relative to B.
xa = dbA.nodes(:,dbA.surfaceNodes); xb = dbB.nodes(:,dbB.surfaceNodes);
near = zeros(size(xa,2),1);
for k = 1:2000:size(xa,2)            % chunked: never a full distance matrix
    j = k:min(k+1999,size(xa,2));
    d = sum(xb.^2,1).' - 2*xb.'*xa(:,j) + sum(xa(:,j).^2,1);
    [~,near(j)] = min(d,[],1);
end
nA = size(dbA.nodes,2); nB = size(dbB.nodes,2);
ia = dbA.surfaceNodes(:) + [0 nA 2*nA]; ib = dbB.surfaceNodes(near) + [0 nB 2*nB];
T = vil.compareModes(dbA.frequencyHz,dbA.Phi(ia(:),:),dbB.frequencyHz,dbB.Phi(ib(:),:));
end
