function T = compareModes(fA,PhiA,fB,PhiB)
% Pair modes of two solutions by MAC and report frequency error.
% fA, fB: frequencies (Hz); PhiA, PhiB: shapes on the same DOFs (columns).
% Each A mode is paired with its best-MAC B mode. Repeated or near-repeated
% modes (e.g. the square demo beam) can mix within their subspace; for those
% the subspace MAC (largest cosine to the B pair's span) is also reported.
nA = numel(fA); nB = numel(fB);
mac = macMatrix(PhiA,PhiB);
[best,match] = max(mac,[],2);
subspace = zeros(nA,1);
for i = 1:nA
    % B modes within 1% of the matched frequency form its subspace.
    near = find(abs(fB-fB(match(i)))<=0.01*fB(match(i)));
    Q = orth(PhiB(:,near));
    a = PhiA(:,i)/norm(PhiA(:,i));
    subspace(i) = norm(Q'*a)^2;
end
errPct = 100*(fA(:)-fB(match(:)))./fB(match(:));
T = table((1:nA).',fA(:),match(:),fB(match(:)),errPct,best,subspace, ...
    'VariableNames',{'Mode','MATLAB_Hz','RefMode','Ref_Hz','Error_pct','MAC','SubspaceMAC'});
T.Properties.UserData = struct('mac',mac,'numRef',nB);
end

function mac = macMatrix(A,B)
num = abs(A'*B).^2;
mac = num./(sum(A.^2,1).'*sum(B.^2,1));
end
