"""Independent Abaqus/CAE modal model built directly from the STEP file.

Usage: abaqus cae noGUI=cae_step_modal.py -- <config.json>
(Abaqus/CAE needs a cae license token; the solver uses standard tokens.)

The config (written by MATLAB) gives the STEP file, scale to metres, mesh
size, SI material, points on the fixed faces and the upper frequency. The
part is meshed by Abaqus with C3D10 elements, so both the CAD import and the
mesher are independent of MATLAB. Results are written next to the config.
"""
import json
import os
import sys

# Abaqus registers methods such as mdb.openStep only when these modules load.
from abaqus import *  # noqa: F401,F403
from abaqusConstants import *  # noqa: F401,F403
import part  # noqa: F401
import material  # noqa: F401
import section  # noqa: F401
import assembly  # noqa: F401
import step  # noqa: F401
import load  # noqa: F401
import mesh
import job  # noqa: F401
import regionToolset


def main(cfg_path):
    with open(cfg_path) as f:
        cfg = json.load(f)
    work = os.path.dirname(os.path.abspath(cfg_path))
    os.chdir(work)
    model = mdb.models['Model-1']
    geom = mdb.openStep(fileName=cfg['step'], scaleFromFile=OFF)
    part = model.PartFromGeometryFile(name='PART', geometryFile=geom, combine=False,
                                      dimensionality=THREE_D, type=DEFORMABLE_BODY,
                                      scale=cfg['scale'])
    xyz = [v.pointOn[0] for v in part.vertices]
    bbox = [[min(p[i] for p in xyz) for i in range(3)], [max(p[i] for p in xyz) for i in range(3)]]

    mat = model.Material(name='MAT')
    mat.Elastic(table=((cfg['E'], cfg['nu']),))
    mat.Density(table=((cfg['rho'],),))
    model.HomogeneousSolidSection(name='SEC', material='MAT', thickness=None)
    part.SectionAssignment(region=regionToolset.Region(cells=part.cells), sectionName='SEC')

    part.seedPart(size=cfg['hmax'], deviationFactor=0.1, minSizeFactor=0.1)
    part.setMeshControls(regions=part.cells, elemShape=TET, technique=FREE)
    part.setElementType(regions=(part.cells,),
                        elemTypes=(mesh.ElemType(elemCode=C3D10, elemLibrary=STANDARD),))
    part.generateMesh()

    asm = model.rootAssembly
    inst = asm.Instance(name='PART-1', part=part, dependent=ON)
    hits = inst.faces.getClosest(coordinates=tuple(tuple(p) for p in cfg['fixedPoints']))
    indices = sorted(set(hit[0].index for hit in hits.values()))
    faces = inst.faces[indices[0]:indices[0] + 1]
    for i in indices[1:]:
        faces = faces + inst.faces[i:i + 1]
    region = asm.Set(name='FIXED', faces=faces)
    model.EncastreBC(name='FIX', createStepName='Initial', region=region)
    model.FrequencyStep(name='FREQ', previous='Initial', eigensolver=LANCZOS,
                        numEigen=ALL, maxEigen=cfg['maxHz'], normalization=MASS)

    analysis = mdb.Job(name=cfg['job'], model='Model-1', numCpus=4, numDomains=4)
    analysis.submit(consistencyChecking=OFF)
    analysis.waitForCompletion()

    info = {'bbox': bbox, 'numNodes': len(part.nodes), 'numElements': len(part.elements),
            'fixedFaces': indices, 'numFacesCAD': len(part.faces)}
    with open(os.path.join(work, cfg['job'] + '_cae.json'), 'w') as f:
        json.dump(info, f)
    with open(os.path.join(work, cfg['job'] + '_nodes.txt'), 'w') as f:
        for node in part.nodes:
            f.write('%d %.12e %.12e %.12e\n' % ((node.label,) + tuple(node.coordinates)))


if __name__ == '__main__':
    # abaqus cae strips the "--" separator; the config path is the last argument.
    main(sys.argv[-1])
