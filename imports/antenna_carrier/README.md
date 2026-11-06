# Antenna carrier models (payload study)

Ready tetrahedral meshes and Virtual Impact Lab projects solved **through the GUI**
(`verification/reproducePayloadStudy.m` with `SaveProjects`): Import tet mesh →
material → plane supports → payload → Solve modes → Save project.

Set-up for every project:

* Material: AM AlSi10Mg (LPBF), E = 70 GPa, ν = 0.33, ρ = 2670 kg/m³
* Supports: plane Z = 0 mm ± 0.05 mm, Ux = Uy = Uz = 0 (side faces free)
* Payload: plane Z = 80 mm ± 0.05 mm, translational inertia mass on the average
  X/Y/Z translation of those nodes (no rotary inertia, no CG offset, no gravity)
* Linear tetrahedra (TetGen), mesh coordinates in metres, 8 modes

| Model | Mesh | Carrier (g) | f1 @ 0.5 kg (Hz) | f1 @ 1.0 kg (Hz) |
|---|---|---:|---:|---:|
| reference | 8,648 nodes / 33,397 el. | 156.99 | 914.2106 | 657.5850 |
| gyroid_r5_c10_t08 | 188,942 nodes / 576,079 el. | 53.20 | 266.6867 | 190.3810 |
| schwarz_r5_c10_t08 | 189,249 nodes / 593,084 el. | 74.94 | 384.7647 | 275.2316 |

These equal the earlier study results (differences ≤ 3·10⁻¹⁰ %).

Files:

* `*_tetmesh.mat`: `nodes` (N×3, m) and `elements` (E×4, 1-based). Open with
  **1 Part → Import tet mesh (.mat)…** (Units: auto). The reference mesh was taken
  from its earlier project; it is saved with `units = "m"`.
* `*_0.5kg_VIL.mat`, `*_1kg_VIL.mat`: projects with modal database and solve set-up.
  Open with **6 Project → Load project…**; supports, payload and markers are restored,
  and **Solve modes** re-solves on the stored mesh.

Modal results only: no stress or fatigue evaluation is implied.
