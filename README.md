# 4×4 INT8 Matrix Accelerator

A synthesizable SystemVerilog implementation of a **4×4 signed INT8 matrix multiplication accelerator** based on a **systolic array architecture**.

The accelerator computes:

\[
C = A \times B
\]

where:

- `A` is a 4×4 signed INT8 matrix
- `B` is a 4×4 signed INT8 matrix
- `C` is a 4×4 signed 32-bit result matrix

The project includes RTL design, directed SystemVerilog verification, a Python golden model, deterministic test-vector generation, and end-to-end self-checking verification.

---

## Architecture

The top-level architecture is:

```text
                 +----------------------+
                 |      Controller      |
                 | CLEAR / FEED / DRAIN |
                 +----------+-----------+
                            |
                            v
A Matrix -----> +----------------------+
B Matrix -----> |    Operand Buffer    |
                +----------+-----------+
                           |
                    A[:,k], B[k,:]
                           |
                           v
                +----------------------+
                |      Input Skew      |
                | delays: 0/1/2/3      |
                +----------+-----------+
                           |
                           v
                +----------------------+
                |   4×4 Systolic Array |
                |                      |
                | PE  PE  PE  PE       |
                | PE  PE  PE  PE       |
                | PE  PE  PE  PE       |
                | PE  PE  PE  PE       |
                +----------+-----------+
                           |
                           v
                      C[0:3][0:3]
```

The design contains **16 processing elements (PEs)**.

Each PE performs a signed multiply-accumulate operation:

```text
acc = acc + a × b
```

while forwarding:

- `A` horizontally
- `B` vertically
- corresponding valid signals with the data

---

## Systolic Dataflow

For matrix multiplication:

\[
C[i][j] = \sum_{k=0}^{3} A[i][k] \times B[k][j]
\]

During each FEED cycle, the operand buffer selects:

```text
A[:, k]
B[k, :]
```

for:

```text
k = 0, 1, 2, 3
```

The input-skew network delays lanes by:

| Lane | Delay |
|---|---:|
| 0 | 0 cycles |
| 1 | 1 cycle |
| 2 | 2 cycles |
| 3 | 3 cycles |

This creates the required wavefront so that the correct `A[i][k]` and `B[k][j]` values meet at each PE.

---

## Controller

The accelerator uses a Moore FSM:

```text
IDLE
  |
 start
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
DONE
  |
  v
IDLE
```

Operation timing:

| State | Cycles | Description |
|---|---:|---|
| CLEAR | 1 | Clear all PE accumulators |
| FEED | 4 | Feed `k = 0,1,2,3` |
| DRAIN | 6 | Allow the systolic wavefront to complete |
| DONE | 1 | Signal completion |

`busy` is asserted during:

```text
CLEAR + FEED + DRAIN
```

for a total of **11 cycles after start is accepted**.

`done` is asserted for one cycle after computation completes.

---

## Top-Level Interface

Main control signals:

```systemverilog
input  logic load;
input  logic start;

output logic busy;
output logic done;
```

Matrix interfaces:

```systemverilog
input logic signed [7:0] a_matrix [0:3][0:3];
input logic signed [7:0] b_matrix [0:3][0:3];

output wire signed [31:0] c_out [0:3][0:3];
```

Typical operation:

```text
Load A/B
   ↓
load = 1 for one clock
   ↓
start = 1 for one clock
   ↓
busy = 1
   ↓
matrix computation
   ↓
busy = 0
done = 1
   ↓
read C
```

---

## RTL Hierarchy

```text
accelerator_4x4_top
│
├── accelerator_4x4_controller
│
├── matrix_operand_buffer
│
└── accelerator_4x4_core
    │
    ├── input_skew
    │
    └── accelerator_4x4
        │
        └── 16 × systolic_pe
```

---

## Verification Strategy

The project uses an independent Python golden model.

```text
Python Golden Model
        |
        v
generate_vectors.py
        |
        +------> input_vectors.txt
        |               |
        |               v
        |              DUT
        |               |
        |               v
        |             c_out
        |               |
        +------> expected_vectors.txt
                        |
                        v
                    Scoreboard
                        |
                   PASS / FAIL
```

The SystemVerilog end-to-end testbench **does not calculate matrix multiplication itself**.

Expected results are generated independently by Python and stored in:

```text
vectors/expected_vectors.txt
```

The scoreboard compares all 16 DUT outputs against the Python-generated results.

---

## Verification Coverage

The following functionality has been tested:

- PE signed multiply-accumulate
- PE data and valid forwarding
- accumulator clear
- asynchronous reset
- horizontal A propagation
- vertical B propagation
- 4×4 systolic interconnect
- input skew of 0/1/2/3 cycles
- signed matrix multiplication
- INT8 boundary values
- operand-buffer load and hold behavior
- `k = 0,1,2,3` operand selection
- controller state timing
- `busy` / `done` protocol
- multiple matrix operations without global reset
- Python-generated vector testing
- complete top-level end-to-end matrix multiplication

All implemented v1.0 directed and end-to-end tests pass.

---

## Project Structure

```text
4x4_accelerator/
│
├── rtl/
│   ├── systolic_pe.sv
│   ├── accelerator_4x4.sv
│   ├── input_skew.sv
│   ├── accelerator_4x4_core.sv
│   ├── accelerator_4x4_controller.sv
│   ├── matrix_operand_buffer.sv
│   └── accelerator_4x4_top.sv
│
├── tb/
│   ├── unit/integration testbenches
│   └── tb_accelerator_4x4_top.sv
│
├── python/
│   ├── golden_model.py
│   └── generate_vectors.py
│
├── vectors/
│   ├── input_vectors.txt
│   └── expected_vectors.txt
│
├── docs/
│   └── 4x4_accelerator_v1.0_specification.pdf
│
└── README.md
```

---

## Generate Test Vectors

From the project root:

```bash
python3 python/generate_vectors.py
```

The script generates:

```text
vectors/input_vectors.txt
vectors/expected_vectors.txt
```

and checks the generated vectors against the Python golden model.

---

## Design Parameters

Default configuration:

```text
DATA_W = 8
ACC_W  = 32
Matrix = 4×4
PEs    = 16
```

Arithmetic is signed.

The v1.0 implementation does not perform saturation.

---

## v1.0 Status

**RTL implementation complete.**

**Directed verification complete.**

**Python golden-model verification complete.**

**Top-level end-to-end verification complete.**

The v1.0 RTL is frozen for release.

---

## Future Work

Possible future extensions include:

- ready/valid command interface
- ping-pong operand buffers
- SRAM-based operand storage
- configurable matrix dimensions
- larger systolic arrays
- matrix tiling
- explicit overflow/saturation behavior
- performance counters
- UVM verification environment