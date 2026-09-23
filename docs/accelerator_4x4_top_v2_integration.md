# Streaming accelerator v2.0 — RTL integration notes

## Scope and implementation status

The new [accelerator_4x4_top_v2](../rtl/accelerator_4x4_top_v2.sv) integrates the existing ping-pong input buffer, Moore controller, and systolic core. The v1 top and standalone ping-pong testbench are preserved. The existing datapath has only the separately documented naming refactor. No DMA, AXI, or output queue is added.

The user subsequently confirmed end-to-end PASS on [EDA Playground](https://www.edaplayground.com/x/hPw2); see the [verification report](accelerator_4x4_top_v2_verification.md) for evidence and limitations. This document records the integration contract and its original static review. Local compilation and simulation have not been executed by Codex: neither Verilator nor Icarus Verilog was found on PATH. Correctness described below is the intended behavior derived from the RTL, not a simulation or formal-proof result. The standalone buffer testbench does not verify this top-level integration.

## Public interface

The module has `DATA_W=8` and `ACC_W=32` defaults, matching signed INT8 inputs and signed 32-bit results.

| Port | Direction | Description |
|---|---|---|
| `clk` | Input | Rising-edge clock |
| `rst_n` | Input | Asynchronous active-low reset |
| `in_valid` | Input | Producer presents one paired A/B element |
| `in_ready` | Output | Pair can be accepted; forced low during reset |
| `a_data`, `b_data` | Input | Signed `DATA_W`-bit elements |
| `busy` | Output | Controller is in CLEAR, FEED, or DRAIN |
| `done` | Output | One-cycle controller DONE indication; all 16 results valid |
| `c_out[0:3][0:3]` | Output | Signed `ACC_W`-bit live accumulator results |

There are no public `load` or `start` inputs. Each group of 16 accepted paired beats forms one matrix pair, automatically scheduled in completion order. Beat `n` fills `A[n/4][n%4]` and `B[n/4][n%4]`. B is streamed row-major, not pre-transposed. Input pauses do not advance the element position.

The producer counts a transfer only on a rising edge with `in_valid && in_ready`. It should retain a pending beat until accepted. `busy` describes computation only: it is not an input-flow-control signal or a statement that both banks are occupied. Use `in_ready` for input flow control.

The fixed architecture remains 4 × 4. Width parameters are propagated to the buffer/core for consistency with v1; the existing PE requires `ACC_W >= 2*DATA_W`, and a narrower accumulator can overflow the four-product sum. The default widths retain every INT8 four-product result. No saturation is implemented.

## Why the v1 operand buffer is bypassed

The existing `matrix_operand_buffer` captures an entire A/B pair into another register array on `load`, then selects column `k` of A and row `k` of B. Connecting matrix wires alone without providing that load would leave its stored operands stale.

It could be loaded on the same edge that claims the queue head: the completed head is already visible before that edge, and the controller's CLEAR interval leaves time before the first feed. This would introduce an unnecessary full matrix copy and an additional load control signal, even though it need not add a separate start cycle.

Instead, the new top selects directly from the ping-pong buffer's retained active bank:

```text
A lane i = selected_A[i][k_counter]
B lane j = selected_B[k_counter][j]
all lane valid signals = feed_valid
```

These are combinational selections without new storage or pipeline stages. Inputs are driven to zero when `feed_valid=0`, preventing uninitialized inactive-bank data from entering idle data registers. This zeroing does not change valid timing or discard already captured data in the skew pipeline.

The existing core still delays lanes by 0, 1, 2, and 3 cycles, forwards A horizontally and B vertically, and accumulates signed products only when both operand-valid signals are asserted. A and B intermediate wires remain signed at every new data connection.

## Controller-to-buffer handshake

The new top implements:

```text
compute_start = rst_n && matrix_ready && !busy && !done
controller.start = compute_start
compute_done = rst_n && done
```

Among reachable states of the existing Moore controller, `!busy && !done` identifies IDLE. The explicit `!done` term excludes DONE, where the controller ignores start and only transitions back to IDLE.

A complete queue head is therefore claimed by the buffer on exactly the edge that the controller accepts start. The buffer switches from showing that queue head to retaining the same bank as active. While active, its `matrix_ready` is low and its bank cannot be overwritten. The controller completes CLEAR, four FEED intervals, and six DRAIN intervals before asserting done.

`compute_done` is high during DONE. The buffer samples it on the next rising edge, when the controller returns to IDLE. Thus release occurs after all datapath consumption and after the complete result has been presented. Any waiting queue entry survives release and can be claimed on the following edge.

No combinational loop is present: `matrix_ready` depends on registered buffer ownership/count, and controller `busy`/`done` depend on registered state. Start/done requests update those registers only on rising edges. Input readiness depends on registered bank states, not combinationally on `in_valid` or `compute_start`.

## Cycle-by-cycle timing

E0 is the rising edge accepting `compute_start`. Table entries describe outputs after nonblocking assignments and combinational logic settle. Datapath actions on an edge use pre-edge control values.

| Edge | Controller state after edge | Datapath action on edge | Buffer action |
|---|---|---|---|
| E0 | CLEAR; busy=1, done=0 | No new operand feed | Pop oldest completion; retain bank as active |
| E1 | FEED, k=0 | Clear accumulators | Hold active bank |
| E2 | FEED, k=1 | Capture slice k=0 into core/skew | Hold active bank |
| E3 | FEED, k=2 | Capture slice k=1 | Hold active bank |
| E4 | FEED, k=3 | Capture slice k=2 | Hold active bank |
| E5 | DRAIN | Capture slice k=3 | Hold active bank |
| E6–E10 | DRAIN | Propagate and accumulate outstanding valid data | Hold active bank |
| E11 | DONE; busy=0, done=1 | Last product reaches PE [3][3]; complete results settle | Keep active bank; compute_done now high |
| E12 | IDLE; busy=0, done=0 | Retain results | Release active bank; next queue head becomes eligible |
| E13, if a matrix is queued | CLEAR; busy=1, done=0 | Retain preceding results | Claim next bank |
| E14, if E13 started work | FEED, k=0 | Clear preceding results | Hold new active bank |

The last product consumed by PE `[i][j]` is at E(5+i+j); `[3][3]` therefore completes at E11. This matches the existing controller's six drain edges.

If a matrix's sixteenth input beat is accepted at L while the controller is idle and the queue was empty, readiness rises after L. The earliest start acceptance is L+1; it cannot start retroactively on L. Done then rises after L+12, absent reset.

The earliest start-to-start interval with queued work is 13 clocks. However, each matrix pair requires 16 input beats, so steady-state operation at one paired beat per clock is normally input-limited. The 13-clock interval describes scheduling capacity, not a claim that the input stream can supply a new pair every 13 clocks.

## Concurrency and ownership cases

| Case | Integration behavior |
|---|---|
| Loading the other bank during computation | Allowed while `in_ready=1`; active-bank selection remains fixed |
| Both banks unavailable | Input ready deasserts; unaccepted beats must not advance storage |
| Final input beat and compute_start on the same edge | Existing FIFO handles simultaneous push/pop: pop old head, retain new completion |
| Final beat with an empty queue | Enqueue now, start on a later edge |
| Final beat in the other bank on the release edge | Enqueue new pair and release old active bank; subsequent scheduling sees updated state |
| Input valid while both banks occupied on release edge | Pre-edge ready is low, so no acceptance; readiness can rise after release |
| Waiting completed bank when done asserts | Remains queued; no early pop during DONE |
| Reset at any point | Buffer ownership/queue/progress, controller, skew valid pipeline, and accumulators reset; pending work is discarded |

The standalone buffer's raw ready is high during reset. The v2 wrapper masks external `in_ready` and the buffer's input valid with `rst_n`, so its public ready/valid interface does not advertise reset-time transfers. Stored matrix bits need not be reset because invalid banks are never scheduled and non-FEED inputs are zeroed.

## Result-consumption contract

`c_out` is the existing live accumulator array, not a result FIFO or separately latched output. Treat it as a completed result only when `done` is asserted. Results appear in input matrix-pair order. Capture all elements during the DONE interval after E11 settles, or synchronously at E12 using the pre-edge high done indication.

Do not inspect the results in the same active simulation scheduling region as E11 and assume nonblocking updates have completed. A testbench should sample after an appropriate settling delay or clocking-block phase.

Results remain stable after DONE until the next accumulator clear (earliest E14), or reset. There is no output-ready handshake. A consumer that cannot capture each done result needs additional storage or flow control in a separate future change; this integration does not silently stall or retain multiple results.

## Static review record

| Review item | Finding from source inspection |
|---|---|
| Reset | Shared asynchronous reset; wrapper blocks reset-time transfers; no stale valid input is scheduled |
| Streaming acceptance | Paired row-major beats go directly to the existing buffer; no additional acceptance counter |
| Bank ownership | Shared start claims and starts the same transaction; release follows full computation |
| FIFO ordering | Scheduling uses existing queue head; no duplicate queue or bank selection logic |
| Concurrent push/pop | No top-level gating prevents a final input beat from coinciding with a valid start |
| Back-to-back work | DONE exclusion and E12 release enforce the documented E13 earliest restart |
| Operand indexing | A column and B row use the same two-bit k counter, matching v1 |
| Signed arithmetic | New paths retain signed widths; existing signed multiply/accumulate reused unchanged |
| Valid propagation | Common feed_valid per lane; existing skew and PE valid delays unchanged |
| Output validity | Existing done aligns with last PE update; consumer sampling requirements documented |
| Combinational loops | None identified; feedback paths terminate at registered state |
| Drivers/latches | New logic uses continuous assignments and module output connections, each with one driver; no incomplete procedural assignment |

No existing RTL change was required. No functional defect was established by this static review. The end-to-end testbench addresses numerical results, consecutive matrices, input pauses, reset during work, bank reuse, and input completion coincident with control transitions. The standalone buffer tests do not substitute for a top-level test.

## Tool status and suggested next checks

Tool discovery used `command -v verilator` and `command -v iverilog`; neither resolved on PATH. No local compile or simulation command was executed. The user-confirmed Playground PASS is recorded separately above.

With Verilator available, a suggested explicit-source lint invocation from the repository root is:

```sh
verilator --lint-only --top-module accelerator_4x4_top_v2 \
  rtl/accelerator_4x4_top_v2.sv \
  rtl/matrix_input_pingpong_buffer.sv \
  rtl/accelerator_4x4_controller.sv \
  rtl/accelerator_4x4_core.sv \
  rtl/input_skew.sv \
  rtl/systolic_array_4x4.sv \
  rtl/systolic_pe.sv
```

This command has not been executed. Record tool version, warnings, exit status, and source revisions when it is run. A lint pass alone is not a matrix-multiplication simulation result.
