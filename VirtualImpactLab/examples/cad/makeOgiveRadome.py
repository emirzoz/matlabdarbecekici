# Tangent-ogive nose radome as a thin-walled STEP solid (mm): the source of
# imports/ogive-radome.step. Needs Python with gmsh (pip install gmsh, which
# bundles the OpenCASCADE kernel). Run: python makeOgiveRadome.py
# Skin 2 mm over a tangent ogive (150 mm base, 225 mm long, 10 mm nose
# radius), a 4 mm mounting ring 15 mm deep, and a 4 mm outward bolt flange
# 14 mm wide with 8 x 5.5 mm holes.
import gmsh, math, numpy as np
D, L, rn, wall = 150.0, 225.0, 10.0, 2.0      # base dia, ogive length, nose radius, skin
ring_h, ring_t = 15.0, 4.0                    # mounting ring below the ogive: height, wall
lip_w, lip_t, nbolt, dbolt = 14.0, 4.0, 8, 5.5 # outward bolt flange
R = D/2; rho = (R*R+L*L)/(2*R)
og = lambda x: math.sqrt(rho**2-(L-x)**2)+R-rho        # x from sharp tip
sl = lambda x: (L-x)/math.sqrt(rho**2-(L-x)**2)
a,b = 0.0, L
for _ in range(200):
    m=(a+b)/2
    if (og(a)-rn)*(og(m)-rn) <= 0: b=m
    else: a=m
xt=m; s=sl(xt); Rs=rn*math.sqrt(1+s*s); xc=xt+s*rn
def outer(n=60):
    # meridian (r, z) from tip down to the ogive base z=0 (tip at z = L-(xc-Rs))
    pts=[]
    th0=math.atan2(rn, xc-xt)
    for t in np.linspace(0,th0,12)[1:]:
        x=xc-Rs*math.cos(t); pts.append((Rs*math.sin(t), L-x))
    for x in np.linspace(xt,L,n)[1:]:
        pts.append((og(x), L-x))
    return pts
def normal_in(r,z,i,pts):
    # inward normal from neighbouring points (towards the axis/inside)
    p0=pts[max(i-1,0)]; p1=pts[min(i+1,len(pts)-1)]
    tr,tz=p1[0]-p0[0],p1[1]-p0[1]; l=math.hypot(tr,tz)
    return (-tz/l, tr/l)          # rotate tangent (pointing down the meridian)
gmsh.initialize(); gmsh.option.setNumber("General.Terminal",0)
gmsh.model.add("radome"); occ=gmsh.model.occ
po=outer(); tip_z=L-(xc-Rs)
# outer profile region (r,z) in XZ plane: axis -> tip -> ogive -> ring -> bottom -> axis
def region(profile, zbot, rbot, ztip):
    ids=[occ.addPoint(0,0,ztip)]
    for r,z in profile: ids.append(occ.addPoint(r,0,z))
    ids.append(occ.addPoint(rbot,0,zbot)); ids.append(occ.addPoint(0,0,zbot))
    spl=occ.addSpline(ids[0:len(profile)+1])
    l1=occ.addLine(ids[len(profile)],ids[-2]); l2=occ.addLine(ids[-2],ids[-1]); l3=occ.addLine(ids[-1],ids[0])
    loop=occ.addCurveLoop([spl,l1,l2,l3]); return occ.addPlaneSurface([loop])
# outer: ogive down to z=0 then straight ring to -ring_h
so=region(po+[(R,-ring_h)][:0], -ring_h, R, tip_z)
# inner: offset the outer meridian inward by the skin, ring inner radius R-ring_t, open below
pi_=[]
for i,(r,z) in enumerate(po):
    nr,nz=normal_in(r,z,i,po)
    # make sure it points inward (towards smaller r / lower z near tip)
    if nr>0: nr,nz=-nr,-nz
    pi_.append((r+wall*nr, z+wall*nz))
pi_=[p for p in pi_ if p[0]>0.5]
si=region(pi_, -ring_h-1.0, R-ring_t, tip_z-wall)
vo=occ.revolve([(2,so)],0,0,0,0,0,1,2*math.pi); vi=occ.revolve([(2,si)],0,0,0,0,0,1,2*math.pi)
occ.synchronize()
Vo=[v for v in vo if v[0]==3]; Vi=[v for v in vi if v[0]==3]
shell,_=occ.cut(Vo,Vi)
# thicker mounting ring: annulus R-ring_t..R from -ring_h to 0 (fills ring wall), fused
ringO=occ.addCylinder(0,0,-ring_h,0,0,ring_h,R); ringI=occ.addCylinder(0,0,-ring_h-1,0,0,ring_h+2,R-ring_t)
ring,_=occ.cut([(3,ringO)],[(3,ringI)])
lipO=occ.addCylinder(0,0,-ring_h,0,0,lip_t,R+lip_w); lipI=occ.addCylinder(0,0,-ring_h-1,0,0,lip_t+2,R-ring_t)
lip,_=occ.cut([(3,lipO)],[(3,lipI)])
body,_=occ.fuse(shell,ring+lip)
holes=[(3,occ.addCylinder((R+lip_w/2)*math.cos(2*math.pi*k/nbolt),(R+lip_w/2)*math.sin(2*math.pi*k/nbolt),-ring_h-1,0,0,lip_t+2,dbolt/2)) for k in range(nbolt)]
body,_=occ.cut(body,holes)
occ.removeAllDuplicates(); occ.synchronize()
vols=gmsh.model.getEntities(3); print('volumes',vols)
print('faces',len(gmsh.model.getEntities(2)))
print('bbox',gmsh.model.getBoundingBox(-1,-1))
mass=sum(occ.getMass(3,v[1]) for v in vols); print('volume mm3',mass)
gmsh.option.setString("Geometry.OCCTargetUnit","MM")
gmsh.write("ogive-radome.step"); gmsh.finalize()
