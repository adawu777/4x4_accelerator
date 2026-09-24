# v3.0 implementation and verification report

Date: 2026-09-24. **RTL implemented; EDA Playground PASS reported by the
project author. No local RTL compilation or simulation performed.**
No compatible local simulator was found. Python passes below are not RTL passes.
The historical user-confirmed v2.0 EDA Playground result is not a fresh
regression result and does not validate v3.0.

## Author-reported v3.0 EDA Playground result

The project author's subsequently supplied README text states that v3.0
passed simulation in EDA Playground. This is an author-reported result,
not an independently observed execution by Codex.

| Evidence item | Status |
|---|---|
| Reported result | PASS, according to the author's supplied README text |
| Environment | EDA Playground, reported by the author |
| Simulation URL | Not provided |
| Simulator/version and configuration | Not provided |
| Executed testbench/test cases and coverage | Not provided |
| Source snapshot matching this repository | Not provided; match not established |
| Runtime log and exact run date | Not provided |

The coverage table below describes the repository testbench, not demonstrated
coverage of the remote run. In particular, the remote report does not establish
that all twelve repository benches or the latest ownership assertions ran.
Local NOT RUN results below remain unchanged. Publication status and tagged
source snapshots are recorded on the repository’s GitHub Releases page.

## Files and preservation

Created:

| File | Purpose |
|---|---|
| `docs/accelerator_4x4_v3_specification.md` | v2 source inspection, reconciled v3 contract, decisions, timing, verification requirements |
| `docs/accelerator_4x4_v3_verification.md` | This implementation/verification record |
| `docs/release_notes_v3.0.md` | Interface/change notes; records reported remote PASS and local verification limitations |
| `rtl/accelerator_4x4_controller_v3.sv` | Compute FSM with protected RESULT_PENDING state |
| `rtl/accelerator_4x4_top_v3.sv` | Existing input buffer/core integration plus one registered output slot |
| `tb/tb_accelerator_4x4_top_v3.sv` | Cycle model, transaction scoreboard, golden-vector comparisons, directed/random stimulus and mandatory coverage |
| `python/generate_vectors_v3.py` | 73 deterministic vectors using the unchanged Python golden model |
| `python/run_regression.py` | Run all eleven existing benches and the new v3 bench; keep compile/runtime logs |
| `vectors/v3_vectors.txt` | Count header followed by A/B/C rows: 16 + 16 + 16 decimal integers per case |

Modified: `README.md` uses the author's v3 overview, with actual interface,
documentation links, reported/local verification distinctions, and release status.
All pre-existing RTL, testbench and Python sources are unchanged. Regenerating
the existing five vectors produced no content diff. The pre-existing untracked
`docs/accelerator_4x4_v2_pingpong_input_buffer_design_spec.pdf` was left untouched.
No commit, tag, or release publication was performed during the implementation
and local-verification phase described here. Publication is handled separately.

## Architecture and interface changes

The new top reuses `matrix_input_pingpong_buffer` and
`accelerator_4x4_core` without modifying them. The inspected buffer already
provides ordered paired input loading and bank ownership. Its two-entry queue
stores bank IDs, not results. The new design adds exactly one 4×4 ACC_W-bit
registered output matrix and its valid bit. Pending results occupy existing
PE accumulators; there is no DMA, second output matrix, or added result FIFO.

Input ports and paired row-major 16-beat transactions are unchanged.
`out_valid` and `out_ready` transfer the whole registered `out_matrix`.
`c_out` remains the live accumulator output, preserving its v2 meaning.
`done` pulses at E11 when computation completes, regardless of output
occupancy/readiness. It does not pulse on output capture or acknowledgement.
`busy` includes RESULT_PENDING and can be low with an unread output still
valid. Unlike v2, busy is high during the done pulse. `acc_result_valid`
explicitly identifies the pending accumulator result.

The actual v2 streaming interface replaces the specification's illustrative
full-matrix load/start interface: retain in_valid/in_ready and automatic
oldest-transaction scheduling, without duplicate load_ready/start_ready ports.
The complete user-supplied specification is now in the specification document;
Appendix A records the v2 source inspection and exact compatibility mapping.
It supersedes the earlier draft's registered c_out and capture-time done.

FSM: IDLE → CLEAR → four FEED edges → six DRAIN edges → RESULT_PENDING
→ IDLE after result capture. Input banks move EMPTY → LOADING → FULL →
COMPUTING → EMPTY. The oldest completed bank starts; release occurs on the
sixth drain edge E11. It can then be reused while the result waits in the
accumulators. Copy starts no earlier than E12 to avoid sampling pre-final-MAC
values on E11. Output occupancy does not prevent starting the next computation
after a copy, but a blocked pending result prevents any further start/clear.

If an old output is consumed on the same edge as a pending result is copied,
the consumer receives the old matrix and valid remains asserted for the new
matrix. Reset asynchronously cancels all transactions, clears output data and
valid, and resets the shared buffer/controller/core state.

## Testbench coverage design (not executed locally)

The model predicts scheduling from accepted transactions, its own bank states,
and fixed compute age; it does not advance from DUT busy/done or FSM state.
Every cycle checks public ready/busy/valid, output stability against a payload
snapshot, control timing, and done/completion correspondence. Numerical output
comparisons occur only at successful out_valid/out_ready handshakes. Expected
values come from `golden_model.matmul_4x4`. Live c_out is separately checked
for clear timing and completed/pending result correctness. Internal control
reads are assertion targets only, not prediction inputs. Watchdogs bound waits.

| Requirement | Implemented stimulus/check |
|---|---|
| Signed arithmetic/indexing | Five original cases, four all-extreme products, 64 seeded random matrices; compare all 16 results |
| Exactly-once FIFO order | Accepted complete input IDs queued independently; output transfers must match the oldest ID |
| Loading/compute overlap and reuse | Continuous stream through all vectors; cycle counters require overlap and released-bank reuse |
| Bank ownership and no overwrite | Compare both DUT bank states, queue count and partial count to the independent model each pre/post edge; compare all A/B elements in FULL/COMPUTING banks to their accepted transaction vectors |
| Input pauses | Three-cycle gaps within matrices; no partial-count advancement |
| True input backpressure | Hold output 0, result 1 pending, both banks FULL; retry the same beat for 40 cycles, then unblock |
| Simultaneous input FIFO push/pop | Hold one FULL bank and another with 15 beats; consume/replace, then complete the partial on the next start edge |
| Three-way overlap | Retain A while loading B; during a B FEED edge, transfer A and accept C beat 3; require a same-edge triple-overlap counter |
| Output stable during new clear/compute | Compare out_matrix against its last payload snapshot on every pre/post edge, including invalid retention; c_out clears independently |
| Empty output capture without ready | Hold ready low from before first result; require valid to appear anyway |
| RESULT_PENDING protection | Compare all accumulators to golden C every pending cycle; require clear/feed/start all low |
| Timing/final MAC | Independent ages check E1 clear, E2–E5 feeds, E11 release/full accumulators, E12 earliest copy |
| Completion pulse compatibility | done equals E11 completion event every cycle; ordered completed-input IDs and pulse counts checked independently of copies/transfers, including done while output is blocked |
| Consume and replace | Pending/full setup followed by ready high; valid must stay high; old and replacement payloads numerically compared on their respective handshakes |
| Consume-only | Always-ready stream and drain; require counter nonzero |
| Random backpressure | Seeded bit-stream controls ready with additional input pauses; hold input through stalls |
| Reset in every FSM state | Directed reset setups for IDLE/CLEAR/FEED/DRAIN/RESULT_PENDING with required state-reset counters |
| Reset all outstanding storage | Partial input; unread output; pending + unread + both FULL; pending + unread + FULL + partial |
| Reset supersedes would-be output transfer/replacement | Present ready/valid, assert reset off-edge before the transfer edge, check asynchronous cancellation |
| Recovery/no stale work | Twenty idle cycles after each reset, then fresh golden transaction and full drain |

Missing mandatory functional events cause `$fatal`; coverage is not considered
achieved until an actual simulation reports its counters and PASS. This bench
and the new RTL still need independently recorded compilation and execution
against the current source snapshot.

## Actual local execution

Executed from the repository root:

```sh
python3 python/run_regression.py --build-dir /tmp/accelerator-v3-regression
```

Observed exit status: **2**, intentionally indicating simulator unavailable.
Actual console output:

```text
Logs and build products: /private/tmp/accelerator-v3-regression
PASS Python golden_model
PASS Python generate_vectors
PASS Python generate_vectors_v3
NOT RUN: no requested compatible simulator found; RTL remains unverified.
```

Python checks executed: the two original hand-calculated golden-model sanity
cases; regeneration/readback of five original vectors; generation/readback of
73 v3 vectors. All four Python source files also passed `ast.parse` syntax
checks. `git diff --check` passed. These checks do not compile SystemVerilog.

Discovery found no `iverilog`, `verilator`, `vcs`, `vsim`, or `xrun` on PATH;
neither Icarus nor Verilator was in the checked Homebrew/local binary locations.
No simulator version or simulation log exists for this run. **All eleven
legacy testbenches and the new v3 testbench are NOT RUN locally.**

Reproduce once a simulator is installed:

```sh
python3 python/run_regression.py --simulator verilator --build-dir /tmp/accelerator-v3-verilator
# Or, with Icarus and vvp:
python3 python/run_regression.py --simulator iverilog --build-dir /tmp/accelerator-v3-iverilog
```

The runner discovers every `tb/tb_*.sv`, explicitly selects each top, and
compiles it with all RTL files. Verilator uses `--binary --timing -Wno-fatal`;
Icarus uses `-g2012` and `vvp`. Each test gets a separate compile/runtime log;
warnings are retained for review. Compile/runtime errors and timeouts fail
the run while allowing other benches to run. Exit 0 requires every bench
to exit successfully with PASS output and no FAIL output. Tool-specific
SystemVerilog compatibility may require follow-up once compilation is possible.

## Remaining limitations

The final source audit rechecked the v2 top, input buffer, controller, core,
array and PE interfaces against the v3 integration. No further RTL changes
were identified as necessary. The v3 bench was strengthened with direct
protected-bank state/data checks; these remain unexecuted locally. Re-running the
regression produced the same Python passes and simulator-unavailable exit 2.
All existing tracked RTL/testbench/Python files remain unchanged.

The full user-supplied specification has been incorporated and its input
interface assumptions reconciled with the actual streaming v2 top. No default
or alternate-width RTL simulation, lint, synthesis, formal
proof, timing closure, or hardware test has been performed locally. Remote
PASS is author-reported; exact sources, logs, and coverage remain unconfirmed.
Release criteria are not established by this report alone.
