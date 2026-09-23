# 4×4 INT8 Matrix Accelerator

A SystemVerilog RTL project implementing a 4×4 INT8 matrix multiplication accelerator based on a systolic array architecture.

The project progresses from a basic matrix accelerator in v1.0 to a streaming, automatically controlled design with ping-pong input buffering in v2.0. It includes RTL modules, self-checking SystemVerilog testbenches, design documentation, and an end-to-end simulation.

## 1. Project Overview

The accelerator computes:

$$
C = A \times B
$$

where:

* `A` and `B` are 4×4 matrices containing signed INT8 elements.
* `C` is a 4×4 matrix containing signed 32-bit accumulated results.
* Each output element is calculated as:

$$
C[i][j] = \sum_{k=0}^{3} A[i][k] \times B[k][j]
$$

The datapath uses a 4×4 systolic array with 16 processing elements (PEs). Each PE performs signed multiplication and accumulation while operands propagate through neighboring PEs.

## 2. Version History

| Version | Description                                                                                                                                        |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| v1.0    | Initial 4×4 INT8 matrix accelerator with a systolic datapath, input skew, controller, and directed verification.                                   |
| v2.0    | Streaming matrix input with ready/valid handshaking, dual-bank ping-pong buffering, automatic computation scheduling, and end-to-end verification. |

The v2.0 design retains the systolic computation architecture and adds a streaming input interface and matrix-level buffering.

## 3. v2.0 Architecture

```text
                  Streaming Input Interface
                in_valid / in_ready / A / B
                              |
                              v
                 +-------------------------+
                 | Matrix Input Ping-Pong  |
                 | Buffer                  |
                 | Bank 0 / Bank 1         |
                 +-------------------------+
                              |
                              v
                 +-------------------------+
                 | Accelerator Controller  |
                 | CLEAR / FEED / DRAIN /  |
                 | DONE                    |
                 +-------------------------+
                              |
                              v
                 +-------------------------+
                 | Input Skew              |
                 +-------------------------+
                              |
                              v
                 +-------------------------+
                 | 4×4 Systolic Array      |
                 | 16 Processing Elements  |
                 +-------------------------+
                              |
                              v
                     4×4 ACC32 Result
                         busy / done
```

The controller coordinates matrix execution and selects operands from the input buffer. Input skew aligns matrix operands before they enter the systolic array.

### Systolic Processing Element

Each PE receives signed operands and valid signals, performs a multiply-accumulate operation when the required operands are valid, and forwards operands to adjacent PEs.

The PE accumulator can be cleared before a new matrix computation.

### Ping-Pong Input Buffer

The v2.0 design uses two input banks. Each bank stores one paired set of 4×4 input matrices.

A complete matrix pair requires 16 accepted input beats. The matrices are loaded in row-major order, with one element from `A` and one element from `B` accepted together on each successful ready/valid handshake.

The dual-bank architecture allows a new matrix pair to be loaded while a previously completed pair is being computed, subject to bank availability.

Completed matrix pairs are processed in order.

## 4. v2.0 Top-Level Interface

Top-level module: `accelerator_4x4_top_v2`

| Signal            | Direction | Description                                             |
| ----------------- | --------- | ------------------------------------------------------- |
| `clk`             | Input     | System clock                                            |
| `rst_n`           | Input     | Active-low reset                                        |
| `in_valid`        | Input     | Indicates that input operand data is valid              |
| `in_ready`        | Output    | Indicates that the accelerator can accept an input beat |
| `a_data`          | Input     | Signed INT8 input element from matrix A                 |
| `b_data`          | Input     | Signed INT8 input element from matrix B                 |
| `busy`            | Output    | Indicates that a matrix computation is in progress      |
| `done`            | Output    | Indicates completion of a matrix computation            |
| `c_out[0:3][0:3]` | Output    | Signed ACC32 output matrix                              |

An input beat is accepted when `in_valid && in_ready` is true at the active clock edge.

The output matrix is checked during the `done` interval. `c_out` represents the live accumulator state and is not a separately retained result queue.

## 5. RTL Module Hierarchy

```text
accelerator_4x4_top_v2
├── matrix_input_pingpong_buffer
├── accelerator_4x4_controller
└── accelerator_4x4_core
    ├── input_skew
    └── systolic_array_4x4
        └── systolic_pe
```

### Main RTL Files

| File                              | Purpose                                         |
| --------------------------------- | ----------------------------------------------- |
| `systolic_pe.sv`                  | Signed multiply-accumulate processing element   |
| `systolic_array_4x4.sv`           | 4×4 systolic array and PE interconnections      |
| `input_skew.sv`                   | Input timing alignment for systolic computation |
| `accelerator_4x4_core.sv`         | Integration of input skew and systolic array    |
| `accelerator_4x4_controller.sv`   | Matrix computation control                      |
| `matrix_input_pingpong_buffer.sv` | Dual-bank matrix input storage and scheduling   |
| `accelerator_4x4_top_v2.sv`       | Complete v2.0 accelerator integration           |

## 6. Verification

The project includes standalone PE and systolic-array testbenches, as well as a self-checking v2.0 top-level testbench.

### v2.0 End-to-End Verification

**Status: PASS — confirmed by the user**

The user confirmed that the v2.0 top-level simulation completed successfully on EDA Playground. Codex did not independently run that simulation; detailed runtime logs and the remote source snapshot have not been independently verified.

**Simulation:** [EDA Playground — v2.0 End-to-End Verification](https://www.edaplayground.com/x/hPw2)

**DUT:** `accelerator_4x4_top_v2`

**Testbench:** `tb_accelerator_4x4_top_v2.sv`

The end-to-end testbench exercises the integrated streaming input, matrix buffering, controller, and systolic computation path.

Its verification environment includes a matrix multiplication reference model, transaction ordering checks, input handshake monitoring, and output comparisons.

The PASS result indicates that the executed simulation checks completed successfully. It does not imply exhaustive verification of every possible input or backpressure condition.

For the detailed verification methodology, test scenarios, results, and limitations, see:

[`docs/accelerator_4x4_top_v2_verification.md`](docs/accelerator_4x4_top_v2_verification.md)

### Additional Testbenches

| Testbench                      | Verification Target           |
| ------------------------------ | ----------------------------- |
| `tb_systolic_pe.sv`            | Individual processing element |
| `tb_systolic_array_4x4.sv`     | Systolic array                |
| `tb_accelerator_4x4_top_v2.sv` | Complete v2.0 accelerator     |

## 7. Running the Simulation

The v2.0 end-to-end simulation is available at:

https://www.edaplayground.com/x/hPw2

For a separate simulation setup, include these RTL sources in the Design section:

```text
systolic_pe.sv
systolic_array_4x4.sv
input_skew.sv
accelerator_4x4_core.sv
accelerator_4x4_controller.sv
matrix_input_pingpong_buffer.sv
accelerator_4x4_top_v2.sv
```

Use the following top-level testbench:

```text
tb_accelerator_4x4_top_v2.sv
```

Select the SystemVerilog language setting and a simulator compatible with the testbench.

## 8. Design and Verification Documentation

The project documentation includes design specifications and verification reports for the accelerator architecture and its major components.

The v2.0 end-to-end verification report is located at:

`docs/accelerator_4x4_top_v2_verification.md`

## 9. Engineering Topics Demonstrated

This project covers:

* Parameterized SystemVerilog RTL design.
* Signed fixed-point multiply-accumulate datapaths.
* Systolic array architecture and local operand propagation.
* Input skew and cycle-level data alignment.
* Finite-state-machine-based accelerator control.
* Ready/valid streaming interfaces.
* Ping-pong buffering and bank ownership.
* Transaction ordering and resource reuse.
* Self-checking testbenches and arithmetic reference models.
* Integrated RTL verification and debugging.

## 10. Project Status

**v2.0: End-to-end simulation PASS on EDA Playground, confirmed by the user.**

The current project demonstrates an integrated 4×4 INT8 matrix accelerator with streaming input, ping-pong buffering, automatic computation control, and a systolic array datapath.

The simulation and verification documentation provide a reproducible starting point for further RTL development and verification.

See the [v2.0 release notes](docs/release_notes_v2.0.md) and [implemented interface and timing specification](docs/accelerator_4x4_top_v2_integration.md). The v1.0 tag and historical specifications remain preserved.
