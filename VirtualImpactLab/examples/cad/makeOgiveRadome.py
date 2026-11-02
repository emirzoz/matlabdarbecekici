# Tangent-ogive nose radome as a thin-walled STEP solid (mm): the source of
# imports/ogive-radome.step (and .stl). Needs Python with OCP, the
# OpenCASCADE bindings used by CadQuery (pip install cadquery-ocp).
# Run: python makeOgiveRadome.py [out.step]
# The wall cross-section is one closed face (outer nose arc, ogive, mounting
# ring, bolt flange, inner ring, inner ogive, inner nose arc, axis segment)
# revolved through 360 degrees with BRepPrimAPI_MakeRevol; the bolt holes are
# cut, the shape is healed and checked, and written with the standard STEP
# writer. The nose is a spherical cap tangent to the ogive with a concentric
# inner sphere, so the skin is exactly `wall` everywhere on the cap.
import math, sys, numpy as np
from OCP.gp import gp_Pnt, gp_Ax1, gp_Ax2, gp_Dir, gp_Circ
from OCP.GC import GC_MakeArcOfCircle
from OCP.GeomAPI import GeomAPI_PointsToBSpline
from OCP.collections import Array1_gp_Pnt
from OCP.BRepBuilderAPI import BRepBuilderAPI_MakeEdge, BRepBuilderAPI_MakeWire, BRepBuilderAPI_MakeFace
from OCP.BRepPrimAPI import BRepPrimAPI_MakeRevol, BRepPrimAPI_MakeCylinder
from OCP.BRepAlgoAPI import BRepAlgoAPI_Cut
from OCP.ShapeFix import ShapeFix_Shape
from OCP.BRepCheck import BRepCheck_Analyzer
from OCP.STEPControl import STEPControl_Writer, STEPControl_AsIs
from OCP.Interface import Interface_Static
from OCP.BRepMesh import BRepMesh_IncrementalMesh
from OCP.StlAPI import StlAPI_Writer
from OCP.TopExp import TopExp_Explorer
from OCP.TopAbs import TopAbs_FACE, TopAbs_SOLID
from OCP.GProp import GProp_GProps
from OCP.BRepGProp import BRepGProp

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
outer = [(og(x), L-x) for x in xs]
inner = []
for x in xs:                                           # offset inward along the normal by the wall
    nr, nz = -1.0, -sl(x); l = math.hypot(nr, nz)
    inner.append((og(x)+wall*nr/l, L-x+wall*nz/l))
inner[-1] = (R-wall, 0.0)
ri = R-ring_t
P = lambda r, z: gp_Pnt(r, 0, z)
def line(p, q): return BRepBuilderAPI_MakeEdge(p, q).Edge()
def arc(p, q, r_mid):                                  # arc on a sphere about the axis point (0, zc)
    return BRepBuilderAPI_MakeEdge(GC_MakeArcOfCircle(p, r_mid, q).Value()).Edge()
def spline(pts):
    arr = Array1_gp_Pnt(1, len(pts))
    for k, (r, z) in enumerate(pts): arr.SetValue(k+1, P(r, z))
    return BRepBuilderAPI_MakeEdge(GeomAPI_PointsToBSpline(arr, 3, 8).Curve()).Edge()
def mid(rad, p_end):                                   # point halfway along a nose arc from the tip
    ang = math.atan2(p_end[0], p_end[1]-zc)/2
    return P(rad*math.sin(ang), zc+rad*math.cos(ang))
tipO = P(0, zc+Rs); tipI = P(0, zc+Rs-wall)
o0 = P(*outer[0]); oN = P(*outer[-1]); i0 = P(*inner[0]); iN = P(*inner[-1])
pRing, pLip1, pLip2, pBot, pStep = P(R, -ring_h+lip_t), P(R+lip_w, -ring_h+lip_t), P(R+lip_w, -ring_h), P(ri, -ring_h), P(ri, 0.0)
edges = [arc(tipO, o0, mid(Rs, outer[0])), spline(outer), line(oN, pRing), line(pRing, pLip1), line(pLip1, pLip2),
         line(pLip2, pBot), line(pBot, pStep), line(pStep, iN), spline(inner[::-1]),
         arc(i0, tipI, mid(Rs-wall, inner[0])), line(tipI, tipO)]
w = BRepBuilderAPI_MakeWire()
for e in edges: w.Add(e)
face = BRepBuilderAPI_MakeFace(w.Wire(), True).Face()
part = BRepPrimAPI_MakeRevol(face, gp_Ax1(gp_Pnt(0, 0, 0), gp_Dir(0, 0, 1)), 2*math.pi).Shape()
rb = R+lip_w/2
for k in range(nbolt):
    t = 2*math.pi*(k+0.5)/nbolt
    cyl = BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(rb*math.cos(t), rb*math.sin(t), -ring_h-1), gp_Dir(0, 0, 1)), dbolt/2, lip_t+2).Shape()
    part = BRepAlgoAPI_Cut(part, cyl).Shape()
fix = ShapeFix_Shape(part); fix.Perform(); part = fix.Shape()
def count(sh, t):
    e = TopExp_Explorer(sh, t); n = 0
    while e.More(): n += 1; e.Next()
    return n
gp = GProp_GProps(); BRepGProp.VolumeProperties_s(part, gp)
print("valid", BRepCheck_Analyzer(part).IsValid(), "solids", count(part, TopAbs_SOLID), "faces", count(part, TopAbs_FACE), "volume mm3", round(gp.Mass()))
Interface_Static.SetCVal_s("write.step.schema", "AP214IS"); Interface_Static.SetCVal_s("write.step.unit", "MM")
wr = STEPControl_Writer(); wr.Transfer(part, STEPControl_AsIs); wr.Write(out)
BRepMesh_IncrementalMesh(part, 0.2, False, 0.2, True)
stl = StlAPI_Writer(); stl.ASCIIMode = False
stl.Write(part, out.rsplit(".", 1)[0]+".stl")
