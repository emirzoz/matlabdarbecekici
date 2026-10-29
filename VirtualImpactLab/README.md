# Virtual Impact Lab — V0.1 implementation candidate

MATLAB-only virtual impact testing with PDE Toolbox and a reusable modal cache.
No external service, Python runtime, or compiled executable is used by the app.

## Status and requirements

**Not executed in MATLAB yet.** The development container has no MATLAB installation.
Official MathWorks documentation access was blocked by the environment proxy (403).
Modern unified FEM API calls therefore require release-specific verification in MATLAB
Online before this can be described as a verified engineering application.
Target MATLAB R2024b or newer with Partial Differential Equation Toolbox; account
licenses and supported STEP import vary. No MATLAB Runtime substitute is sufficient.

## Launch (MATLAB Online)

Upload/clone this repository into MATLAB Drive, then run:

```matlab
cd matlabdarbecekici/VirtualImpactLab
VirtualImpactLab
```

Reference examples requested by the user:

```matlab
openExample("pde/ModalSuperpositionMethodForStructuralDynamicsProblemExample")
openExample("pde/STEPFileImportExample")
```

These commands open MathWorks examples; they do not run inside this cloud container.
Primary reference pages to consult in MATLAB Help: `femodel`, `fegeometry`,
`materialProperties`, `faceBC`, `assembleFEMatrices`, structural modal `solve`,
`FEStructuralModalResults`, and the two examples above.

## Required acceptance checks — not yet run

Run from this folder:

```matlab
results = runtests('tests');
assertSuccess(results);
run('examples/demoCantilever.m');
```

The demo solves three meshes, compares the first frequency with Euler–Bernoulli
beam theory (10% tolerance), checks final mesh change (5%), and computes 30 FRFs
from the final cached modal solution without another eigenvalue solve. The square
beam has repeated bending modes; compare frequencies rather than mode vectors.
Tests use independent synthetic systems for mass normalization, component DOF
mapping, reciprocity, damping, modal truncation, force scaling and complex
frequency/time response agreement after ring-down. They do not replace FEM tests.

Also verify interactively: demo geometry face labels and clamp at X=-L/2;
mode plots; STEP units/dimensions; one-solid rejection; saved MAT reload;
material/mesh changes invalidating the cache; two overlaid virtual tests.
Compare a FEM FRF against the built-in modal-superposition example before
engineering use. This independent FEM comparison remains outstanding.

## Workflow

1. Create the built-in 0.30 x 0.02 x 0.02 m beam, or import a single-solid STEP.
   Select the CAD scale **before import** (1e-3 for mm). Face labels appear in Geometry.
2. Set SI material constants, one fixed face ID, mesh size and modal frequency band.
   Solve once; assembly checks refuse incompatible DOF ordering or normalization.
3. Inspect modal frequencies and select a mode for exaggerated deformation display.
4. List selectable surface node IDs; choose hammer/sensor IDs and Cartesian directions.
   Selection uses exterior tetrahedral corner nodes, not mouse picking or midside nodes.
5. Choose assumed damping, force and sampling parameters. Run tests using the cached
   modes; Results overlays FRF magnitude/phase, force, acceleration, spectrum and displacement.
6. Save a MAT project containing the modal database and all tests. Reload for further
   impacts; geometry must be reimported to remesh a loaded database.

## Physics and limits

SI throughout. Structural DOFs are component-blocked (all X, all Y, all Z).
Fixed nodes are zeroed, then each mode is mass-normalized using assembled M.
Mass orthogonality and free-DOF eigen residuals are checked against M and K;
incompatible assembly layouts cause an error rather than silent use.
Receptance is m/N; accelerance is (m/s²)/N. FRFs are independent of force amplitude.
Time integration uses exact per-mode matrix exponentials with piecewise-linear force
interpolation. Half-sine contact requires >=20 samples; fs must be >=10 times the
highest retained mode. FFT plots show single-sided acceleration amplitudes, not FRFs.

Linear isotropic small-displacement mechanics; fixed support only; diagonal assumed
modal damping. No experimentally identified damping, residual flexibility correction,
contact nonlinearity, or rigid-body modes. Modal cutoff can bias even lower-frequency
responses; increase bandwidth and compare FRFs for convergence. A warning starts at
80% of modal cutoff, but absence of a warning is not a convergence guarantee.

No L-bracket STEP is bundled or verified. Supply a licensed single-solid L-bracket
STEP in MATLAB Online and repeat unit, clamp, mesh and modal convergence checks.
No animation or direct 3D click selection is implemented. Results export is MAT only.
Full sparse M/K storage and quadratic meshes can be large; start with the default
beam mesh and monitor MATLAB Online memory. Frequency resolution in the UI is
currently 2001 points; the standalone FRF function accepts any nonnegative grid.
