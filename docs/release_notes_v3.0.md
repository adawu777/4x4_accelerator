# 4×4 INT8 Matrix Accelerator v3.0

Version 3.0 supports overlapping input loading, computation, and output
transfer while preserving ordered signed INT8 matrix multiplication with
INT32 results.

- Two ping-pong input banks accept paired A/B streaming elements and protect
  occupied banks from overwrite.
- Input loading, computation, and output transfer can overlap, including
  same-cycle three-way overlap.
- One registered 4×4 output buffer provides a whole-matrix ready/valid
  handshake and stable payload under downstream backpressure.
- RESULT_PENDING retains a completed result in the accumulators until the
  output slot can accept it, preventing premature clear or overwrite.
- Simultaneous output consumption and replacement retains valid without a
  bubble, while transaction ordering and buffer ownership are preserved.
- `done` pulses at computation completion independently of output readiness;
  `busy` includes RESULT_PENDING. The legacy `c_out` remains live accumulator
  data; downstream transfers use `out_matrix`.
- Reset cancels partial, queued, active, pending, and unread transactions.
- A compact self-contained EDA testbench uses nine directed and 64 fixed-seed
  random matrix pairs with an independent reference multiplication. The
  file-based repository testbench remains available with Icarus-safe reads.

## Verification

**EDA Playground PASS**, confirmed by the project author using **Icarus
Verilog with SystemVerilog `-g2012`** at
https://www.edaplayground.com/x/D8a8.

```text
PASS v3: results=158 copies=161 completions=164 cycles=3765 golden_vectors=73
```

Reported coverage includes 1417 load/compute overlaps, 80 output/compute
overlaps, 4 triple overlaps, 53 input stalls, 112 pending stalls, 3 output
replacements, 1 simultaneous queue push/pop, 37 captures while not ready,
155 consume-only events, 5 completions while output was blocked, and 4290
ownership checks.

See [the verification report](accelerator_4x4_v3_verification.md) for the
supplied counters and verified scenarios, and
[the specification](accelerator_4x4_v3_specification.md) for the architecture
and exact interface/timing contract. No local HDL simulation is claimed;
this result does not imply a fresh run of the legacy regression suite.
Existing v1.0 and v2.0 releases are preserved.
