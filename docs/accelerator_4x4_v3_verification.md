# v3.0 verification report

## Confirmed EDA Playground result

The project author confirmed successful v3.0 verification and supplied the
following results for this release. This records that manual remote run;
no local HDL simulation is claimed.

- Simulator: **Icarus Verilog** (exact version not supplied).
- Language/mode: **SystemVerilog, `-g2012`**.
- EDA Playground: https://www.edaplayground.com/x/D8a8
- Testbench: `tb/tb_accelerator_4x4_top_v3_eda.sv`.
- DUT: `accelerator_4x4_top_v3`, signed INT8 inputs and INT32 accumulation.

## Supplied PASS and coverage counters

```text
COVERAGE load_compute=1417
output_compute=80
input_stalls=53
pending_stalls=112
replacements=3
push_pop=1
capture_empty_not_ready=37
consume_only=155

COVERAGE triple_overlap=4
done_while_output_blocked=5
ownership_checks=4290

PASS v3:
results=158
copies=161
completions=164
cycles=3765
golden_vectors=73
```

These are the counters supplied by the author, with their line grouping
preserved. The bench also requires buffer reuse and reset-state coverage;
the supplied excerpt does not include numeric `reused` or `resets` values.
PASS is printed only after all mandatory coverage checks succeed.
The cumulative completion, capture, and consumption counts can differ because
directed resets intentionally cancel outstanding transactions.

## Reference model and test inputs

The self-contained EDA bench uses nine directed matrix pairs and 64 reproducible
pseudo-random pairs. Directed inputs cover sequential times identity, mixed
signed values, zero matrices, identity times signed values, boundary patterns,
and all four combinations of uniform -128/127 matrices. These nine pairs
match the original generated directed cases.

A fixed-seed xorshift PRNG (`32'h00004a43`) generates the remaining inputs,
independently of the existing handshake-stimulus PRNG. Signed 32-bit integer
multiplication and accumulation compute each reference element as
`sum(A[row][k] * B[k][column])` for k=0..3. The INT8 four-product sum fits
within [-65024, 65536]. Expected values do not depend on DUT signals or timing.
The `va`, `vb`, and `vc` arrays feed the existing transaction scoreboard.

The repository file-based bench remains available, using
`python/generate_vectors_v3.py` and `vectors/v3_vectors.txt`. It has the same
protocol checks but a different seeded random input sequence. Its file reads
use a scalar before assigning array elements. Neither Python nor file I/O is
needed at EDA simulation runtime.

## Major verified scenarios

| Area | Stimulus and checks |
|---|---|
| Arithmetic | All 16 signed output elements compared with the independent reference on each output handshake |
| Input handshake | Only accepted paired beats advance loading; pauses and hold-until-accepted behavior checked |
| Ping-pong ownership | Independent bank states, queue/partial counts, and protected FULL/COMPUTING A/B contents checked before and after edges |
| Ordering and exactly-once output | Independently queued transaction IDs; duplicate, missing, or reordered results fail |
| Output handshake and stability | Whole-matrix ready/valid transfer; registered payload retained through stalls and concurrent clear/compute |
| Backpressure | Both input banks full; unchanged input retried for 40 cycles before release |
| Overlap | Input load during compute, compute with retained output, and simultaneous load/compute/output transfer |
| RESULT_PENDING | Completed accumulators retained; no start, clear, or feed until output capacity is available |
| Consume/replacement | Old result consumed and pending result captured on the same edge with valid retained |
| Queue and reuse | Simultaneous bank-ID push/pop, released-bank reuse, consume-only, and capture while ready is low |
| Timing, busy, done | Independent compute ages check clear/feed/drain/capture; one completion pulse independent of output readiness; busy includes pending |
| Random stalls | Reproducible output-ready variations and input pauses; held input payload checked |
| Reset | IDLE, CLEAR, FEED, DRAIN, RESULT_PENDING; partial input, unread output, full banks and pending results; asynchronous cancellation and fresh recovery |
| Late or lost work | Drain/watchdog limits and idle periods catch missing, duplicate, or stale transactions |

The EDA bench retains the file-based bench's protocol tasks and all scenarios
after initialization. Missing mandatory events or reset-state coverage cause
`$fatal`; none of these checks were removed for Playground portability.

## Reproduction and release scope

1. Open the EDA Playground project above.
2. Select SystemVerilog, Icarus Verilog, and `-g2012`.
3. Replace the Testbench pane with `tb/tb_accelerator_4x4_top_v3_eda.sv`.
4. Use the unchanged repository RTL in the design sources; select
   `tb_accelerator_4x4_top_v3` if a top module is requested.
5. Run and check the coverage output and final `PASS v3` line.

The EDA file is approximately 21 KB, below the 100,000-character limit, and
requires no external vector files. Do not compile both v3 bench variants in
one invocation because they declare the same module. The regression runner
uses separate invocations and selects the shared module name for the EDA file.

Release preparation includes static source review, Python golden-model and
vector checks, and staged whitespace checks. No local HDL simulator is
installed, and none was installed for release preparation. The supplied PASS
covers the manual v3 EDA run, not a fresh execution of all legacy benches,
alternate parameter widths, synthesis, formal proof, timing closure, or hardware.
The existing v3 specification, including its v2 streaming-interface mapping,
is retained in `docs/accelerator_4x4_v3_specification.md`.
