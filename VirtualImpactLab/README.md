# Virtual Impact Lab

Import a part, solve its modes **once**, then run as many virtual impact-hammer
tests as you like from the cached modal database: pick where the hammer hits
and where the accelerometer sits, and get the force pulse, acceleration
response, spectrum and FRF in seconds, with no further FEA.

Runs in MATLAB desktop and **MATLAB Online**. Requires MATLAB R2024b or newer
and **Partial Differential Equation Toolbox** (nothing else; developed and
tested on R2025b). The MATLAB results are verified against Abaqus 2024; see
[verification](#verification-against-abaqus).

## Start

```matlab
cd VirtualImpactLab
VirtualImpactLab
```

In MATLAB Online, upload or clone the repository into MATLAB Drive and run the
same two lines.

## Workflow

| Step | What you do | Notes |
|---|---|---|
| 1 Part | **Import STEP / STL…** or **Demo cantilever**. The part is meshed straight away with an element size suggested from its size. Or **Import tet mesh (.mat)…**: a ready linear (4-node) or quadratic (10-node) tetrahedral mesh, solved without remeshing. | STEP length units are read from the file and converted to metres. STL has no units: if the largest dimension is > 2, millimetres are assumed. Mesh files: `nodes` (N×3) + `elements` (E×4/10, 1-based), e.g. TetGen `*_tetmesh.mat`, or the mesh inside a VIL project. **Units: auto** uses a `units` variable, then a `tetVolume_mm3` check, then the size; or choose m / mm. Connectivity, unused nodes and element volumes are checked. The Part tab shows the coordinate ranges: check them before choosing planes. |
| 2 Solve | Choose a material preset (steels, aerospace aluminium 2024/7075/7050, quasi-isotropic CFRP and GFRP, additively manufactured Ti-6Al-4V, AlSi10Mg, Inconel 718, 316L, PA12) or enter E, ν, ρ. Presets also set a typical damping ratio. Choose **Supports**: **Clamped** or **Free-free** (no supports, as a part hung on soft cords). A clamp is selected by **CAD faces** (click **Pick fixed faces on model**, then the faces; click again to release) or by **Coordinate plane** (axis, position and tolerance in mm: every node on the plane gets Ux = Uy = Uz = 0). Optionally **Add payload (antenna) mass** (kg, 0.5 kg when switched on), attached to faces or a plane. Set how many modes to compute. **Solve modes**. **Run mass sweep** solves again for each payload mass in the list. | Use **Flip** to see faces underneath the part. **Face IDs** labels every CAD face. Free-free removes the 6 rigid-body modes; flight simulation needs a clamp. Supports are drawn as blue faces or squares, the payload region as orange faces or dots with a star at its centroid. Changing the material, supports or payload retires the previous solution. See [Payload mass](#payload-antenna-mass). |
| 3 Modes | Click a row to see the mode shape; **Animate** to animate it. | Colour is relative displacement magnitude. |
| 4 Test | Choose **Roving hammer, fixed accelerometer** or **Roving accelerometer, fixed hammer**. **Pick** the fixed point, then **Add** as many roving points as you like. Directions: **Into surface** / **Out of surface** follow the local surface normal, or ±X/Y/Z. Set the force, choose the **Hammer tip** (**Rubber** for low modes, **Steel** for high modes; the app suggests one after solving) and the damping. **Advanced** adds plastic and aluminium tips, contact time, record length, sample rate and rejection. **Run test**. | Under the tip, the test tab shows the band the hit excites and how many modes fall inside it. Small stiff parts (a 20 mm bracket starts near 20 kHz) need the steel tip. Results appear on **Hammer: modal ID** and **Hammer: FRF & signals**. Weak responses are removed automatically; the **Use** column overrides that and refits at once. No eigen solve happens here. |
| 5 Flight | Choose an aircraft profile, or enter shaft speeds, tones and a random PSD. Choose the axis the clamp shakes along and a monitor point. **Simulate flight vibration**. | The verdict is at the top of the **Flight: response** tab. The transmissibility plotted there is clamp-to-monitor under base shaking, not a hammer FRF. Tone amplitudes and PSD presets are examples: enter measured or specified levels. |
| 6 Project | Save/load the modal database, the test and the solve set-up (`.mat`); export signals, FRFs and identified modes as CSV; export an Abaqus `.inp`; **Compare projects…** side by side. | A loaded project can run new impacts without the CAD file, and **Solve modes** re-solves it on its stored mesh: the mode table then shows the loaded and new frequencies. Loading restores material, supports, payload and their 3D markers, also for the earlier payload-study projects (`payloadKg`, `payloadModel`, `tipNodes`, `fixedNodes` with empty `fixedFaces`). Compare groups projects by material, supports, payload mass and model (A, B, …) and lists what differs. |

Picking happens on mouse release and only if the mouse did not move, so dragging
to rotate never changes the clamp or the points. Picking also stops when you
solve or change tab. The **Solve** tab shows how much of the surface is clamped,
in red above 35 %. The clamp sets the frequencies: clamping more faces of the
bearing housing moves its first mode from 3.5 kHz to above 40 kHz.

Each step shows only its own results on the right: step 4 shows the two Hammer tabs, step 5 the Flight tab, and step 6 all of them. The 3D model and the **Verification** tab (the stored Abaqus comparison) are always there.

Scripted use without the UI: see `examples/demoCantilever.m`.

## What the engine computes

* **Mesh**: 10-node quadratic tetrahedra (PDE Toolbox `generateMesh`).
* **Modes**: PDE Toolbox assembles K and M; clamped DOFs are removed and the
  lowest *N* modes are found by shift-invert `eigs`, plus every further mode
  up to an optional frequency. Modes are mass-normalized, and mass
  orthogonality and eigen residuals are checked against the assembled
  matrices before the database is accepted.
* **FRF**: modal superposition, receptance (m/N) and accelerance
  ((m/s²)/N), constant modal damping ratio ζ for every mode.
* **Impact**: half-sine force pulse. Each mode is integrated exactly for a
  piecewise-linear force (matrix exponential of the augmented state), so the
  sample rate only has to exceed twice the highest retained mode. By default
  fs is chosen automatically (2.56 × the highest mode, and at least 25
  samples over the contact).
* **Roving test**: one simulated hit per path. Each FRF comes from the force
  and acceleration records (H1 = Gxf/Gff), as on an analyser. A record too short
  to ring down gets an exponential window, and the decay it adds is removed from
  the damping. The band ends at 1.2/contact time, where the half-sine is 15 dB
  down. There is no noise, so one hit per path is enough and there is no
  coherence to report.
* **Weak responses**: each path's RMS FRF level is compared with the median. A
  path more than 20 dB below it (adjustable) is left out of the fit.
* **Natural frequencies and damping**: a rational-fraction fit (LSCF) over a
  range of model orders keeps the poles that repeat between orders; a
  least-squares fit of every FRF to those poles gives the modal constants.
  Identified modes are compared with the FE modes by frequency and MAC. FE modes
  the test cannot see are listed with the reason: points near a node, too close
  to a neighbour, or above the band.
* **Flight**: the clamp is shaken as a rigid base. Each mode is loaded through
  its participation factor (Φ'·M·r), which gives the transmissibility from clamp
  to monitor. Tones are order × shaft speed; random response integrates the PSD
  through the transmissibility. A mode counts as excited if at resonance it adds
  at least 10 % of the clamp motion at the monitor. Output is acceleration only:
  no stress or fatigue.

### Payload (antenna) mass

The payload is a translational inertia mass that follows the average X, Y
and Z translation of its attachment nodes:

    u_payload = B·u,   M_total = M_structure + m·BᵀB

B (3 × 3n) averages each translation over the N selected nodes (1/N per
node). The payload adds no stiffness, no rotary inertia and no offset of its
centre of mass, and it does not tie the attachment nodes to each other
(adding m/N to every node would be a different model). It is inertia only:
no gravity load or static preload is computed. Then K·φ = ω²·M_total·φ is
solved with the clamped DOFs removed. Mode normalization, the eigen residual
and the mass-orthogonality check use M_total, and so do the participation
factors Φᵀ·M_total·r, so FRFs, impacts, flight transmissibility and effective
masses all include the payload. The Solve tab reports structure, payload and
total mass separately. Payload nodes that are also clamped are refused.

A clamp by coordinate plane fixes Ux = Uy = Uz at every node within the
tolerance of the plane; solid tetrahedra carry no rotation DOF, so this is a
full clamp of those nodes. The **Payload mass sweep** runs one complete eigen
solve per mass (K and M are assembled once); frequencies are never scaled.
`verification/reproducePayloadStudy.m` repeats the antenna-carrier study
through the app and writes `verification/results/payload_reproduction.csv`.

### Limits

Linear, isotropic, small-displacement elasticity; fixed (clamped) or free-free
supports only (no springs; free-free FRFs leave out the rigid-body mass line); modal damping is assumed, not measured; no contact stiffness for the
hammer tip (the force pulse is prescribed); no residual-flexibility
correction, so include modes well above the highest frequency of interest.
Single-solid parts only.

## STEP import: what was wrong and what changed

The original app never produced modes for imported STEP parts. Running it in
R2025b showed why:

1. **Double scaling.** `fegeometry` already converts STEP coordinates to
   metres using the unit declared in the file (a 40 mm block imports as
   0.040 m). The UI then applied a default "CAD scale" of 0.001, shrinking
   every part 1000×. The first mode moved into the MHz range and the
   2 kHz band was empty. Import now reads the declared unit and applies no
   extra scale.
2. **Meshing failures.** `bearing-housing.step` will not mesh from its
   B-rep at any Hmax/Hmin. Meshing now retries with smaller elements and,
   if CAD meshing still fails, rebuilds the solid from its own watertight
   surface tessellation, which meshes reliably. Curved faces become faceted
   (the UI and the verification report say so).
3. **Frequency band guessing.** A fixed 1–2000 Hz band contains no modes
   for small stiff parts (`corner-bracket-2020.step` starts at ~20 kHz).
   The solver now computes the lowest *N* modes directly, which is also
   about 20× faster than searching for a band with repeated
   `solve(...,FrequencyRange=...)` calls (bearing housing: 10 s instead of
   190 s).
4. **Fixture by number.** Face ID 1 was the default clamp, which on a STEP
   part is an arbitrary face. Faces are now picked on the 3D model, several
   at once if needed.
5. **The tests never ran.** `runtests` found no tests because the test
   functions did not start with `test`.
6. `nema17-mount-bracket.step` (a FreeCAD export) is rejected by MATLAB as
   "not a solid". The importer now says so and suggests re-exporting a
   single solid body or an STL.

## Verification against Abaqus

`verification/runVerification.m` (desktop only, needs Abaqus) checks every
case two ways:

* **Same mesh.** The MATLAB mesh, material and clamp are written to an Abaqus
  input file (C3D10, same node numbering) and solved with `*FREQUENCY`
  (Lanczos), `*STEADY STATE DYNAMICS` (modal FRF) and `*MODAL DYNAMIC` (the
  same half-sine hammer pulse). This isolates the MATLAB eigen solution, mode
  normalization, DOF mapping, FRF and time integration from meshing
  differences.
* **Independent.** Abaqus/CAE imports the STEP file itself, meshes it with its
  own C3D10 mesher at the same element size, clamps the faces nearest to the
  MATLAB clamp, and extracts modes. This checks CAD import, units, face
  selection and meshing end to end. Mode shapes are compared by MAC on the
  nearest MATLAB node to each Abaqus node.

The full report with plots is in
[`verification/results/VERIFICATION.md`](verification/results/VERIFICATION.md).

Results (steel, 2% modal damping, R2025b vs Abaqus 2024):

| Case | Nodes | Same mesh: max freq. error | Same mesh: min MAC | Same mesh: FRF / impact rel. error | Independent Abaqus/CAE: max freq. error, min MAC | MATLAB refinement 0.7h: max change |
|---|---|---|---|---|---|---|
| Demo cantilever (0.007 % from Euler–Bernoulli theory) | 8,188 | 0.004 % | 1.0000 | 1e-6 / 7e-7 | n/a (no STEP) | 0.21 % |
| block.step | 4,758 | 0.001 % | 1.0000 | 9e-7 / 2e-6 | 0.08 %, 0.991 | 0.14 % |
| bearing-housing.step | 26,398 | 0.002 % | 1.0000 | 7e-7 / 1e-6 | Abaqus cannot mesh this CAD either | 0.83 % |
| corner-bracket-2020.step | 10,258 | 0.002 % | 1.0000 | 8e-7 / 1e-6 | 0.57 %, 0.993 | 1.15 % |

What this shows:

* On the same mesh, MATLAB and Abaqus agree to solver precision for
  frequencies, mode shapes, FRFs and the hammer-impact time history. The
  modal database, mass normalization, DOF mapping, FRF and the exact time
  integration are correct.
* With Abaqus importing and meshing the STEP itself, frequencies agree within
  0.6 % and mode shapes within MAC 0.99. Units, CAD import, clamp face
  selection and meshing are consistent.
* The remaining differences are mesh-size effects of the same order as the
  MATLAB refinement change (≤ 1.2 % at the default sizes). Use a finer
  element size when you need tighter numbers.
* `bearing-housing.step` (and its rev-b) cannot be meshed from its B-rep by
  MATLAB **or** Abaqus/CAE, not even with Abaqus virtual topology. The CAD
  itself needs repair. MATLAB meshes its faceted tessellation instead.

No correction factors are applied to the MATLAB results. Where the two
solvers agree to solver precision on the same mesh, a remaining difference
from the independent model is discretization or geometry (e.g. faceting),
and the cure is a finer mesh, not a fudge factor.

To re-run (about 5 minutes for all parts):

```matlab
cd VirtualImpactLab/verification
runVerification            % or runVerification("block")
verifyFlight               % clamp motion: results/FLIGHT.md
```

Roving tests are checked against known answers (`tests/testSurvey.m`). Clamp
motion is checked against Abaqus `*BASE MOTION` on the same mesh:
transmissibility agrees to 1e-7 and random response to about 1 % (18.0 vs 18.1 g
rms on the beam, 3.48 vs 3.44 g rms on the bearing housing). Abaqus integrates
the PSD on its own frequency points, so its random result depends on that grid:
with 15 uniform points per interval the beam read 26.9 g rms.

## Tests

```matlab
cd VirtualImpactLab
results = runtests('tests'); disp(table(results))
```

`tests/testPhysics.m` uses small synthetic systems (no FEM): reciprocity,
damping, truncation, force scaling, time/frequency agreement, mass
normalization, DOF mapping, surface normals, vector directions, modal
cutoff and mode pairing. `tests/testPipeline.m` runs the FEM path on the
STEP files in `../imports` (skipped if they are missing): unit handling,
meshed mass, clamped DOFs, beam theory, the tessellation fallback and the
non-solid error. `tests/testSurvey.m` checks roving tests and flight response
against known answers: recovered frequencies, damping and modal constants,
window correction, weak-point removal, a fixed point on a node, the Miles
equation and the resonance verdicts. `tests/testApp.m` drives the UI through its
scripting handle (`app = VirtualImpactLab`): demo part, face toggling, solve,
roving tests in both modes and a flight run.
`tests/AppGestureTest.m` presses the real Pick buttons, clicks and drags on the
3D model (matlab.uitest), with rotate/zoom interactions active.
`tests/testPayload.m` checks the payload mass matrix against an independently
built B, that 0 kg reproduces the earlier solver exactly, plane and face
selections (midside nodes included), selection and mesh-import errors, units,
project round trips and the older payload-study layout, the mass sweep and the
grouping in project comparisons. `tests/testAppPayload.m` runs the same
features through the UI, including save/load and re-solving a loaded project.

## Files

```
VirtualImpactLab.m        UI (programmatic uifigure)
+vil/importCAD.m          STEP/STL import, unit detection
+vil/meshPart.m           meshing with retries and tessellation fallback
+vil/extractSurface.m     exterior triangles labelled with CAD face IDs
+vil/importMesh.m         ready tetrahedral mesh import (units, connectivity, volumes)
+vil/selectNodes.m        node selection by faces, coordinate plane or list
+vil/solveModes.m         assembly + eigs (node clamps, payload mass), modal database
+vil/payloadSweep.m       one full modal solve per payload mass
+vil/projectSettings.m    solve set-up of a project, older layouts included
+vil/compareProjects.m    projects side by side, grouped by assumptions
+vil/buildModalDatabase.m mass normalization and consistency checks
+vil/calculateFRF.m       modal FRF
+vil/simulateImpact.m     one hammer hit, one sensor
+vil/modalPropagate.m     exact modal time integration shared by all hits
+vil/runSurvey.m          roving test: signals to FRFs
+vil/analyseSurvey.m      weak-response removal, comparison with FE modes
+vil/identifyModes.m      natural frequencies, damping, modal constants
+vil/flightProfile.m      aircraft presets
+vil/flightResponse.m     tones, RPM sweep, random response, resonance verdicts
+vil/baseTransmissibility.m  clamp-to-monitor transmissibility
+vil/exportAbaqus.m       same-mesh Abaqus input file
+vil/compareModes.m       MAC pairing and frequency error
verification/             Abaqus runners, ODB reader, report and results
```
