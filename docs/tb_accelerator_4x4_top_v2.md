# v2.0 accelerator end-to-end testbench

## Files and scope

[Testbench](../tb/tb_accelerator_4x4_top_v2.sv): `tb_accelerator_4x4_top_v2` directly instantiates `accelerator_4x4_top_v2` with `DATA_W=8` and `ACC_W=32`. It exercises the real input buffer, Moore controller, skew pipeline, and 16-PE array. No RTL or earlier testbench is modified.

Only public ports are used. There are no hierarchical reads, forced signals, external vectors, Python reference model, DPI calls, or UVM dependencies.

## Reference and timing checks

The clock period is 10 ns. Input signals change on falling edges. A pending beat is held until a rising-edge `in_valid && in_ready` acceptance, with a bounded retry count. The checker records the accepted paired bytes in row-major order and computes an independent reference when all 16 beats have arrived. Both operands are sign-extended to 64 bits before multiplication, and all reference sums are signed 64-bit values.

A reference transaction queue records matrix completion order. An independent elapsed-cycle model predicts automatic scheduling from accepted completed matrices; it does not infer progress from DUT busy/done. A matrix can start only on an edge after its sixteenth accepted beat. The model checks busy at E0–E10, done at E11, bank release at E12, and earliest restart at E13. Comparisons occur 1 ns after rising edges to allow nonblocking updates to settle.

The checker compares all 16 sign-extended result elements using case inequality, reporting matrix ID, row, column, expected value, actual value, and time. It also checks accumulator clearing at E1, result retention until the next clear, control X/Z mismatches, unexpected done pulses, and independently modeled bank-state input readiness. It never treats stale or partial results as complete.

Reference state is discarded on reset, while total test/result/error counters are retained. Reset checks occur before the next rising edge and while reset is held. Valid poison data during reset verifies that the wrapper keeps input ready low and does not create a transaction.

The readiness model tracks two EMPTY/LOADING/FULL/COMPUTING bank states, accepted-beat counts, write-bank selection, queued bank IDs, and active ownership. It checks ready before and after each rising edge. Pre-edge snapshots govern simultaneous acceptance, start, and release; a LOADING bank stays writable while the other computes. Release/reuse and held-payload checks are included. Expected state never advances from observed busy/done.

## Directed scenarios

The suite contains 17 reported groups (one reference-selector self-check and 16 DUT-directed scenarios) and expects 22 completed matrix results:

| Group | Coverage |
|---|---|
| Reference selector | Synthetic EMPTY/LOADING/FULL/COMPUTING combinations; model-only checks, not DUT coverage |
| Reset and idle | Asynchronous clearing, reset-time input masking, no unsolicited busy/done |
| Ten arithmetic cases | Left/right identity, zero A/B, positive values, mixed signs, all -128 × -128, -128 × 127, 127 × 127, mixed boundaries |
| Input pauses | Three-cycle valid gaps before beats 3, 9, and 15; no skipped or duplicated elements |
| Continuous stream | Eight distinct pairs without inter-matrix invalid cycles; overlapping input/computation, repeated bank reuse, result ordering |
| Partial-load reset | Abandon seven accepted beats; require a fresh full matrix after reset |
| FEED reset | Abort computation with four beats of the following pair already accepted; check recovery |
| DRAIN reset | Abort at E7 before done; suppress stale completion and verify a fresh result |

The eight continuous-stream pairs and reset recovery cases use repeatable asymmetric patterns. Byte truncation in stimulus generation is intentional. No random seed is required.

Each input wait, pending-operation age, and final drain is bounded by 64 clocks. A 200,000 ns global watchdog catches an unexpected stall outside those waits. Any accumulated failure or timeout terminates with `$fatal(1, ...)`; the successful summary reports scenario count, result count, element checks, accepted beats, overlapping beats, and stalled beats. These counters are runtime evidence, not precomputed claims of a passing simulation.

## Reachability limitation

With the current automatic scheduler and one paired input beat per clock, a pair needs at least 16 clocks to arrive. Its bank is released 13 edges after its final accepted input beat: start at the following edge, then E12 release. This precedes completion of the next continuously streamed pair. Starting from reset, normal traffic therefore cannot occupy both banks with complete/active pairs or exercise a full completion FIFO.

The test checks readiness and honors any actual stall, but does not manufacture full-bank backpressure, simultaneous FIFO push/pop, or a permanently queued E13 restart by forcing internals. The standalone buffer testbench exercises those buffer-specific cases. The continuous-stream test does exercise writing the other bank during computation and on a bank-release edge. An overlap counter must be nonzero for the suite to pass.

## Run commands

From the project root, with a compatible Verilator installation:

```sh
verilator --binary --timing -Wno-fatal \
  --top-module tb_accelerator_4x4_top_v2 \
  rtl/accelerator_4x4_top_v2.sv \
  rtl/matrix_input_pingpong_buffer.sv \
  rtl/accelerator_4x4_controller.sv \
  rtl/accelerator_4x4_core.sv \
  rtl/input_skew.sv \
  rtl/systolic_array_4x4.sv \
  rtl/systolic_pe.sv \
  tb/tb_accelerator_4x4_top_v2.sv
./obj_dir/Vtb_accelerator_4x4_top_v2
```

Review compiler warnings even though `-Wno-fatal` permits them. Four-state X/Z detection depends on the simulator's execution semantics; two-state execution cannot establish full X/Z coverage merely because case-aware operators are present. The unpacked array ports and timing constructs must be supported by the selected tool.

## Current validation status

Source inspection and whitespace checks were completed. No compatible local simulator was available, so the commands above were not executed by Codex. The user confirmed an overall end-to-end **PASS on [EDA Playground](https://www.edaplayground.com/x/hPw2)**. See the [verification report](accelerator_4x4_top_v2_verification.md) for evidence limits, unavailable runtime metrics, and unexercised backpressure cases. No formal proof is claimed.
