# v2.0 — Streaming 4×4 INT8 Matrix Accelerator

## Architecture and interfaces

v2.0 adds `accelerator_4x4_top_v2`, integrating paired signed INT8 streaming inputs, a two-bank ping-pong matrix buffer, the existing Moore controller, input skew, and a 16-PE systolic array with signed 32-bit accumulation.

- `in_valid` / `in_ready` accept one paired A/B element per rising-edge handshake. Sixteen accepted row-major beats form a complete matrix pair.
- Completed pairs are automatically selected in FIFO order. The next pair can load while the current pair computes; bank availability controls input backpressure.
- Direct A-column/B-row selection feeds the retained active bank without another full-matrix copy.
- `busy` identifies computation; one-cycle `done` identifies a valid 4×4 result on `c_out`. Results are live accumulators with no output-ready handshake or result queue.
- Active-low reset discards partial, queued, and active work.

Current datapath names are `systolic_pe` and `systolic_array_4x4`, with matching unit-test names. This naming refactor preserves arithmetic and cycle timing. The v1.0 top-level module, historical specifications, release, and tag are preserved.

## Verification

**End-to-end simulation PASS on EDA Playground was confirmed by the user.**

[EDA Playground — v2.0 end-to-end verification](https://www.edaplayground.com/x/hPw2)

DUT: `accelerator_4x4_top_v2`. Testbench: `tb_accelerator_4x4_top_v2.sv`.

The standalone SystemVerilog testbench includes signed 64-bit reference arithmetic, all-element scoreboarding, independent bank-state readiness prediction, controller timing checks, reset recovery, continuous input, ordering, and bank reuse. Codex did not independently run the Playground simulation or a local simulator. Detailed runtime logs, numerical coverage, simulator settings, and an exact remote-source match are not independently confirmed.

Full-bank backpressure, stalled-beat retry, and simultaneous FIFO completion/start are not reachable through normal traffic in the fixed automatic top-level schedule. Reference-selector self-checks are not DUT coverage. Standalone buffer stimulus addresses these cases separately, without an additional passing-run claim. No exhaustive formal proof, synthesis, hardware, or timing-closure result is claimed.

## Documentation

- [Implemented interface, architecture, and cycle timing](accelerator_4x4_top_v2_integration.md)
- [End-to-end verification report and coverage limitations](accelerator_4x4_top_v2_verification.md)
- [Testbench usage and reproduction commands](tb_accelerator_4x4_top_v2.md)
- [Standalone buffer verification plan](matrix_input_pingpong_buffer_verification.md)
- [Current naming and historical specification mapping](rtl_naming_refactor.md)

The local revision-0.1 PDF marked implementation/simulation pending is excluded from this release commit. The implemented contract is documented in the integration notes above.
