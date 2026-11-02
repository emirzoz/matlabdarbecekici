# Tangent-ogive nose radome as a thin-walled STEP solid (mm): the source of
# imports/ogive-radome.step. Needs Python with gmsh (pip install gmsh, which
# bundles the OpenCASCADE kernel). Run: python makeOgiveRadome.py [out.step]
# The whole wall cross-section is one closed outline (outer nose arc, ogive,
# mounting ring, bolt flange, inner ring, inner ogive, inner nose arc); its
# curves are revolved into surfaces and sewn into a closed solid, so no
# profile or seam faces remain. Only the bolt holes are cut afterwards. The nose is a spherical cap tangent
# to the ogive, with a concentric inner sphere: the skin is exactly `wall`.
import gmsh, math, numpy as np, sys
D, L, rn, wall = 150.0, 225.0, 10.0, 2.0       # base dia, ogive length, nose radius, skin
ring_h, ring_t = 15.0, 4.0                     # mounting ring below the ogive: depth, wall
lip_w, lip_t, nbolt, dbolt = 14.0, 4.0, 8, 5.5 # outward bolt flange: width, thickness, holes
out = sys.argv[1] if len(sys.argv) > 1 else "ogive-radome.step"
R = D/2; rho = (R*R+L*L)/(2*R)
og = lambda x: math.sqrt(rho**2-(L-x)**2)+R-rho        # radius; x from the sharp tip, base at x = L
sl = lambda x: (L-x)/math.sqrt(rho**2-(L-x)**2)
a, b = 0.0, L
for _ in range(200):
    m = (a+b)/2
    if (og(a)-rn)*(og(m)-rn) <= 0: b = m
    else: a = m
xt = m; s = sl(xt); Rs = rn*math.sqrt(1+s*s); xc = xt+s*rn
zc = L-xc                                              # nose sphere centre (ogive base at z = 0)
xs = np.linspace(xt, L, 80)
outer = [(og(x), L-x) for x in xs]                     # (r, z) from the nose tangency down to the base
inner = []                                             # offset inward by the wall along the normal
for x in xs:
    nr, nz = -1.0, -sl(x)                              # inward normal of r(x) in (r, z): z = L - x
    l = math.hypot(nr, nz); inner.append((og(x)+wall*nr/l, L-x+wall*nz/l))
inner[-1] = (R-wall, 0.0)                              # ogive base meets the ring at z = 0
ri = R-ring_t
gmsh.initialize(); gmsh.option.setNumber("General.Terminal", 0)
gmsh.model.add("radome"); occ = gmsh.model.occ
P = lambda r, z: occ.addPoint(r, 0, z)
c = P(0, zc)
tipO = P(0, zc+Rs); tipI = P(0, zc+Rs-wall)
o = [P(r, z) for r, z in outer]; i = [P(r, z) for r, z in inner]
pRing = P(R, -ring_h+lip_t); pLip1 = P(R+lip_w, -ring_h+lip_t); pLip2 = P(R+lip_w, -ring_h)
pBot = P(ri, -ring_h); pStep = P(ri, 0.0)
cur = [occ.addCircleArc(tipO, c, o[0]), occ.addSpline(o),
       occ.addLine(o[-1], pRing), occ.addLine(pRing, pLip1), occ.addLine(pLip1, pLip2),
       occ.addLine(pLip2, pBot), occ.addLine(pBot, pStep), occ.addLine(pStep, i[-1]),
       occ.addSpline(i[::-1]), occ.addCircleArc(i[0], c, tipI), occ.addLine(tipI, tipO)]
# Revolve the outline curves (not a profile face) into surfaces, then sew
# them into one closed shell: no profile face exists, so none can be left
# behind at the 360-degree seam. The short axis segment between the two
# nose tips sweeps no area and is not revolved.
surf = []
for cv in cur[:-1]:
    surf += [v for v in occ.revolve([(1, cv)], 0, 0, 0, 0, 0, 1, 2*math.pi) if v[0] == 2]
occ.remove([(1, cur[-1])], recursive=True)
part = [(3, occ.addVolume([occ.addSurfaceLoop([t for _, t in surf], sewing=True)]))]
rb = R+lip_w/2
holes = [(3, occ.addCylinder(rb*math.cos(2*math.pi*(k+0.5)/nbolt), rb*math.sin(2*math.pi*(k+0.5)/nbolt),
          -ring_h-1, 0, 0, lip_t+2, dbolt/2)) for k in range(nbolt)]
part, _ = occ.cut(part, holes)
occ.synchronize()
# Keep only the final solid: the sewn surfaces it was built from stay behind
# as loose faces after the hole cut.
own = {t for _, t in gmsh.model.getBoundary(part, oriented=False)}
loose = [(2, t) for _, t in gmsh.model.getEntities(2) if t not in own]
if loose: occ.remove(loose, recursive=True)
occ.synchronize()
vols = gmsh.model.getEntities(3)
print("volumes", len(vols), "faces", len(gmsh.model.getEntities(2)), "volume mm3", round(sum(occ.getMass(3, v[1]) for v in vols)))
for d, t in gmsh.model.getEntities(2):
    print(" face", t, gmsh.model.getType(2, t), round(occ.getMass(2, t)), np.round(gmsh.model.getBoundingBox(2, t), 1))
gmsh.option.setString("Geometry.OCCTargetUnit", "MM")
gmsh.write(out); gmsh.finalize()
