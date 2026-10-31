function tests=testShell
% Laminated shell solver against exact plate, laminate and ring solutions,
% shell-from-faces on a hand-built thin solid, and the radome STEP part.
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.applyFixture(matlab.unittest.fixtures.PathFixture(fileparts(fileparts(mfilename('fullpath')))));
t.TestData.imports=fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))),'imports');
end
function [nodes,tri]=plate(a,b,nx,ny)
[X,Y]=ndgrid(linspace(0,a,nx+1),linspace(0,b,ny+1)); nodes=[X(:).';Y(:).';0*X(:).'];
id=@(i,j)j*(nx+1)+i+1; tri=zeros(0,3);
for i=0:nx-1
    for j=0:ny-1
        p=[id(i,j) id(i+1,j) id(i+1,j+1) id(i,j+1)];
        if mod(i+j,2)==0, tri=[tri;p([1 2 3]);p([1 3 4])]; else, tri=[tri;p([1 2 4]);p([2 3 4])]; end %#ok<AGROW>
    end
end
end
function m=iso(E,nu,rho)
m=struct('E1',E,'E2',E,'G12',E/2/(1+nu),'nu12',nu,'rho',rho,'t',1);
end
function f=lowest(nodes,tri,L,fixedDofs,k)
[K,M]=vil.shellMatrices(nodes,tri,L);
fr=setdiff(1:size(K,1),fixedDofs);
f=sort(sqrt(abs(eigs(K(fr,fr),M(fr,fr),k,1)))/(2*pi));
end
function testPlatesMatchTheory(t)
E=210e9; nu=0.3; rho=7850; h=2e-3; a=0.3; D=E*h^3/12/(1-nu^2);
[nodes,tri]=plate(a,a,16,16); n=size(nodes,2); L=vil.laminate(iso(E,nu,rho),0,h);
x=nodes(1,:); y=nodes(2,:); edge=find(x<1e-9|x>a-1e-9|y<1e-9|y>a-1e-9);
% Simply supported: w, in-plane and drilling held on the edges.
f=lowest(nodes,tri,L,[edge edge+n edge+2*n edge+5*n],1);
verifyEqual(t,f(1),pi^2*2/a^2*sqrt(D/(rho*h))/(2*pi),'RelTol',0.003);
% Clamped (Leissa: 35.985).
f=lowest(nodes,tri,L,reshape(edge(:)+(0:5)*n,1,[]),1);
verifyEqual(t,f(1),35.985/a^2*sqrt(D/(rho*h))/(2*pi),'RelTol',0.006);
end
function testLaminatedPlatesMatchNavier(t)
cf=vil.plyMaterials(); cf=cf(1); a=0.3; b=0.2;
[nodes,tri]=plate(a,b,30,20); n=size(nodes,2); x=nodes(1,:); y=nodes(2,:);
edge=find(x<1e-9|x>a-1e-9|y<1e-9|y>b-1e-9);
navier=@(L,D)pi^2/sqrt(L.m)*sqrt(D(1,1)/a^4+2*(D(1,2)+2*D(3,3))/(a*b)^2+D(2,2)/b^4)/(2*pi);
% Symmetric cross-ply, simply supported: exact Navier solution.
L=vil.laminate(cf,[0 90 90 0],0.25e-3);
f=lowest(nodes,tri,L,[edge edge+n edge+2*n edge+5*n],1);
verifyEqual(t,f(1),navier(L,L.D),'RelTol',0.002);
% Unsymmetric [0/90], edges free to slide: bending-stretching coupling
% lowers the stiffness to D* = D - B A^-1 B.
L=vil.laminate(cf,[0 90],0.5e-3);
c0=find(x<1e-9&y<1e-9); c1=find(x>a-1e-9&y<1e-9);
f=lowest(nodes,tri,L,[edge+2*n edge+5*n c0 c0+n c1+n],1);
verifyEqual(t,f(1),navier(L,L.D-L.B*(L.A\L.B)),'RelTol',0.003);
% The fibre axis follows the reference direction: 90 deg plies equal 0 deg
% plies with the reference turned to Y.
[K1,M1]=vil.shellMatrices(nodes,tri,vil.laminate(cf,[90 0 0 90],0.25e-3));
[K2,M2]=vil.shellMatrices(nodes,tri,vil.laminate(cf,[0 90 90 0],0.25e-3),[],[0;1;0]);
verifyEqual(t,full(K1),full(K2),'AbsTol',1e-6*max(abs(K1(:))));
verifyEqual(t,full(M1),full(M2),'AbsTol',1e-12);
end
function testCylinderFreeFree(t)
% Free-free thin steel cylinder: six rigid modes, then the n = 2 ring mode.
E=210e9; nu=0.3; rho=7850; h=1e-3; R=0.05; Lz=0.2; nt=48; nz=24;
[T,Z]=ndgrid((0:nt-1)*2*pi/nt,linspace(0,Lz,nz+1));
nodes=[R*cos(T(:)).';R*sin(T(:)).';Z(:).']; id=@(i,j)mod(i,nt)+j*nt+1; tri=zeros(0,3);
for i=0:nt-1
    for j=0:nz-1
        p=[id(i,j) id(i+1,j) id(i+1,j+1) id(i,j+1)];
        if mod(i+j,2)==0, tri=[tri;p([1 2 3]);p([1 3 4])]; else, tri=[tri;p([1 2 4]);p([2 3 4])]; end %#ok<AGROW>
    end
end
c=struct('laminates',vil.laminate(iso(E,nu,rho),0,h),'ref',[0;0;1],'boundary','free');
[db,mats]=vil.solveShellModes(nodes,tri,c,'MinModes',4);
verifyNumElements(t,db.rigidBodyHz,6);
D=E*h^3/12/(1-nu^2); ring=6/sqrt(5)*sqrt(D/(rho*h))/R^2/(2*pi);
verifyEqual(t,db.frequencyHz(1:2),[ring;ring],'RelTol',0.002);
verifyEqual(t,db.totalMass,rho*h*2*pi*R*Lz,'RelTol',0.002);
verifyLessThan(t,db.massOrthogonalityError,1e-8);
% Residual flexibility on shells (rotations included) against dense modes.
n=size(nodes,2); f=sparse(3*n,1); f(2*n+5)=1; g=sparse(3*n,1); g(n+300)=1;
r=vil.residualFlexibility(db,mats,f,g);
verifyTrue(t,isfinite(r));
end
function testResidualFlexibilityOnShellPlate(t)
[nodes,tri]=plate(0.2,0.2,8,8); n=size(nodes,2);
c=struct('laminates',vil.laminate(iso(70e9,0.3,2700),0,1e-3),'fixedNodes',find(nodes(1,:)<1e-9));
[db,mats]=vil.solveShellModes(nodes,tri,c,'MinModes',5);
f=sparse(3*n,1); f(3*n)=1; g=sparse(3*n,1); g(2*n+40)=1;
fr=mats.free; F=[f;sparse(3*n,1)]; G=[g;sparse(3*n,1)];
P=[db.Phi;db.PhiRot]; P=P(fr,:);
exact=G(fr).'*(mats.K(fr,fr)\F(fr))-G(fr).'*P*diag(1./db.omega.^2)*P.'*F(fr);
verifyEqual(t,vil.residualFlexibility(db,mats,f,g),full(exact),'RelTol',1e-8);
end
function testShellFromThinSolid(t)
% A 100 x 60 x 2 mm plate as a closed, outward-oriented surface.
a=0.1; b=0.06; h=0.002; nx=20; ny=12;
[nodesTop,T]=plate(a,b,nx,ny); np=size(nodesTop,2);
nodes=[nodesTop+[0;0;h] nodesTop]; tri=[T;fliplr(T)+np]; fid=[ones(size(T,1),1);2*ones(size(T,1),1)];
id=@(i,j)j*(nx+1)+i+1;
sides={fliplr(arrayfun(@(j)id(0,j),0:ny)),3; arrayfun(@(j)id(nx,j),0:ny),4; ...
       arrayfun(@(i)id(i,0),0:nx),5; fliplr(arrayfun(@(i)id(i,ny),0:nx)),6};
for k=1:4
    e=sides{k,1}(:);
    q=[e(1:end-1) e(2:end) e(2:end)+np; e(1:end-1) e(2:end)+np e(1:end-1)+np];
    tri=[tri;fliplr(q)]; fid=[fid;sides{k,2}*ones(size(q,1),1)]; %#ok<AGROW>
end
surf=struct('tri',tri,'faceId',fid);
% One skin is suggested; its wall is 2 mm; the shell sits on the mid-plane.
verifyEqual(t,vil.suggestSkinFaces(nodes,surf,0.005),1);
sh=vil.shellFromFaces(nodes,surf,1);
verifyEqual(t,sh.faceThickness,h,'RelTol',1e-9);
verifyEqual(t,sh.nodes(3,:),h/2*ones(1,size(sh.nodes,2)),'AbsTol',1e-12);
% Clamped by the end face (touching) or by the bottom skin (far side).
fx=vil.shellClampNodes(sh,nodes,surf,3);
verifyNumElements(t,fx,ny+1); verifyEqual(t,max(sh.nodes(1,fx)),0,'AbsTol',1e-12);
verifyNumElements(t,vil.shellClampNodes(sh,nodes,surf,2),size(sh.nodes,2));
% Cantilever plate: close to beam theory with the plate stiffness.
E=70e9; c=struct('laminates',vil.laminate(iso(E,0.3,2700),0,h),'fixedNodes',fx,'faceId',sh.faceId);
db=vil.solveShellModes(sh.nodes,sh.tri,c,'MinModes',3);
D=E*h^3/12/(1-0.09);
verifyEqual(t,db.frequencyHz(1),1.875104^2/(2*pi*a^2)*sqrt(D/(2700*h)),'RelTol',0.04);
end
function testRadomeAsShell(t)
% The radome is a thin-walled cover: suggested skin faces, ~1 mm walls,
% and a free-free quartz laminate shell solve.
f=fullfile(t.TestData.imports,'radome.step');
assumeTrue(t,isfile(f),'radome.step not available');
g=vil.importCAD(f); [g,mi]=vil.meshPart(g,0.0015);
faces=vil.suggestSkinFaces(g.Mesh.Nodes,mi.surface,0.003);
verifyNotEmpty(t,faces);
sh=vil.shellFromFaces(g.Mesh.Nodes,mi.surface,faces);
verifyGreaterThan(t,min(sh.faceThickness),1e-4); verifyLessThan(t,max(sh.faceThickness),3e-3);
p=vil.plyMaterials(); q=p(strcmp([p.name],"Quartz woven/epoxy"));
L=vil.laminate(q,vil.parseLayup('[0/45]s'),median(sh.faceThickness)/4);
c=struct('laminates',L,'boundary','free','faceId',sh.faceId);
db=vil.solveShellModes(sh.nodes,sh.tri,c,'MinModes',6);
verifyNumElements(t,db.rigidBodyHz,6);
verifyTrue(t,all(db.frequencyHz>0));
log(t,sprintf('Radome shell: %d faces, walls %.2f-%.2f mm, first modes %s Hz',numel(faces), ...
    1e3*min(sh.faceThickness),1e3*max(sh.faceThickness),mat2str(round(db.frequencyHz(1:3).'))));
end
