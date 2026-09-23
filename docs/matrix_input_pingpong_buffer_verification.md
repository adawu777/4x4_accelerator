# Matrix Input Ping-Pong Buffer — Verification Plan and Status

**Document date:** 2026-09-22
**DUT:** `matrix_input_pingpong_buffer`
**Configuration:** `DATA_W = 8`, two banks, 4 × 4 elements per A/B matrix pair
**Status:** Directed testbench implemented; simulation and formal proof not executed.

## 1. Purpose and scope

This document records the implementation-derived protocol, directed verification coverage, and proposed formal proof obligations for the matrix input ping-pong buffer. It is a verification plan and evidence record, not a formal proof certificate or a change to the design specification.

The verification boundary includes streaming input acceptance, row-major storage, bank ownership, completed-matrix ordering, compute selection, backpressure, and reset. Matrix arithmetic, the accelerator controller, and the systolic array are outside this boundary.

Only this documentation is added by this task. The DUT and testbench are unchanged.

## 2. Source baseline

| Artifact | Role |
|---|---|
| [RTL](../rtl/matrix_input_pingpong_buffer.sv) | Source of truth for implemented behavior |
| [Testbench](../tb/tb_matrix_input_pingpong_buffer.sv) | Standalone public-port verification environment |

Repository HEAD at review: `9668dc7673a7ecd31d86c7c65341e16fead7774e`.
Both files above were untracked at review, so the commit alone does not identify their contents. SHA-256 fingerprints are:

```text
RTL: 320f3aac3dff5bda1ca6d30f59fb7d57a82a58ff48828336f8f78f3136fb692f
TB:  a64a709f813b157c8a4b048629564c4d2bd21998371d292fb0f0e83cb108681a
```

Update the baseline and rerun verification after either source changes.

## 3. Interface contract derived from RTL

| Port | Direction | Meaning |
|---|---|---|
| `clk` | Input | Rising-edge sampling clock |
| `rst_n` | Input | Asynchronous active-low control reset |
| `in_valid` | Input | A/B input beat is presented |
| `in_ready` | Output | An empty or currently loading bank can accept a beat |
| `a_data`, `b_data` | Input | Signed `DATA_W`-bit elements, accepted together |
| `matrix_ready` | Output | A completed pair is queued and no computation is active |
| `compute_start` | Input | Requests selection of the oldest queued matrix pair |
| `compute_done` | Input | Releases the active compute bank |
| `compute_sel` | Output | Active bank, otherwise queue head, otherwise bank 0 |
| `a_matrix`, `b_matrix` | Output | Selected bank's 4 × 4 signed element arrays |

### 3.1 Input acceptance and storage

An input beat is accepted only when `in_valid && in_ready` is true immediately before a rising edge, with reset inactive. Sixteen accepted beats complete one matrix pair. For zero-based beat index `n`, both inputs are stored at `[n/4][n%4]`.

A cycle with no accepted beat does not advance the write position. The sixteenth beat marks the bank complete and appends its bank identifier to the two-entry completion FIFO. No arithmetic is performed on the stored values.

The writer continues its selected bank while that bank is loading or empty. If that bank is occupied, it may choose the other bank only when the other bank is empty. Reset initially selects bank 0. Bank allocation is therefore availability-driven; strict alternation is not a general interface promise.

### 3.2 Bank lifecycle

| Previous condition | Event | Result |
|---|---|---|
| Empty bank | First accepted beat | Loading bank |
| Loading bank | Accepted beats 2–15 | Continue loading |
| Loading bank | Accepted beat 16 | Full bank; append to completion FIFO |
| Full bank at queue head | Accepted compute start | Computing bank; remove queue head |
| Computing bank | Compute done | Empty bank |
| Any bank | Reset asserted | Empty control state; stored bits are not cleared |

A full bank and a computing bank must not accept new writes. At most one computation can be active. Both banks being occupied by completed/active matrices produces backpressure.

### 3.3 Compute and concurrent-event timing

All event decisions use pre-edge state. The following cases follow directly from the RTL:

| Pre-edge condition and inputs | Post-edge behavior |
|---|---|
| Queued matrix, no active computation, `compute_start=1` | Queue head becomes active |
| Active computation, `compute_start=1` | Start is ignored |
| Active computation, `compute_done=1` | Active bank is released |
| Active computation, both start and done asserted | Release only; no same-edge handoff |
| No active computation, queued matrix, both start and done asserted | Start accepted; done ignored because no computation was active before the edge |
| Final input beat plus start of an already queued matrix | Append new matrix and pop old head; queue count unchanged |
| Empty queue, final input beat plus start | Enqueue only; start cannot consume a matrix that was not ready before the edge |
| Both banks occupied, input valid plus compute done | No input acceptance on this edge; readiness can rise after bank release |

`matrix_ready` is low throughout active computation, even if the other bank contains a queued matrix. Outputs select the active bank during computation and remain unchanged by loading the other bank. With no active computation, a queued head is visible before `compute_start`.

### 3.4 Reset and data validity

After asynchronous control reset settles, `matrix_ready=0`, `in_ready=1`, and `compute_sel=0`. Matrix storage is not reset and must not be assumed to contain zeros. Data comparisons are valid only for a completely loaded queue head or active bank.

Reset discards partial input progress, queued completions, and active ownership. A new transaction requires 16 new accepted beats. `in_ready` is not gated low during reset; an external producer must not count reset-time ready/valid levels as accepted transactions because the reset branch suppresses writes.

## 4. Implemented simulation environment

The standalone testbench directly instantiates the buffer at `DATA_W=8`. It generates a 10 ns clock, drives stimulus on falling edges, samples handshake conditions at rising edges before nonblocking updates, and checks resulting outputs after a 1 ns settling delay.

The reference model records each accepted A/B beat in row-major arrays. A transaction-ID queue records completed pairs; a separate active ID records the computation in progress. Expected bank IDs are assigned explicitly for the directed sequences. Queue removal is evaluated against the old head before a newly completed pair is appended, exercising concurrent push/pop without consulting DUT internals.

The checker:

- Compares all 16 A and 16 B elements whenever a valid selected matrix is visible, including during overlap and stalls.
- Checks `compute_sel` and expected `matrix_ready`, and rejects unknown `in_ready` values.
- Uses `!==` for data/control comparisons and `===` for accepted-event detection.
- Reports scenario, matrix ID, A/B array, row, column, expected value, actual value, and time for data mismatches.
- Uses deterministic signed byte patterns, with width truncation intentional; no external vectors, Python, DPI, or UVM are involved.
- Limits input and ready waits to 40 cycles per task invocation and provides a 100,000 ns global watchdog.
- Prints per-scenario results and final test/error/comparison counts; failures terminate through `$fatal(1, ...)`.

The scoreboard uses only public ports. Its finite arrays are sized for this directed suite, not unrestricted random traffic.

## 5. Directed coverage and traceability

“Implemented” means stimulus/checking code exists; it does not mean the scenario has passed simulation.

| ID | Scenario | Principal stimulus and checks | Status |
|---|---|---|---|
| T01 | Reset | Assert reset at a falling edge; check control before next rising edge and after release; do not inspect invalid storage | Implemented, not run |
| T02 | Single matrix | Accept 16 beats into bank 0; check ready, start, all A/B elements, release | Implemented, not run |
| T03 | Input pause | Pause four cycles after six accepted beats; resume without skipped/duplicated elements | Implemented, not run |
| T04 | Ping-pong overlap | Compute bank 0 while loading bank 1; continuously check active matrix stability | Implemented, not run |
| T05 | Backpressure | Both banks occupied; present four poison beats; check no acceptance and verify both matrices when selected | Implemented, not run |
| T06 | FIFO order | Queue two matrices before starting; consume in order; check simultaneous done/start releases only | Implemented, not run |
| T07 | Simultaneous push/pop | Accept bank 1's final beat while starting bank 0; verify both acceptance events and subsequent order | Implemented, not run |
| T08 | Bank reuse | Release bank 0, compute bank 1, reload bank 0, then consume the new matrix | Implemented, not run |
| T09 | Partial-load reset | Reset after seven beats; verify no stale completion; require 16 new beats and verify new contents | Implemented, not run |

T05 intentionally continues from T04's occupied-bank state. Other scenario groups use explicit reset or the documented preceding state. These are coverage intentions, not measured code, assertion, or functional-coverage percentages.

## 6. Proposed formal verification plan

No formal harness, executable assertions, proof configuration, or proof results currently exist in this work. The following properties are requirements for a future implementation, not claims of proven behavior.

### 6.1 Reference model and assumptions

Build a harness that instantiates only the buffer and uses public-port history to model accepted elements, partial length, completion order, active ownership, and bank availability. The model must advance its input history only on actual accepted beats and must derive expected readiness independently from its resource model rather than using DUT readiness as the expected answer.

Use arbitrary input bytes and arbitrary input pauses. Establish an initial reset and guard history-dependent properties until reset has been observed. For clocked proofs, state the reset sampling model explicitly; sampled reset assertions alone do not prove asynchronous behavior between edges.

Do not assume that `matrix_ready` or `in_ready` is correct: they are outputs under verification. Do not assume commands occur only when accepted; illegal/unaccepted start and done combinations are useful safety cases. Payload stability across stalled cycles is not necessary to prove this buffer's accepted-beat storage contract; if imposed for system integration, record it as an additional source assumption.

Safety proofs require no promise that a producer eventually finishes a matrix or that computation eventually ends. Liveness claims do require explicit fairness or bounded-response assumptions about future accepted input beats, compute requests, and compute completion. Ordinary two-state formal proofs do not replace four-state simulation checks for X/Z propagation.

### 6.2 Safety property inventory

| ID | Required invariant or transition | Directed support |
|---|---|---|
| F01 | Reset removes all model ownership and pending work; after settling, ready outputs match reset contract | T01, T09 |
| F02 | Partial position advances exactly once per accepted beat; stalls do not advance it | T02, T03 |
| F03 | Completion occurs exactly on the sixteenth accepted beat; a partial pair is never offered for compute | T02, T03, T09 |
| F04 | Every valid selected A/B element equals its accepted input history in row-major order | T02–T09 |
| F05 | Input acceptance cannot alter a queued or computing bank | T04, T05, T08 |
| F06 | `matrix_ready` equals “reference queue nonempty and no reference computation active” | T01–T09 |
| F07 | Accepted start chooses the oldest completed pair exactly once | T06, T07 |
| F08 | Active selection and all active elements remain stable until done or reset | T04, T05, T08 |
| F09 | Queue length remains within 0–2; no bank is simultaneously queued and active; occupied banks never exceed two | T04–T08, partial support |
| F10 | Simultaneous completion/start removes the old head and retains the new completion without loss/duplication | T07 |
| F11 | Done releases only the previously active bank; inactive done does not discard queued work | T06, T08; inactive-done case not directed |
| F12 | Start while active cannot switch bank; simultaneous active done/start releases only | T06, partial support |
| F13 | `in_ready` matches independent bank availability, including a partially loaded bank | T01, T03, T05, T08, partial support |
| F14 | Reset prevents pre-reset partial or completed transactions from appearing in the new epoch | T09; queued/active reset not directed |
| F15 | With no active computation, selection is the queue head, or bank 0 if the queue is empty | T01–T09, partial support |

After initialization, conservation checks should relate accepted completions, accepted starts, completed computations, queue occupancy, and active occupancy within each reset epoch. Evaluate concurrent events from the same pre-edge reference state. Reset starts a new epoch rather than requiring old transactions to finish.

### 6.3 Reachability and non-vacuity covers

Require witnesses for both banks becoming active; two queued completions; a computing bank plus a complete waiting bank; several stalled input cycles followed by release; simultaneous final-beat/start; repeated bank reuse; and reset during loading, queued work, and active computation. Reach an accepted start and a valid data comparison for every applicable data-integrity property so proofs cannot pass solely because no transaction is allowed through the assumptions.

Prove safety with an appropriate induction or unbounded engine when available. Record tool, version, engine, assumptions, source hashes, and result for every property. A bounded search with no counterexample must be reported with its depth; it is not an unbounded proof. Cover success establishes reachability, not safety.

## 7. Execution procedure and evidence

### 7.1 Current evidence

| Activity | Actual result |
|---|---|
| Read complete RTL and testbench | Completed |
| Inspect directed scenarios and source organization | Completed |
| Search for simulation/formal run configurations | No relevant run script or formal configuration found |
| Check executable availability with `command -v` | `verilator`, `iverilog`, `sby`, and `yosys` not found on PATH at documentation review |
| Compile and simulate | Not executed |
| Execute formal properties | Not executed; harness/properties not implemented |
| Simulation coverage or proof coverage | Not measured |

Static review found no confirmed DUT functional defect. That observation is limited by the absence of compilation, simulation, and proof evidence.

### 7.2 Suggested simulation commands — not executed

Run from the repository root after installing a compatible simulator:

```sh
verilator --binary --timing -Wno-fatal \
  --top-module tb_matrix_input_pingpong_buffer \
  rtl/matrix_input_pingpong_buffer.sv \
  tb/tb_matrix_input_pingpong_buffer.sv
./obj_dir/Vtb_matrix_input_pingpong_buffer
```

These are proposed commands, not a validated tool invocation. Review all compilation warnings; `-Wno-fatal` permits warning diagnostics without treating them as compile errors. Do not accept a run unless compilation succeeds, all nine scenarios report PASS, the final summary reports zero errors, and the simulator exits successfully. Also review whether the simulator preserves the four-state behavior needed for the intended X/Z checks; syntax compatibility alone does not establish that coverage.

If compilation fails because the simulator does not support the unpacked array ports, timing controls, or other required constructs, record the diagnostic and tool version. Do not report a simulation pass or change the DUT to work around a testbench-tool limitation without separate authorization.

Retain build output, simulation output, exit status, source hashes, simulator version, and invocation for a reproducible result. Formal commands will be defined only after a harness and engine configuration exist.

## 8. Open coverage items and protocol observations

The current suite does not exhaustively explore all interleavings or parameter values. Additional work should address reset during queued/active operation; start with an empty queue; final-beat/start with an initially empty queue; inactive done; prolonged held commands; done coincident with accepted input into the other bank; repeated FIFO pointer wrapping without reset; and a cycle-by-cycle independent `in_ready` availability model.

The current public-port scoreboard validates accepted traffic and checks ready in selected scenarios, but does not independently predict `in_ready` on every cycle. Persistent unexpected stalls are bounded by timeouts; shorter unnecessary stalls may escape the current checks. This is a test coverage limitation, not an established DUT defect.

Protocol observations to preserve in integration:

- Matrix output bits may be stale or unknown when no valid complete matrix is selected.
- A bank released on an edge cannot retroactively accept input that was backpressured before that edge.
- A matrix completed on an edge is not available to a start request unless a different completed matrix was already ready before that edge.
- Holding `compute_start` high can accept work on a later eligible edge; commands are level-sampled, not edge-detected.
- Reset-time `in_ready=1` does not imply data capture while reset is asserted.

Any DUT defect discovered by later testing must be reported separately before changing RTL. This document does not authorize a release or revise the existing design specification.

## 9. Completion criteria

Simulation sign-off requires a successful compile, all nine scenario passes, zero accumulated errors, clean termination, reviewed warnings, and archived execution evidence for the identified sources. An optional injected-fault run should demonstrate that representative data or ordering corruption causes a nonzero exit.

Formal sign-off additionally requires an implemented and reviewed harness, explicit assumptions, passing safety proofs with documented scope, non-vacuity cover witnesses, and disposition of every failure or inconclusive result. Neither simulation nor formal sign-off has been achieved at this baseline.
