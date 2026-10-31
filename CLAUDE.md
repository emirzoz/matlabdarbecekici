# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Virtual Impact Lab (`VirtualImpactLab/`): a MATLAB app that imports a CAD part, solves its modes once, then runs virtual impact-hammer modal tests (roving hammer or roving accelerometer) and flight-vibration checks from the cached modal database, with no further FEA. Requires MATLAB R2024b+ and only the Partial Differential Equation Toolbox; developed on R2025b desktop and used in MATLAB Online. Results are verified against Abaqus 2024 (`verification/results/VERIFICATION.md`).

`imports/` (repo root, next to `VirtualImpactLab/`) holds the STEP parts used by tests and verification.

## Commands

No build step. Run from MATLAB with `VirtualImpactLab/` as the current folder:

```matlab
VirtualImpactLab                         % launch the app
runtests('tests')                        % all tests (several minutes; app windows open and close)
runtests({'tests/testSurvey.m','tests/testPhysics.m'})   % fast, no FE solve (~3 s)
runtests('tests/testApp.m','ProcedureName','testHammerTips')   % one test
```

- `testSurvey`, `testPhysics`: signal processing / identification / flight math on small synthetic modal databases (hand-built `db` structs).
- `testPipeline`: real PDE Toolbox meshing and solves on the demo beam and `imports/*.step` (skipped via `assumeTrue` if the files are absent).
- `testApp`: drives the UI through the handle struct `VirtualImpactLab` returns.
- `AppGestureTest`: `matlab.uitest.TestCase` with real clicks/drags on the 3D view; don't touch windows while it runs. In MATLAB Online redraws are slow, so tests must poll, not assume frame timing.
- `verification/runVerification.m` and `verifyFlight.m` need desktop MATLAB plus a local Abaqus install; they regenerate `verification/results/`.

## Architecture

- **Engine (`+vil/`)** holds all numerics; the UI never computes physics itself. Pipeline: `importCAD` (reads the STEP length unit; `fegeometry` already converts to metres, so never rescale) → `meshPart` (10-node tets; retries smaller elements, falls back to rebuilding the solid from its surface tessellation) → `solveModes` (assemble K, M; remove clamped DOFs; shift-invert `eigs`; `boundary` "clamped" or "free", free-free drops 6 checked rigid-body modes) → `buildModalDatabase` (mass-normalizes, asserts orthogonality and eigen residuals, stores participation factors for base excitation).
- **Modal database `db`** is the central struct: `nodes`, `elements`, `Phi` (component-blocked: all X DOFs, then all Y, then all Z), `omega`, `frequencyHz`, `surfaceFaces/surfaceFaceId/surfaceNodes`, `fixedNodes` (empty ⇒ free-free), `participation`, `totalMass`, `config`. Projects (`saveProject`/`loadProject`) are just this struct plus tests, so impacts run without the CAD file. Stiffness/mass matrices are deliberately not stored.
- **Hammer test**: `runSurvey` simulates one hit per path via `modalPropagate` (exact per-mode state transition for a piecewise-linear force, so fs only needs > 2× top mode) and forms H1 FRFs from force/acceleration records like an analyser (exponential window when the record doesn't ring down; band limited to 1.2/contact time). It errors `vil:BandBelowModes` if the hit can't reach the first mode. `analyseSurvey` rejects weak paths, then `identifyModes` (LSCF stabilisation over model orders + least-squares residues) and compares with FE modes by frequency and MAC.
- **Shells** (`shellMatrices`, `solveShellModes`, `shellFromFaces`, `suggestSkinFaces`, `shellClampNodes`, `laminate`, `parseLayup`, `plyMaterials`): CST+DKT flat triangles, 6 DOF/node component-blocked `[ux;uy;uz;rx;ry;rz]`; the shell db has the same fields as a solid db plus `isShell` and `PhiRot`, so everything downstream works unchanged (residual flexibility pads loads to 6n). Shells are built from picked skin faces of the meshed solid, offset to the mid-surface by measured wall thickness. The new shell functions avoid `arguments` blocks, `string` and `datetime` so they run in Octave (8.4 is installable in the cloud container: `apt-get install octave`) for quick numeric checks without MATLAB.
- **Flight**: `flightResponse`/`baseTransmissibility` load modes through participation factors (clamp as rigid base); needs a clamp, so it errors `vil:FreeFree` on free-free databases. Acceleration only, no stress.
- **UI (`VirtualImpactLab.m`)**: a single programmatic `uifigure` with nested functions sharing state struct `S` and graphics handles `H`. Left tab group = workflow steps (Part, Solve, Modes, Test, Flight, Project); right tab group = results, and `syncResultTabs` reparents tabs so each step shows only its own results (hammer vs flight are kept separate on purpose). 3D-view mouse navigation is custom (`onWindowDown/Drag/Up`): left-drag rotates, right/middle-drag pans, a click without movement picks; don't reintroduce the built-in rotate interaction, it ignores drags starting on the pickable patch. Hammer tips (`hammerTips`) map to contact times; material presets (`materialPresets`) are isotropic (composites are quasi-isotropic equivalents). The returned `app` struct (`demo`, `solve`, `pick`, `runTest`, `setBoundary`, `setTip`, `showTab`, `state`, ...) is the scripting/test API: extend it when adding UI features that tests need.

## Conventions

- SI units everywhere internally (m, kg, s, Pa); UI shows mm/GPa/ms and converts at the boundary.
- Errors use `vil:<Id>` identifiers that tests assert on; give actionable messages (what to change).
- Code style is terse: short variable names in `+vil`, few comments that explain *why*. Match it.
- `README.md` documents the workflow and limits; update it when user-visible behaviour changes.

## Open items

- Retest in MATLAB Online with the next batch: `AppGestureTest/animateModeShape` (last run failed only on the timer cleanup check, since fixed) and `testSurvey/testResidualFlexibilityRestoresTruncatedFRF` (now compared below half the first omitted mode). Drag throttling fixed `dragOnModelRotatesOnly`. Confirm by hand that **Animate** visibly moves the mode.
- Agreed roadmap (single parts, MATLAB Online, no external solvers): residual flexibility (done) → in-app composite shells (done: thin monolithic laminates, one layup per shell; next could be per-face-group layups, STL surface import, sandwich). No assemblies or Craig–Bampton. Gimbal/isolator mount was skipped by the user.
