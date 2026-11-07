function z = rayleighDamping(omega,zLow,zHigh)
% Rayleigh damping C = a*M + b*K through zLow at the lowest and zHigh at
% the highest mode: z(w) = a/(2w) + b*w/2. Mass damping dominates low
% modes, stiffness damping high ones.
w = omega(:); w1 = w(1); w2 = w(end);
if w2 <= w1*(1+1e-9), z = zLow*ones(size(w)); return, end
ab = [1/(2*w1) w1/2; 1/(2*w2) w2/2]\[zLow; zHigh];
% z(w) is monotonic between the anchors, or convex with its minimum
% sqrt(a*b) > 0, so every mode keeps positive damping.
z = ab(1)./(2*w) + ab(2)*w/2;
end
