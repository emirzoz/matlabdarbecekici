# Antenna carrier models (payload study)

Solver input files to open with **1 Part → Import Abaqus / Ansys model…**, and
Virtual Impact Lab projects solved through the GUI.

Set-up in every file and project:

* Material: AM AlSi10Mg (LPBF), E = 70 GPa, ν = 0.33, ρ = 2670 kg/m³
* Supports: the 229 nodes on Z = 0 mm (set `FIXED`), Ux = Uy = Uz = 0; side faces free
* Payload: 0.5 kg point mass on a reference node, tied by three equations to the
  average X/Y/Z translation of the nodes on Z = 80 mm (no rotary inertia, no CG
  offset, no gravity)
* Linear tetrahedra (TetGen), SI units (m, kg, s, Pa), 8 modes

| File | What it is | f1 (Hz) |
|---|---|---:|
| `reference_0.5kg_abaqus.inp` | Abaqus input of the study (`reference_modal.inp`, `*INCLUDE` written in place) | 914.2106 |
| `reference_0.5kg_ansys.cdb` | the same model written in Ansys blocked format by `vil.exportAnsys` (SOLID285, MASS21 + RBE3, CMBLOCK FIXED + D) | 914.2106 |
| `gyroid_r5_c10_t08_0.5kg_abaqus.inp` | Abaqus input of the gyroid lattice (188,942 nodes / 576,079 elements; import takes about 1.5 min) | 266.6867 |
| `reference_0.5kg_VIL.mat`, `reference_1kg_VIL.mat` | projects (open with **6 Project → Load project…**) | 914.2106 / 657.5850 |
| `gyroid_r5_c10_t08_0.5kg_VIL.mat`, `..._1kg_VIL.mat` | projects | 266.6867 / 190.3810 |

Importing a file sets the material, supports, payload and mode count; press
**Solve modes**. The frequencies equal the stored study results (differences
≤ 10⁻¹⁰ %). In Advanced mode the payload mass can be changed or swept on the
Solve tab. `imports/demo-beam-tipmass_abaqus.inp` and `_ansys.cdb` are a small
quick check (demo cantilever, 0.5 kg tip mass, f1 = 104.57 Hz).

`VirtualImpactLab/verification/makeImportFiles.m` regenerates the input files
from the study folder and checks each by importing and solving it. The schwarz
lattice files are not versioned (size).

Modal results only: no stress or fatigue evaluation is implied.
