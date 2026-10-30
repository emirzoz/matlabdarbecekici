# Clamp-motion check against Abaqus 2024

Same mesh, damping 2 %, clamp shaken along Z, monitor at the free point farthest from the clamp.
PSD (the example shape in the app): 10 Hz 0.001, 40 Hz 0.01, 500 Hz 0.01, 2000 Hz 0.0025 g²/Hz.

| Case | Modes | Lines | Transmissibility rel. error | Random MATLAB (g rms) | Random Abaqus (g rms) |
|---|---|---|---|---|---|
| demo | 30 | 393 | 9.78e-08 | 18.01 | 18.08 |
| bearing | 30 | 365 | 3.21e-07 | 3.48 | 3.441 |
