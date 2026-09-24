# v3.0 change notes

**Status: RTL implemented; EDA Playground PASS reported by the project author,
not independently verified. No local RTL compilation/simulation performed.
Publication and tagged source snapshots are recorded on the repository’s
[GitHub Releases page](https://github.com/adawu777/4x4_accelerator/releases).**

The new `accelerator_4x4_top_v3` adds one registered 4×4 output matrix and
ready/valid backpressure while preserving all released v2 sources. It reuses
the existing two-bank input buffer, bank-ID ordering queue, and systolic core.
No DMA, second output buffer, or result FIFO is added.

## Interface and timing

* Preserve `clk`, `rst_n`, `in_valid`, `in_ready`, `a_data`, `b_data`, `busy`,
  `done`, and signed `c_out[0:3][0:3]`, with DATA_W=8 and ACC_W=32 defaults.
* Preserve paired 16-beat row-major input loading and automatic scheduling of
  the oldest complete pair. No external load/start ports are introduced.
* Add signed `out_matrix[0:3][0:3]`, `out_valid`, and `out_ready`. The whole
  registered matrix transfers at a rising edge with valid and ready high.
* Preserve live-accumulator `c_out` and the E11 completion pulse on `done`.
  Done remains independent of downstream readiness and occurs once per
  completed computation, even when its result cannot yet enter the output slot.
* Extend `busy` through RESULT_PENDING. Consequently busy and done can both
  be high, and busy low does not imply the output slot is empty.
* Release the active input bank at E11, one edge earlier than v2, allowing
  future inputs to occupy both banks while an accumulator result is pending.
* Capture completed accumulators into the output register no earlier than
  E12. An unread output does not block the next computation; if that computation
  completes first, its result waits in the accumulators without being cleared.
* Consume an old output and replace it with a pending result on the same edge
  without deasserting valid. Reset cancels all partial/queued/active/pending/output
  transactions and clears both output interfaces.

## Verification and limitations

Python golden-model sanity checks and 73-case vector generation/readback pass.
No compatible local simulator is available; all eleven legacy benches and
the v3 bench are NOT RUN locally. The v3 bench includes arithmetic/order checks,
backpressure, simultaneous transfers, three-way overlap, completion pulses,
and reset recovery. Its coverage is implemented, not demonstrated locally.
The author reports a successful v3 EDA Playground run, but its URL, simulator,
source snapshot, executed cases, and log have not been provided. The remote
report does not establish that every current repository bench passed.

Run `python3 python/run_regression.py` with a compatible simulator, review
all compile warnings and runtime logs, and resolve any failures.
See the [specification](accelerator_4x4_v3_specification.md) and
[verification report](accelerator_4x4_v3_verification.md) for details.
