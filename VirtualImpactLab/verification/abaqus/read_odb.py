"""Extract modal, FRF and impact results from an Abaqus ODB to plain text.

Usage: abaqus python read_odb.py <job.odb> <output_folder>

Writes:
  frequencies.txt   mode, frequency (Hz), generalized mass
  modes_nodes.txt   node labels (one per row of modes_u.txt)
  modes_u.txt       per node: U1..U3 for mode 1, then mode 2, ...
  ssd.txt           frequency (Hz), Re U, Im U at the sensor DOF
  impact.txt        time (s), U, A at the sensor DOF
"""
import os
import sys

import numpy as np
from odbAccess import openOdb


def main(odb_path, out):
    os.makedirs(out, exist_ok=True)
    odb = openOdb(odb_path, readOnly=True)
    steps = odb.steps
    if 'FREQ' in steps.keys():
        write_modes(steps['FREQ'], out)
    sensor = sensor_dof(odb)
    if 'SSD' in steps.keys() and sensor:
        write_ssd(steps['SSD'], sensor, out)
    if 'IMPACT' in steps.keys() and sensor:
        write_impact(steps['IMPACT'], sensor, out)
    if 'SSDBASE' in steps.keys() and sensor:
        write_base(steps['SSDBASE'], 'TA', sensor, os.path.join(out, 'ssdbase.txt'))
    if 'RANDOM' in steps.keys() and sensor:
        write_base(steps['RANDOM'], 'RTA', sensor, os.path.join(out, 'random.txt'))
    odb.close()


def write_base(step, name, label, path):
    """Frequency, then the three components and their conjugates, at the sensor."""
    with open(path, 'w') as f:
        for i in range(1, len(step.frames)):
            frame = step.frames[i]
            if name not in frame.fieldOutputs.keys():
                continue
            value = [v for v in frame.fieldOutputs[name].values if v.nodeLabel == label][0]
            imag = value.conjugateData if value.conjugateData is not None else (0.0, 0.0, 0.0)
            f.write('%.12g %s %s\n' % (
                frame.frequency,
                ' '.join('%.12e' % x for x in value.data[:3]),
                ' '.join('%.12e' % x for x in imag[:3])))


def write_modes(step, out):
    rows, shapes, labels = [], [], None
    for i in range(1, len(step.frames)):
        frame = step.frames[i]
        field = frame.fieldOutputs['U']
        block = field.bulkDataBlocks[0]
        order = np.argsort(block.nodeLabels)
        if labels is None:
            labels = np.asarray(block.nodeLabels)[order]
        shapes.append(np.asarray(block.data, dtype=float)[order, :3])
        rows.append((frame.mode, frame.frequency))
    gm = {}
    for region in step.historyRegions.values():
        for key, out_data in region.historyOutputs.items():
            if key.startswith('GM'):
                for mode, value in out_data.data:
                    gm[int(round(mode))] = value
    with open(os.path.join(out, 'frequencies.txt'), 'w') as f:
        for mode, freq in rows:
            f.write('%d %.12g %.12g\n' % (mode, freq, gm.get(mode, float('nan'))))
    np.savetxt(os.path.join(out, 'modes_nodes.txt'), labels, fmt='%d')
    np.savetxt(os.path.join(out, 'modes_u.txt'), np.hstack(shapes), fmt='%.10e')


def sensor_dof(odb):
    sets = odb.rootAssembly.instances.values()[0].nodeSets
    if 'SENSOR' not in sets.keys():
        return None
    label = sets['SENSOR'].nodes[0].label
    return label


def write_ssd(step, label, out):
    with open(os.path.join(out, 'ssd.txt'), 'w') as f:
        for i in range(1, len(step.frames)):  # frame 0 is the base state
            frame = step.frames[i]
            value = [v for v in frame.fieldOutputs['U'].values if v.nodeLabel == label][0]
            imag = value.conjugateData if value.conjugateData is not None else (0.0, 0.0, 0.0)
            f.write('%.12g %s %s\n' % (
                frame.frequency,
                ' '.join('%.12e' % x for x in value.data[:3]),
                ' '.join('%.12e' % x for x in imag[:3])))


def write_impact(step, label, out):
    region = [r for k, r in step.historyRegions.items() if k.endswith('.%d' % label)][0]
    keys = sorted(region.historyOutputs.keys())
    u = [k for k in keys if k.startswith('U')][0]
    a = [k for k in keys if k.startswith('A')][0]
    time_u = np.asarray(region.historyOutputs[u].data)
    time_a = np.asarray(region.historyOutputs[a].data)
    np.savetxt(os.path.join(out, 'impact.txt'),
               np.column_stack([time_u[:, 0], time_u[:, 1], time_a[:, 1]]), fmt='%.12e')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
