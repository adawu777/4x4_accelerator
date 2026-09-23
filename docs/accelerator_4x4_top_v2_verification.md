# 4×4 INT8 Matrix Accelerator v2.0 — End-to-End Verification Report

| Verification record | Value |
|---|---|
| **Verification status** | **PASS — user-confirmed overall end-to-end result** |
| **Verification platform** | **EDA Playground** |
| **Simulation link** | [EDA Playground — v2.0 end-to-end simulation](https://www.edaplayground.com/x/hPw2) |
| **Verification target** | `accelerator_4x4_top_v2` |
| **Testbench** | `tb_accelerator_4x4_top_v2.sv` |
| Configuration reviewed | Fixed 4×4 matrices; signed INT8 inputs; signed 32-bit accumulators |
| Report review date | 2026-09-22 |

## 1. Verification Summary

The v2.0 end-to-end simulation has **PASSED on EDA Playground, as confirmed by the user**. The reported run is linked at [https://www.edaplayground.com/x/hPw2](https://www.edaplayground.com/x/hPw2).

Verification covers the complete streaming input-to-result path: paired input acceptance, matrix assembly, ping-pong storage, automatic scheduling, operand feeding, input skew, systolic propagation, signed multiplication and accumulation, and output comparison. The implemented testbench also checks reset recovery, bank ownership, input readiness, transaction ordering, and controller timing.

The overall PASS is recorded from the user's explicit confirmation. The linked page could not be retrieved through the available inspection tools, and no detailed simulation log was found in the project. Consequently, this report does not independently confirm the simulator name/version, compilation options, individual scenario messages, or numerical summary. These details remain unconfirmed without changing the user-confirmed overall PASS status. No simulation was rerun while editing this report.

### Evidence and source basis

| Evidence | Interpretation |
|---|---|
| User confirmation and supplied Playground link | Supports the overall end-to-end PASS record |
| Current RTL and testbench inspection | Supports architecture, implemented checks, stimulus inventory, and RTL-derived timing |
| Per-scenario runtime log and numerical summary | Not available for independent inspection |
| Coverage database or formal proof report | Not available; no exhaustive-verification claim |

The current seven RTL sources and top-level testbench were reviewed; their fingerprints were rechecked and are unchanged from the preceding complete source review. The inspected testbench SHA-256 is `9c139f708f06172da5c4a8b6925aef02aa9952a28a4e630937b9c94e508d0e9f`. This identifies the local source described here, not an independently established match to the remote Playground source snapshot.

Existing context includes the v1.0 accelerator/controller specifications, [integration notes](accelerator_4x4_top_v2_integration.md), [earlier testbench notes](tb_accelerator_4x4_top_v2.md), [standalone buffer verification plan](matrix_input_pingpong_buffer_verification.md), and [naming record](rtl_naming_refactor.md). The current source takes precedence over older scenario counts and historical naming. Historical v1.0 PASS claims are not used as evidence for this v2.0 result. This document is an engineering verification report, not a formal mathematical proof.

## 2. DUT Architecture

The integrated data path is:

**Streaming matrix inputs → ping-pong input buffer → controller-directed operand feeding and input skew → 4×4 systolic array → output matrix.**

The controller supplies sequencing and valid signals rather than carrying operand data.

### 2.1 Integrated hierarchy

```text
accelerator_4x4_top_v2
├── matrix_input_pingpong_buffer
├── accelerator_4x4_controller
├── combinational A[:,k] / B[k,:] selection
└── accelerator_4x4_core
    ├── input_skew
    └── systolic_array_4x4
        └── 16 × systolic_pe
```

The v2 wrapper bypasses the v1 operand-copy buffer. The active ping-pong bank already retains the complete operands, so the wrapper selects `A[lane][k_counter]` and `B[k_counter][lane]` directly. All lane-valid inputs equal `feed_valid`; operand values are zeroed outside FEED. `input_skew` delays lane N by N clocks, and the array propagates A horizontally and B vertically with matched valid signals.

### 2.2 Public interface

| Port | Direction | Default width / shape | Contract |
|---|---|---|---|
| `clk` | Input | 1 bit | Rising-edge sampling clock |
| `rst_n` | Input | 1 bit | Asynchronous active-low reset |
| `in_valid` | Input | 1 bit | Paired A/B input element is presented |
| `in_ready` | Output | 1 bit | Input can be accepted; masked low during reset |
| `a_data` | Input | Signed 8 bits | Next row-major A element |
| `b_data` | Input | Signed 8 bits | Next row-major B element |
| `busy` | Output | 1 bit | High in CLEAR, FEED, and DRAIN |
| `done` | Output | 1 bit | One-cycle DONE indication |
| `c_out[0:3][0:3]` | Output | Sixteen signed 32-bit elements | Live accumulator matrix |

Every sixteen accepted paired beats form A and B. Beat `n`, counted from zero, writes both matrices at `[n/4][n%4]`. Both matrices arrive row-major; B is not pre-transposed. Invalid or unaccepted beats do not advance matrix assembly. There is no public load or start command.

### 2.3 Banks, queue, and automatic scheduling

Each bank stores one complete A/B pair. A two-entry FIFO stores completed bank identifiers, not copies of matrix data. Completion enqueues a bank; accepted computation start removes the oldest descriptor and retains that bank as active until release.

The top-level scheduling equations are:

```text
compute_start = rst_n && matrix_ready && !busy && !done
controller.start = compute_start
compute_done = rst_n && done
```

The buffer's `matrix_ready` indicates a completed queue entry with no active computation. In reachable controller states, `!busy && !done` identifies IDLE. The same edge claims the bank and starts the controller. Selection remains stable throughout FEED and DRAIN. The active bank is released on the edge leaving DONE, not when done first rises.

Reset discards queued work, partial input progress, and active ownership. Matrix storage itself is not reset, but the controller, valid pipelines, and accumulators are reset. Invalid storage is never scheduled as a completed operation. Unlike the standalone buffer's raw readiness, the v2 public `in_ready` is low during reset.

`busy` is computation status, not input backpressure. Producers use `in_ready`; consumers capture results on `done`. No result FIFO or output-ready handshake is provided.

## 3. Verification Environment

The standalone SystemVerilog testbench directly instantiates the complete v2 DUT with `DATA_W=8` and `ACC_W=32`. It uses neither UVM nor DPI, and requires no Python model or external vector files.

| Component | Implementation and responsibility |
|---|---|
| Clock/reset | `always #5` creates a 10 ns clock; `reset_dut` asserts reset on a falling edge and checks asynchronous effects before the next rising edge |
| Streaming driver | `send_beat`, `send_matrix`, and `idle_cycles` drive paired bytes on falling edges and optionally insert valid gaps |
| Acceptance monitor | `cycle` records a beat only when both input valid and actual ready are exactly 1 at the rising edge |
| Bank reference | `ref_bank_state`, `ref_bank_beats`, `ref_write_sel`, `ref_active_bank`, and transaction-to-bank mapping track ownership independently |
| Transaction queue | `head`, `tail`, `active_id`, and `queued_at` preserve accepted-completion order and support bounded progress checks |
| Arithmetic reference | `reference_matmul` computes sixteen signed 64-bit expected results from accepted matrix elements |
| Scoreboard | `check_result` compares all sixteen outputs and also checks reset/clear zeros and result retention |
| Control timing | `age` predicts busy/done from the independently scheduled transaction, not from observed DUT progress |
| Diagnostics | Per-scenario error deltas, global error totals, detailed mismatches, coverage counters, bounded waits, and `$fatal(1, ...)` |

Expected readiness is checked at the rising edge before reference transitions and again 1 ns afterward, after DUT nonblocking updates settle. Numerical and busy/done checks also use the settled sample. This avoids treating old accumulator data as the current edge's completed result.

The reference model uses public accepted-input history and its own predicted compute schedule. Actual `in_ready` is used to determine whether an observed input transfer occurred; it is not substituted for expected readiness or used to choose a bank. Actual busy/done are checked rather than used to advance the schedule. No DUT state, counter, bank storage, FIFO memory, or hierarchical signal is read or forced.

Input retries, queued/active transaction ages, and drain waits are bounded by `WAIT_LIMIT=64`; a 200,000 ns watchdog bounds the overall run. Missing E11 completion is an immediate failure. Reset starts a new reference epoch, while aggregate result/error/coverage counters remain available across resets. Reference arrays support up to 64 complete matrices per epoch, sufficient for this directed suite.

## 4. Verification Test Plan and Results

The overall end-to-end result is **PASS, user-confirmed**. The table below maps current testbench groups to their verification objectives. Individual rows are not marked PASS solely by inference from the overall confirmation: the per-scenario transcript and remote source snapshot are unavailable for inspection.

| Test ID | Test Scenario | Verification Objective | Result |
|---|---|---|---|
| E2E | Complete v2.0 end-to-end simulation | Exercise the integrated streaming accelerator using the reported Playground testbench | **PASS — confirmed by the user** |
| R00 | Reference bank selector checks | Check EMPTY/LOADING selection, occupied-bank refusal, and choices after release, including synthetic state combinations | Implemented; reference model only; not individually confirmed |
| T01 | Reset and idle | Check asynchronous reset, reset-time ready masking, zero outputs, and absence of unsolicited computation | Implemented; not individually confirmed |
| T02 | Pattern 0: left identity | Verify `I × B = B` with asymmetric signed B and correct matrix indexing | Implemented; not individually confirmed |
| T03 | Pattern 1: right identity | Verify `A × I = A` and detect transposition/operand-index errors | Implemented; not individually confirmed |
| T04 | Pattern 2: zero A | Check zero results and absence of stale accumulation | Implemented; not individually confirmed |
| T05 | Pattern 3: positive operands | Check four-term accumulation across all sixteen processing elements | Implemented; not individually confirmed |
| T06 | Pattern 4: mixed signs | Check signed multiplication, accumulation, and asymmetric indexing | Implemented; not individually confirmed |
| T07 | Pattern 5: all -128 in A and B | Check minimum INT8 operands and sums beyond signed 16-bit range; expected element value 65536 | Implemented; not individually confirmed |
| T08 | Pattern 6: A=-128, B=127 | Check negative boundary products and sign extension; expected element value -65024 | Implemented; not individually confirmed |
| T09 | Pattern 7: A=B=127 | Check maximum positive INT8 operands; expected element value 64516 | Implemented; not individually confirmed |
| T10 | Pattern 8: mixed -128/127 | Stress signed boundaries and row/column selection | Implemented; not individually confirmed |
| T11 | Pattern 9: zero B | Check zero propagation and clearing after nonzero results | Implemented; not individually confirmed |
| T12 | Input pauses | Preserve row-major grouping through three-cycle gaps before beats 3, 9, and 15 | Implemented; not individually confirmed |
| T13 | Eight continuous matrix pairs | Check loading/computation overlap, ordered outputs, COMPUTING+LOADING readiness, bank release/reuse, and all sixteen results per operation | Implemented; not individually confirmed |
| T14 | Reset after seven accepted beats | Discard partial loading; reject stale completion and verify fresh pattern 25 | Implemented; not individually confirmed |
| T15 | Reset during FEED with overlapped loading | Abort at modeled E3, discard four beats of the following matrix, and verify fresh pattern 28 | Implemented; not individually confirmed |
| T16 | Reset during DRAIN | Abort at modeled E7, suppress stale done, and verify fresh paused pattern 30 | Implemented; not individually confirmed |

The current source defines 17 reported groups: 16 DUT-directed groups and reference-only R00. E2E is this report's overall-result row, not an additional `begin_test` invocation. The code requires 22 completed matrix results: ten arithmetic operations, one paused-input operation, eight continuous operations, and three reset-recovery operations. Aborted FEED/DRAIN operations are excluded. These are source-defined expectations, not recovered runtime counts.

Normal arithmetic groups retain state between operations, so accumulator clearing is tested without a global reset before each multiplication. T13 combines overlap, ordering, and reuse in one group; those objectives are not additional scenario counts. Conditional backpressure and stalled-beat checks are distinguished from exercised DUT scenarios in section 9.

## 5. Ready/Valid and Ping-Pong Buffer Verification

### 5.1 Reference state and prediction

| Reference state | Meaning | Input eligibility |
|---|---|---|
| `REF_EMPTY` | No live matrix ownership; accepted-beat count is zero | Eligible to begin a new pair |
| `REF_LOADING` | Holds 1–15 accepted beats of the current pair | Selected write bank remains eligible |
| `REF_FULL` | Holds sixteen beats and belongs to a queued transaction | Not writable |
| `REF_COMPUTING` | Holds the active complete pair | Not writable until release |

`write_bank_choice` examines only reference states and the reference write pointer. It keeps the selected bank when that bank is EMPTY or LOADING; otherwise it chooses the other bank only if that bank is EMPTY. It returns -1 when neither choice is legal. Expected top-level readiness is `rst_n && (selected_bank >= 0)`.

A LOADING bank remains writable alongside a COMPUTING bank because the partially loaded pair already owns its write bank. It does not need another empty bank for each successive beat. The model checks that the partial count agrees with that bank's progress and that the write pointer continues to select it.

The first accepted beat changes EMPTY to LOADING. The sixteenth changes LOADING to FULL and records its bank ID with the queued matrix. Independently predicted start changes the old FIFO head's bank to COMPUTING. Predicted release changes only the old active bank to EMPTY and clears its beat count. Reset restores both banks to EMPTY and the write pointer to bank 0.

### 5.2 Simultaneous events and ownership checks

Before any reference mutation, `cycle` snapshots the candidate write bank, predicted start bank, and predicted release bank. Consequently, newly available space after release cannot retroactively authorize an input transfer on the release edge. Accepted input into the other writable bank can proceed concurrently with a start or release. A matrix completed on the current edge is appended after the old queue head is considered for scheduling.

`check_bank_model` verifies that FULL-bank count equals queued-transaction count, COMPUTING ownership agrees with the active transaction, at most one bank is LOADING, and every queued transaction maps to a FULL bank. It checks expected readiness against the DUT both before and after the edge. Additional checks reject acceptance when no reference bank is writable and reject an input write targeting the same pre-edge bank as a compute start or release.

### 5.3 Release, reuse, and stalled input

After modeled release, the checker requires actual `in_ready=1`. A per-bank release marker records when that bank later accepts its first new beat; the `reused_bank_beats` counter counts those first accepted reuse beats, not every beat of a reused matrix.

`send_beat` retries the same payload until acceptance. `hold_pending`, `held_a`, and `held_b` independently check that a previously unaccepted beat still has valid asserted and unchanged A/B data at the next sampled edge, including the eventual accepting edge. Reset legally abandons the pending beat and clears this checker's history.

The COMPUTING+LOADING and release/reuse checks are intended to execute during T13. Full-bank refusal and held-beat checks are conditional checkers; their presence does not prove those conditions occurred. The reference-selector self-check supplies synthetic state combinations only to the pure helper and never forces the DUT into those states. Section 9 records the associated coverage limits.

## 6. Controller and Datapath Timing

The following timing is derived from the actual Moore state transitions, counter updates, skew delays, and PE forwarding. Exact cycles below are confirmed by RTL inspection; the detailed waveform or run log was not available for independent timing confirmation. E0 is the rising edge that accepts the shared buffer/controller start request. States and control values in the table are the settled post-edge values; sequential datapath actions consume pre-edge controls.

| Edge | Controller state after edge | Datapath and ownership event |
|---|---|---|
| E0 | CLEAR; busy=1 | Oldest complete pair is claimed; bank becomes active |
| E1 | FEED, k=0 | Accumulators clear using the preceding CLEAR control |
| E2 | FEED, k=1 | Slice k=0 enters the core/skew |
| E3 | FEED, k=2 | Slice k=1 enters |
| E4 | FEED, k=3 | Slice k=2 enters |
| E5 | DRAIN | Slice k=3 enters |
| E6–E10 | DRAIN | Remaining valid data propagates and accumulates |
| E11 | DONE; busy=0, done=1 | PE [3][3] commits the last product; all results settle |
| E12 | IDLE; busy=0, done=0 | Buffer samples compute_done and releases the active bank |
| E13, if queued | CLEAR for the next operation | Earliest possible next start |
| E14, if E13 starts | FEED for the next operation | Previous result is cleared |

A term k reaches PE `[i][j]` at E(2+k+i+j). The last term has k=3, i=3, and j=3, so the final accumulator update occurs at E11. The controller's six drain edges align with this update; the testbench observes done and results at E11+1 ns.

A sixteenth input beat accepted at edge L cannot start that newly completed pair on the same edge when the FIFO was previously empty. Start can be accepted at L+1; done then appears at L+12 and release occurs at L+13. E13 restart is a conditional scheduler capability, not a demonstrated continuously queued condition in this top-level suite.

`c_out` is a live accumulator matrix. Capture it during DONE after E11 settles, or synchronously at E12 while sampling the pre-edge asserted done. It remains stable until the next CLEAR or reset; the earliest next clear is E14. There is no output backpressure mechanism. The testbench checks post-completion retention until the modeled clear rather than assuming permanent result storage.

## 7. Reference Model and Scoreboard

For each completed accepted pair, the mathematical reference is:

\[
C[i][j] = \sum_{k=0}^{3} A[i][k] \times B[k][j],\qquad i,j\in\{0,1,2,3\}.
\]

The scoreboard reconstructs A and B from actual accepted public input bytes. Each signed 8-bit operand is explicitly sign-extended to 64 bits before multiplication. Products and sums use signed 64-bit intermediates. This avoids reliance on the DUT's product width or implicit expression sizing. The reference is computed only after all sixteen accepted beats have populated the matrices.

Expected results are stored by transaction ID. FIFO-style head/tail indices select the expected active transaction independently of the DUT's done sequence. The cycle model predicts starts from previously queued completions and predicts E11 completion without waiting for the DUT to choose a completion time.

For every predicted completion, all sixteen `c_out` elements are sign-extended from 32 to 64 bits and compared with `!==`. Diagnostics report scenario, transaction ID, row, column, expected signed value, actual signed value, hexadecimal value, and simulation time. Additional full-matrix comparisons check asynchronous reset, accumulator clear, and result stability after completion.

| Failure class | Detection mechanism |
|---|---|
| Incorrect arithmetic or signed extension | Independent full-precision dot-product comparison, including INT8 boundaries |
| Row/column or k indexing error | Asymmetric identity, signed, and deterministic matrix patterns |
| Result reordering | Distinct transactions compared against the reference queue head in expected schedule order |
| Missing or late completion | Exact E11 done check plus bounded input, queue, active-operation, and drain waits |
| Early, stretched, or duplicate done | Every driven cycle's done value compared with independently predicted age |
| Stale accumulator contents | Zero tests, E1 clear check, and consecutive non-reset operations |
| Stale output after reset | Reset clears reference epoch; following idle cycles prohibit abandoned completions |

Numerical comparisons alone cannot distinguish two transactions with identical products. Distinct continuous-stream patterns and independent timing checks reduce that ambiguity but do not constitute exhaustive ordering proof. The source-defined final expected count is 22 results; the actual logged count is not available for inspection.

## 8. Simulation Setup

### 8.1 Reported platform and available run details

The user-confirmed passing simulation was executed on **EDA Playground**:

[Open the v2.0 end-to-end simulation](https://www.edaplayground.com/x/hPw2).

| Run detail | Recorded information |
|---|---|
| Overall simulation result | **PASS — user-confirmed** |
| Platform | EDA Playground |
| DUT | `accelerator_4x4_top_v2` |
| Top-level testbench | `tb_accelerator_4x4_top_v2` in `tb_accelerator_4x4_top_v2.sv` |
| Simulator name and version | Not independently confirmed; run log/settings unavailable |
| Actual compilation and execution options | Not independently confirmed |
| Numerical PASS summary | Not available for inspection |
| Local simulation during this documentation update | Not performed |

The supplied page could not be retrieved by the available web/browser tools. No local runtime log, waveform, or saved run configuration was found. These evidence limits apply to detailed attribution and metrics; they do not retract the user's confirmation that the end-to-end simulation passed.

### 8.2 Required source files

| Current file | Module / purpose |
|---|---|
| [rtl/systolic_pe.sv](../rtl/systolic_pe.sv) | `systolic_pe`: signed MAC and forwarding |
| [rtl/systolic_array_4x4.sv](../rtl/systolic_array_4x4.sv) | `systolic_array_4x4`: 4×4 PE interconnect |
| [rtl/input_skew.sv](../rtl/input_skew.sv) | `input_skew`: matched operand/valid delays |
| [rtl/accelerator_4x4_core.sv](../rtl/accelerator_4x4_core.sv) | `accelerator_4x4_core`: datapath integration |
| [rtl/accelerator_4x4_controller.sv](../rtl/accelerator_4x4_controller.sv) | `accelerator_4x4_controller`: Moore control sequence |
| [rtl/matrix_input_pingpong_buffer.sv](../rtl/matrix_input_pingpong_buffer.sv) | `matrix_input_pingpong_buffer`: banks and completion FIFO |
| [rtl/accelerator_4x4_top_v2.sv](../rtl/accelerator_4x4_top_v2.sv) | `accelerator_4x4_top_v2`: streaming wrapper |
| [tb/tb_accelerator_4x4_top_v2.sv](../tb/tb_accelerator_4x4_top_v2.sv) | `tb_accelerator_4x4_top_v2`: simulation root |

Only the seven listed RTL modules and the one top-level testbench are required. The v1 operand-copy buffer and alternate registered-output controller are not instantiated by this v2 top.

### 8.3 Reproduction guidance

In EDA Playground, select Verilog/SystemVerilog and an available compatible simulator. Place the unchanged top-level testbench in Testbench and the seven complete RTL module definitions in Design, separated by newlines. Include every module exactly once. Alternatively, upload RTL files as Design tabs and include them once from the main Design file. No UVM library or external vectors are required. If the chosen tool needs an explicit simulation root, select `tb_accelerator_4x4_top_v2`. These are reproduction instructions, not a recovered record of the original run's options. See the [official quick start](https://eda-playground.readthedocs.io/en/latest/intro.html) and [file/simulator settings](https://eda-playground.readthedocs.io/en/latest/settings.html).

Retain the selected simulator/version, complete build/run output, source snapshot, options, and termination status when exporting the passing run. The next documentation update can then add per-scenario results and metrics without inferring them from source code. No new local or Playground simulation was executed for this report revision.

## 9. Verification Coverage and Limitations

### 9.1 Numerical evidence

The overall result is user-confirmed PASS. Detailed values below require the actual simulation log and are **not available**, rather than zero. No numerical summary has been fabricated.

| Metric | Current testbench counter / interpretation | Confirmed logged value |
|---|---|---|
| Test scenarios executed | `tests`; includes reference-only R00 | Unavailable |
| Matrix operations completed | `results`; counted at predicted E11 after actual done is confirmed; arithmetic errors tracked separately | Unavailable |
| Output element comparisons | `element_checks`; reset, clear, completion, and retention comparisons | Unavailable |
| Accepted input beats | `accepted_beats`; includes accepted data later discarded by reset | Unavailable |
| Input/computation overlap | `overlap_beats`; accepted beats while the reference predicts pre-edge busy | Unavailable |
| COMPUTING+LOADING readiness | `loading_compute_checks`; pre/post-edge checked snapshots | Unavailable |
| Occupied-bank backpressure | `blocked_bank_checks`; snapshots with both banks FULL/COMPUTING | Unavailable |
| Bank release | `release_checks`; predicted release followed by actual readiness check | Unavailable |
| Bank reuse | `reused_bank_beats`; first accepted input beat following a bank's release | Unavailable |
| Stalled attempts | `stalled_beats`; valid sampled while ready is low | Unavailable |
| Held-beat retry | `held_beat_checks`; samples following an unaccepted beat | Unavailable |
| Error count | `errors`; accumulated failures | Unavailable |

The source-defined targets of 17 reported groups and 22 results are not substituted for measured counts. `element_checks` includes more than completion comparisons, and coverage counters can count both pre-edge and post-edge observations. Counters are cumulative across scenarios and resets; a nonzero total alone does not identify the contributing scenario or bank.

### 9.2 Directed checks versus coverage closure

The testbench implements directed stimulus and procedural checks. It does not contain SystemVerilog covergroups, cross-coverage bins, an exhaustive input sweep, or a formal proof harness. No measured code-coverage database or coverage percentage is available. An overall PASS does not establish that every conditional checker was exercised.

R00 calls only the pure reference-selector function, including synthetic two-COMPUTING-bank combinations impossible under single-compute ownership. It is not DUT stimulus and cannot establish DUT backpressure coverage.

### 9.3 Unexercised-case reporting remains applicable

The current source conditionally prints `NOT EXERCISED on DUT` for these cases:

| Source condition | Reported limitation | Evidence distinction |
|---|---|---|
| `blocked_bank_checks == 0` | Full-bank backpressure; automatic compute releases banks before the next sixteen-beat pair completes | Checker/message implemented; actual counter and emitted message unavailable |
| `held_beat_checks == 0` | Stalled-beat retry; hold-until-handshake checker exists but no input stall occurred | Checker/message implemented; actual counter and emitted message unavailable |

The user-confirmed overall PASS does not override these limitations. Any such messages in the actual log must remain part of the final coverage record. This report does not invent their occurrence or numerical values.

RTL timing explains the expected reachability limit: a pair needs at least sixteen accepted input clocks; after completion it starts at the next edge and its bank is released thirteen edges after its final beat. The next pair therefore cannot complete before that release. Starting from reset, correct normal top-level operation cannot accumulate two FULL/COMPUTING banks, and input pauses only increase the available time. Thus full-bank backpressure, a backpressure-induced held-beat retry, a continuously queued E13 restart, and simultaneous FIFO completion/start are not reached through the current normal stream. No DUT internals are forced to manufacture those cases.

Loading a partial second pair while the first computes, bank reuse, and input acceptance into the other bank on a release edge remain within the implemented continuous-stream scenario. Standalone buffer tests provide separate controllable stimulus for FIFO/backpressure cases, but this end-to-end PASS is not a substitute for their own execution evidence.

### 9.4 Remaining work and scope limits

- Archive the user-confirmed passing run's full log and exact source snapshot, then confirm simulator details, per-scenario outcomes, counters, and any unexercised-case messages.
- Match the remote run sources to the current working tree before claiming that every current checker was included in that run.
- Record standalone buffer evidence for full-bank stalls and simultaneous FIFO events that cannot arise in this fixed top-level schedule.
- Extend measured functional coverage and per-scenario/per-bank accounting in future verification work; no such extension is part of this documentation revision.
- Consider longer streams, additional reset offsets and CLEAR/DONE boundaries, and deliberate fault/X/Z tests. Current directed resets cover partial loading, E3 FEED, and E7 DRAIN.
- Qualify four-state checking for the selected simulator. Case-aware comparisons in source do not by themselves establish X/Z coverage in two-state execution.

The suite targets signed INT8 operands with 32-bit accumulation. It does not establish parameter-sweep, synthesis, timing-closure, power, hardware, or exhaustive formal verification. The RTL and protocol reference share an interpretation of the interface, so independent specification review remains valuable even with a passing end-to-end run.

## 10. Verification Conclusion

The v2.0 end-to-end simulation has **PASSED on EDA Playground, as confirmed by the user**. The reported result is available through the supplied [EDA Playground simulation link](https://www.edaplayground.com/x/hPw2).

The current implementation and testbench define checks for streaming matrix assembly, independent ready/bank-state prediction, automatic scheduling, signed 4×4 multiplication, ordered result comparison, loading/computation overlap, bank reuse, controller timing, and reset recovery. The overall user-confirmed PASS is recorded for this end-to-end verification activity. Individual scenario results and exact numerical coverage remain unconfirmed until the run transcript and source snapshot can be inspected.

Full-bank backpressure and stalled-beat retry remain distinct coverage limitations; reference-selector self-checks do not establish that those DUT conditions occurred. The result is a directed end-to-end simulation PASS, not a claim of exhaustive verification or formal proof.

The verification-report revision did not change RTL or testbench behavior. Release packaging is documented separately in the release notes.
