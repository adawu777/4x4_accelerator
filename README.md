# 4×4 INT8 Matrix Accelerator

A SystemVerilog-based 4×4 INT8 matrix multiplication accelerator featuring a systolic array architecture, ping-pong input buffering, and ready/valid output flow control.

**Current implementation: v3.0**

## 1. Overview

The accelerator computes:

C = A × B

where A and B are 4×4 signed INT8 matrices and C is a 4×4 signed INT32 result matrix.

The design uses a 4×4 systolic array with 16 processing elements (PEs).

Version 3.0 extends the existing v2.0 architecture by supporting overlapping input loading, matrix computation, and output transfer.

## 2. Key Features

* 4×4 systolic array architecture.
* Signed INT8 multiplication with INT32 accumulation.
* Two ping-pong input matrix buffers.
* Single registered 4×4 output result buffer.
* Ready/valid output handshake.
* Output backpressure support.
* Overlapping input loading, computation, and output transfer.
* Accumulator result retention when the output buffer is occupied.
* Simultaneous output consumption and result-buffer replacement.
* Transaction ordering and buffer ownership management.
* Active-low reset.

## 3. Architecture

```text
   Paired A/B Streaming Input
               |
       +-------v-------+
       | Input Buffer 0|
       | Input Buffer 1|
       +-------+-------+
               |
       +-------v-------+
       | Input Buffer  |
       |  Controller   |
       +-------+-------+
               |
       +-------v-------+
       | 4x4 Systolic  |
       |     Array     |
       +-------+-------+
               |
       +-------v-------+
       | ACC Registers |
       +-------+-------+
               |
       +-------v-------+
       | Output Buffer |
       +-------+-------+
               |
       +-------v-------+
       | Ready / Valid |
       |   Interface   |
       +-------+-------+
               |
        Downstream Module
```

## 4. Computation and Output Overlap

Version 3.0 supports three concurrent operations:

1. Transaction A is transferred to the downstream consumer.
2. Transaction B is computed by the systolic array.
3. Transaction C is loaded into an available input buffer.

When the output buffer is occupied, the next matrix computation may proceed using the accumulator registers.

If computation completes before the previous output transaction is consumed, the new result remains in the accumulators until the output buffer becomes available.

The controller protects unconsumed results from overwrite.

## 5. Output Interface

The registered output interface uses:

```systemverilog
out_valid
out_ready
out_matrix[0:3][0:3]
```

One successful handshake transfers the complete 4×4 result matrix.

A transfer occurs when:

```systemverilog
out_valid && out_ready
```

is sampled HIGH at the rising clock edge.

During backpressure, the output payload and `out_valid` remain stable until the transaction is accepted or reset is asserted.

## 6. Input Buffer Management

Two input buffer banks operate in ping-pong mode.

Each bank stores one complete input matrix pair. The implemented top is
`accelerator_4x4_top_v3`, retaining the v2.0 streaming interface: each rising
edge with `in_valid && in_ready` accepts paired signed `a_data` and `b_data`
elements. Sixteen accepted beats form A and B in row-major order. Input pauses
do not advance the element count; producers hold unaccepted beats stable.
Complete pairs are scheduled automatically in arrival order.

A bank is EMPTY, LOADING, FULL, or COMPUTING (the specification’s ACTIVE state).

The input controller prevents overwriting occupied banks and preserves transaction ordering.

Input loading may overlap with computation when an available bank exists.

## 7. Compute Controller

The v3.0 compute controller implements the following logical states:

```text
IDLE
  |
  v
CLEAR
  |
  v
FEED
  |
  v
DRAIN
  |
  v
RESULT_PENDING
  |
  v
IDLE
```

RESULT_PENDING retains a completed result in the accumulators until the output buffer can accept it.

A new computation cannot clear the accumulators while a previous result remains pending.

The existing `c_out` remains the live accumulator matrix. `done` pulses when
computation completes, independently of output readiness. `busy` includes
RESULT_PENDING and can be LOW while an unread output remains valid. Use
`out_matrix` with `out_valid`/`out_ready` for downstream transfers.

## 8. Verification

**v3.0 PASS on EDA Playground**, confirmed by the project author using
**Icarus Verilog with SystemVerilog `-g2012`**:
[run the project](https://www.edaplayground.com/x/D8a8).

```text
PASS v3: results=158 copies=161 completions=164 cycles=3765 golden_vectors=73
```

The run covers signed arithmetic, ping-pong ownership, ready/valid handshakes,
output backpressure and stability, load/compute/output overlap (including
triple overlap), RESULT_PENDING protection, simultaneous consume/replacement,
transaction ordering, completion timing, and reset recovery.

Copy `tb/tb_accelerator_4x4_top_v3_eda.sv` into the Playground Testbench pane.
It is self-contained (about 21 KB), with nine directed matrix pairs and 64
fixed-seed pseudo-random pairs. An independent signed-integer reference
multiplication calculates expected results. No vector-file upload is needed.
Use only one v3 testbench at a time: both declare `tb_accelerator_4x4_top_v3`.

The file-based `tb/tb_accelerator_4x4_top_v3.sv` remains available for repository
regression, with scalar file reads compatible with Icarus and a configurable
`V3_VECTOR_FILE` defaulting to `"vectors/v3_vectors.txt"`. Its Python-generated
random inputs differ from the EDA bench's PRNG; both retain the same protocol
scenarios and checks.

No local HDL simulator is installed; no local HDL simulation is claimed.
The remote PASS does not imply a fresh run of the legacy benches. With an
existing compatible simulator, the repository regression can be run using:

```sh
python3 python/run_regression.py --simulator iverilog
```

See the [verification report](docs/accelerator_4x4_v3_verification.md) for the
reported counters, scenarios, and verification scope.

## 9. Documentation

The design specification is provided in:

[v3.0 architecture and interface specification](docs/accelerator_4x4_v3_specification.md)

The specification defines the architecture, interfaces, buffer management,
computation control, output handshake, reset behavior, and verification
requirements. Appendix A reconciles the proposed interface with the actual
v2.0 streaming RTL.

* [v3.0 change notes](docs/release_notes_v3.0.md)
* [v2.0 release notes](docs/release_notes_v2.0.md)
* [v2.0 verification report](docs/accelerator_4x4_top_v2_verification.md)

## 10. Version History

| Version | Description                                                            |
| ------- | ---------------------------------------------------------------------- |
| v1.0    | Initial 4×4 INT8 matrix accelerator                                    |
| v2.0    | Input buffering and streaming interface enhancements                   |
| v3.0    | Computation/output overlap and registered ready/valid output interface |

## 11. Tools

* SystemVerilog
* EDA Playground
* Python golden model
* Git and GitHub

## 12. Release Status

Version 3.0 is the current implementation.

The project author confirmed v3.0 PASS on EDA Playground with Icarus Verilog
and SystemVerilog `-g2012`; the verification report records the supplied results.

See the [GitHub Releases page](https://github.com/adawu777/4x4_accelerator/releases)
for published releases and their tagged source snapshots.
The v2.0 RTL and verification assets remain preserved.
