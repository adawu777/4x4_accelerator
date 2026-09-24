# 4×4 INT8 Matrix Accelerator

## v3.0 Architecture and Interface Specification

**Document:** `docs/accelerator_4x4_v3_specification.md`

**Version:** 3.0

**Status:** RTL implemented; EDA Playground PASS author-reported; local compilation/simulation pending

**Design:** 4×4 INT8 Matrix Accelerator

### 1. Purpose

Version 3.0 extends the existing v2.0 accelerator with a registered output interface and overlapping input loading, computation, and output transfer.

The architecture consists of:

* Two complete input matrix buffers operating in ping-pong mode.
* One 4×4 INT8 systolic array with 32-bit accumulators.
* One registered 4×4 ACC32 output buffer.
* A synchronous ready/valid output interface.
* Independent input-buffer, computation, and output-buffer control.

The design shall support the following concurrent operations when resources are available:

1. Transfer the result of transaction A to the downstream consumer.
2. Compute transaction B using the systolic array.
3. Load transaction C into an available input buffer.

The design shall preserve transaction ordering and shall not overwrite unconsumed data.

### 2. Scope and Compatibility

The v2.0 systolic array, processing elements, arithmetic behavior, and existing top-level functionality shall be preserved unless a modification is required to implement the v3.0 interface.

The existing `done` and `c_out` outputs shall remain available.

Version 3.0 introduces an independent registered output interface.

The existing v2.0 RTL shall be inspected before implementation to confirm:

* Actual top-level port names and widths.
* Input loading and transaction acceptance semantics.
* Input-buffer organization.
* Computation latency and DRAIN timing.
* Existing `busy`, `done`, and `c_out` behavior.
* Reset polarity and reset implementation.

Where the existing RTL differs from the assumptions in this specification, the differences shall be documented before modifying the design.

### 3. Datapath Parameters

| Parameter           | Default | Description                                |
| ------------------- | ------: | ------------------------------------------ |
| DATA_W              |       8 | Signed input element width                 |
| ACC_W               |      32 | Signed accumulator width                   |
| MATRIX_DIM          |       4 | Fixed matrix dimension                     |
| INPUT_BUFFER_COUNT  |       2 | Number of complete input matrix buffers    |
| OUTPUT_BUFFER_COUNT |       1 | Number of registered output matrix buffers |

The matrix operation is:

C[i][j] = Σ A[i][k] × B[k][j]

where i, j, and k range from 0 through 3.

Each input element is a signed two's-complement INT8 value.

Each output element is a signed ACC32 value.

The default output matrix contains 16 × 32 = 512 data bits.

The two input buffer banks collectively contain 2 × 2 × 16 × 8 = 512 data bits, excluding control and metadata.

### 4. Top-Level Interface

The existing v2.0 top-level ports shall be preserved.

The following interface is the proposed v3.0 logical contract. The implementation shall map this contract onto the actual v2.0 port names and input loading mechanism.

#### 4.1 Existing functional signals

| Signal   | Direction | Description                           |
| -------- | --------- | ------------------------------------- |
| clk      | Input     | System clock                          |
| rst_n    | Input     | Active-low reset                      |
| load     | Input     | Existing input-loading control        |
| start    | Input     | Computation start request             |
| a_matrix | Input     | Input matrix A                        |
| b_matrix | Input     | Input matrix B                        |
| busy     | Output    | Computation controller busy status    |
| done     | Output    | Computation completion indication     |
| c_out    | Output    | Existing systolic-array result output |

The exact dimensions and declaration styles of the existing matrix ports shall be retained.

#### 4.2 New v3.0 output interface

```systemverilog
output logic out_valid,
input  logic out_ready,

output logic signed [ACC_W-1:0]
    out_matrix [0:3][0:3]
```

The output matrix is transferred as one complete transaction.

A transfer occurs only when:

```systemverilog
out_valid && out_ready
```

is sampled HIGH at the rising clock edge.

All 16 output elements belong to the same matrix transaction.

No partial-matrix transfer is supported.

#### 4.3 Input acceptance interface

The input controller shall expose an unambiguous method for determining whether a new matrix pair can be accepted.

The proposed additional status signals are:

```systemverilog
output logic load_ready;
output logic start_ready;
```

These are separate from the output ready/valid interface.

If v2.0 already provides equivalent input acceptance signals, the existing signals shall be reused rather than duplicated.

For the proposed single-cycle request protocol:

```systemverilog
load_accept  = load  && load_ready;
start_accept = start && start_ready;
```

An input request is accepted only when its corresponding acceptance condition is true.

Requests presented while the associated ready signal is LOW are not accepted or automatically queued.

A complete input matrix pair shall be captured atomically on `load_accept`, provided the existing v2.0 loading mechanism supports full-matrix capture.

If v2.0 instead uses a multi-cycle loading interface, the original loading protocol shall be preserved and the buffer shall become FULL only after the complete matrix pair has been received.

A partially loaded buffer shall never be eligible for computation.

### 5. Input Buffer Architecture

#### 5.1 Buffer organization

Two complete input buffer banks shall be provided.

Each bank stores one matrix pair:

```systemverilog
logic signed [DATA_W-1:0]
    a_buf [0:1][0:3][0:3];

logic signed [DATA_W-1:0]
    b_buf [0:1][0:3][0:3];
```

Bank 0 and Bank 1 are independently controlled.

One bank may supply operands to the systolic array while the other bank receives a new matrix pair.

#### 5.2 Buffer ownership states

Each input bank shall have one of the following logical states:

| State   | Description                                                   |
| ------- | ------------------------------------------------------------- |
| EMPTY   | Available for loading                                         |
| LOADING | A multi-cycle input transaction is in progress, if applicable |
| FULL    | Contains one complete matrix pair waiting for computation     |
| ACTIVE  | Owned by the current computation                              |

A bank shall not be written while it is FULL or ACTIVE.

A bank shall not be selected for computation while it is EMPTY or LOADING.

A FULL bank shall retain its data until the corresponding computation is accepted.

An ACTIVE bank shall retain the operands required by the systolic array until the final operand has been safely consumed.

Once all operands have been consumed, the bank may return to EMPTY even if the computation remains in DRAIN, provided no subsequent datapath operation requires its contents.

Otherwise, the bank shall remain ACTIVE until the required computation stage has completed.

#### 5.3 Input loading rules

Loading may proceed concurrently with computation when an EMPTY bank exists.

For example:

* Bank 0 is ACTIVE for transaction B.
* Bank 1 is EMPTY.
* Transaction C may be loaded into Bank 1.

The loading operation shall not modify Bank 0.

If both banks are FULL or ACTIVE, `load_ready` shall be LOW.

The input controller shall never overwrite a FULL bank to accept a newer transaction.

A bank in the LOADING state shall be reserved for the current input transaction.

#### 5.4 Bank selection

The controller shall maintain a bank selection mechanism for loading and computation.

Suggested internal signals include:

```systemverilog
logic load_sel;
logic compute_sel;
```

`load_sel` identifies the bank selected for the next accepted loading operation.

`compute_sel` identifies the bank owned by the active computation.

Bank selection shall be based on actual buffer availability, not solely on unconditional toggling of a selection bit.

For example, if Bank 0 becomes EMPTY while Bank 1 remains FULL, Bank 0 shall be eligible for the next load.

The controller shall not select Bank 1 for loading merely because a toggle bit points to it.

#### 5.5 Transaction ordering

Input matrix pairs shall be computed in their accepted loading order.

If both input banks contain pending transactions, the older accepted transaction shall be selected first.

The implementation may use transaction-order metadata or a two-entry FIFO-style ownership controller.

The design shall not assume that bank index alone determines transaction age.

Output results shall preserve the same transaction order.

### 6. Computation Start Conditions

A new computation may start when:

1. A complete input matrix pair is available.
2. The compute FSM is IDLE.
3. The systolic-array accumulators are available.
4. No previous result remains pending in the accumulators.

The output buffer is not required to be EMPTY.

The proposed acceptance condition is:

```systemverilog
start_accept =
    start &&
    start_ready;
```

`start_ready` shall be HIGH only when all computation resources and a complete input transaction are available.

An accepted start request shall select the oldest pending input transaction.

The selected input bank shall become ACTIVE.

The output buffer may simultaneously hold an older result.

A new computation shall not clear the accumulators while they contain a completed result awaiting transfer to the output buffer.

### 7. Compute FSM

The computation controller shall implement the following logical states:

```systemverilog
typedef enum logic [2:0] {
    IDLE,
    CLEAR,
    FEED,
    DRAIN,
    RESULT_PENDING
} compute_state_t;
```

#### 7.1 IDLE

The computation engine is available for a new transaction.

The controller waits for an accepted start request.

An accepted request selects the oldest pending input bank and transitions the controller to CLEAR.

#### 7.2 CLEAR

The accumulator registers are initialized for the new matrix operation.

The input transaction and selected bank shall remain associated with the computation.

The controller then transitions to FEED.

#### 7.3 FEED

Input operands are supplied to the systolic array according to the existing v2.0 input-skew and feed schedule.

The selected input bank shall remain protected until all required operands have been consumed.

The other input bank may accept a new matrix pair when available.

#### 7.4 DRAIN

The controller waits for the remaining in-flight operands and partial sums to complete.

The DRAIN latency shall follow the verified v2.0 implementation.

Output backpressure shall not interrupt an incomplete systolic-array computation.

The controller shall transition to RESULT_PENDING only after all 16 result elements are complete and stable.

#### 7.5 RESULT_PENDING

The accumulator registers contain one complete matrix result.

The controller shall assert an internal `acc_result_valid` condition.

The accumulator contents shall remain stable until the result is transferred to the output buffer.

The controller shall not enter CLEAR for a new transaction while the previous result remains pending.

When the output buffer can accept the result, the complete matrix shall be transferred.

The controller may then return to IDLE.

### 8. Output Buffer Architecture

#### 8.1 Result storage

The output buffer shall contain one complete registered matrix:

```systemverilog
logic signed [ACC_W-1:0]
    result_buf [0:3][0:3];

logic output_full;
```

The output interface shall be driven from this registered buffer.

```systemverilog
assign out_valid = output_full;
```

Each output element shall correspond to the matching element in `result_buf`.

The output interface shall not directly expose the changing internal accumulator values as its valid result payload.

#### 8.2 Output transfer

Define:

```systemverilog
output_fire =
    out_valid && out_ready;
```

An output transaction is consumed on a rising clock edge when `output_fire` is HIGH.

When `out_valid` is HIGH and `out_ready` is LOW, the output buffer shall retain its current result.

The complete `out_matrix` payload and `out_valid` shall remain stable until a successful transfer or reset.

#### 8.3 Output buffer acceptance

The output buffer can accept a new result when it is EMPTY or when its current result is consumed on the same clock edge.

```systemverilog
output_can_accept =
    !output_full || output_fire;
```

The internal result transfer condition is:

```systemverilog
result_transfer =
    acc_result_valid &&
    output_can_accept;
```

`result_transfer` shall cause all 16 accumulator values to be captured into the output buffer on the same rising edge.

#### 8.4 Simultaneous output and replacement

The following operation shall be supported:

* Output Buffer contains transaction A.
* Accumulators contain completed transaction B.
* `out_valid` and `out_ready` are HIGH.

At the rising edge:

1. The downstream consumer samples transaction A.
2. Transaction B is captured into the output buffer.
3. The output buffer remains FULL.
4. The accumulator result is released.

The old output payload shall be consumed before the registered payload is replaced.

The implementation shall use nonblocking sequential assignments to preserve this behavior.

#### 8.5 Output occupancy update

The required occupancy behavior is:

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        output_full <= 1'b0;
    end
    else begin
        if (result_transfer)
            output_full <= 1'b1;
        else if (output_fire)
            output_full <= 1'b0;
    end
end
```

The output buffer payload shall be updated only when `result_transfer` is asserted, except for reset behavior if implemented.

The implementation shall ensure that `result_transfer` uses the completed and stable accumulator result, not the accumulator values from an incomplete computation.

### 9. Computation and Output Overlap

The following operations shall be independently supported:

| Operation             | Resource               |
| --------------------- | ---------------------- |
| Load transaction C    | Available input buffer |
| Compute transaction B | Systolic array and ACC |
| Output transaction A  | Output buffer          |

The output buffer may remain FULL while a newer transaction is computed.

If computation B completes while the output buffer still contains A, the result of B shall remain in the accumulator registers.

The computation controller shall remain in RESULT_PENDING until B can be transferred.

No additional computation may clear the accumulators while B remains pending.

The input controller may continue accepting input transactions into available input banks, subject to bank capacity and ownership rules.

If both input banks are occupied, further input loading shall be rejected or stalled according to the defined input acceptance protocol.

### 10. Busy and Done Semantics

The v3.0 computation controller shall distinguish computation completion from output consumption.

`done` shall indicate that a matrix computation has completed.

`out_valid` shall indicate that a complete matrix result is available at the registered output interface.

The two signals are not required to assert in the same cycle.

The proposed v3.0 `done` behavior is a one-cycle completion pulse after all accumulator results become valid.

The proposed `busy` behavior is HIGH whenever the computation FSM is not IDLE, including RESULT_PENDING.

Therefore:

* `busy = 0` does not imply that the output buffer is empty.
* `done = 1` does not imply that the downstream consumer has received the result.
* `out_valid = 1` indicates a result awaiting or undergoing output transfer.

Before implementation, the existing v2.0 timing and meaning of `busy` and `done` shall be checked.

Any required change to externally observable behavior shall be explicitly documented and covered by compatibility tests.

### 11. Reset Behavior

The design shall use the existing active-low reset.

When reset is asserted:

* The compute FSM shall return to IDLE.
* All input-buffer ownership states shall return to EMPTY.
* Any partial input-loading transaction shall be discarded.
* The output buffer valid flag shall be cleared.
* The pending accumulator result flag shall be cleared.
* The completion indication shall be cleared.
* Input and computation transaction-order metadata shall be reset.

Pending input, computation, and output transactions shall be invalidated.

The output payload registers need not be physically cleared if `out_valid` is LOW and no valid transaction can be inferred from their contents.

Reset during DRAIN shall abort the incomplete computation.

Reset during RESULT_PENDING shall discard the untransferred accumulator result.

Reset during output backpressure shall invalidate the pending output transaction.

No transaction that was invalidated by reset shall reappear after reset is released.

### 12. Verification Requirements

The v3.0 testbench shall verify the following cases:

**Input-buffer verification**

* Loading into an EMPTY bank.
* Loading transaction C while transaction B is computing.
* Correct FULL and ACTIVE ownership behavior.
* Rejection of loading when no input bank is available.
* No overwrite of a FULL or ACTIVE bank.
* Correct ordering when both banks contain pending transactions.
* Correct release of a bank after its operands are consumed.
* Reset during partial loading, if multi-cycle loading is supported.

**Computation verification**

* Correct 4×4 signed INT8 matrix multiplication.
* Correct handling of negative and boundary input values.
* Correct CLEAR, FEED, DRAIN, and RESULT_PENDING sequencing.
* No accumulator clearing while a completed result remains pending.
* Correct computation when the output buffer is already FULL.
* Correct association between input transactions and computed results.

**Output verification**

* Output payload correctness for all 16 elements.
* Normal ready/valid transfer.
* Output stability during backpressure.
* Output valid retention while ready is LOW.
* Simultaneous consumption of an old result and capture of a new result.
* No duplicate output transactions.
* No lost output transactions.
* Preservation of transaction ordering.

**Overlap verification**

* Load C while computing B and outputting A.
* Compute B while A is stalled at the output.
* Hold B in ACC while A remains unconsumed.
* Transfer B immediately when output capacity becomes available.
* Resume computation after the pending accumulator result is released.
* Sustained operation under varying downstream readiness.

**Reset verification**

* Reset during input loading.
* Reset during FEED.
* Reset during DRAIN.
* Reset during RESULT_PENDING.
* Reset during output backpressure.
* No stale output-valid assertion after reset.

The scoreboard shall associate each accepted input transaction with its expected output matrix.

Expected results shall be generated by the existing Python golden model or an equivalent independently implemented reference model.

Output comparisons shall be performed only on successful output handshakes.

The testbench shall also verify that `done` occurs exactly once for each completed, non-aborted computation.

### 13. Implementation Constraints

The implementation shall:

1. Preserve the existing v2.0 RTL and verification assets.
2. Introduce v3.0 functionality without unnecessarily rewriting the arithmetic datapath.
3. Use synthesizable SystemVerilog.
4. Use nonblocking assignments for sequential register updates.
5. Avoid combinational loops between ready and valid signals.
6. Preserve stable output data during backpressure.
7. Maintain correct transaction ordering.
8. Prevent buffer ownership conflicts and accumulator overwrite.
9. Avoid introducing a second output buffer or an additional result FIFO.
10. Document all changes to existing externally visible interface timing.

The implementation shall not assume that an input buffer is available merely because the compute FSM is IDLE.

Likewise, it shall not assume that the accumulator is available merely because the output buffer can accept new data.

Each resource shall be managed according to its own occupancy and ownership state.

### 14. Release Criteria

Version 3.0 shall be considered ready for release only after:

* The actual v2.0 RTL has been reviewed and interface compatibility has been confirmed.
* All required v3.0 RTL changes have been implemented.
* Existing v2.0 regression tests pass.
* New v3.0 functional and overlap tests pass.
* Output backpressure and simultaneous transfer cases pass.
* Reset and transaction-ordering tests pass.
* The verification report records the simulator, test environment, test results, and any remaining limitations.
* README and release notes accurately describe the implemented and verified functionality.

A specification or completed RTL implementation alone does not establish verification completion.

**End of Specification — v3.0**

## Appendix A — Reconciliation with inspected v2.0 RTL

This appendix records implementation mappings and compatibility differences
before updating the earlier v3 draft to the full user-supplied specification.
Sections 1–14 above are the supplied requirements; the status line has been
updated to reflect implementation work, not verification completion.

### Actual v2.0 inspection


* Released streaming top: `accelerator_4x4_top_v2`, defaults `DATA_W=8`,
  `ACC_W=32`; ports `clk`, `rst_n`, `in_valid`, `in_ready`, `a_data`,
  `b_data`, `busy`, `done`, and `c_out[0:3][0:3]`. The older
  `accelerator_4x4_top` is the separate load/start interface.
* `matrix_input_pingpong_buffer` already stores two paired A/B banks.
  Each accepted beat writes both matrices at `[count/4][count%4]`. Sixteen
  beats complete a transaction; pauses preserve the partial count. States
  are EMPTY, LOADING, FULL, COMPUTING. A two-entry FIFO stores completed
  bank IDs. Its simultaneous push/pop updates count without changing it.
  An active compute bank is locked until `compute_done`. This is existing
  v2.0 behavior, not assumed v3.0 output ownership support.
* The top instantiates `accelerator_4x4_controller`, **not** the alternative
  `accelerator_4x4_controller_registered`. Its Moore FSM is
  IDLE → CLEAR → FEED (four edges) → DRAIN (six edges) → DONE → IDLE.
  Start E0, clear E1, feed E2–E5, last PE update E11, bank release E12,
  earliest queued restart E13. DRAIN tests pre-edge counter 5.
* v2 `busy` is high in CLEAR/FEED/DRAIN; `done` is high for the DONE
  interval. `c_out` directly exposes live accumulators, changing on the
  next clear/compute. There is no output backpressure or output register bank.
* `accelerator_4x4_core` takes four signed A/B lanes, per-lane valid,
  `clear_acc`, clock and reset. `input_skew` delays lanes 0/1/2/3 cycles.
  `systolic_array_4x4` has the same lane/clear interface and exposes all 16
  PE accumulators. A propagates horizontally; B vertically. A PE updates
  only when both valids are high; clear takes priority. Pipeline valids
  shift every clock and reset asynchronously. No separate accumulator
  read enable or result capture port is needed.
* All eleven existing testbenches: `tb_systolic_pe`,
  `tb_systolic_array_4x4`, `tb_input_skew`, `tb_matrix_operand_buffer`,
  `tb_matrix_input_pingpong_buffer`, `tb_accelerator_4x4_controller`,
  `tb_accelerator_4x4_interconnect`, `tb_accelerator_4x4_matmul`,
  `tb_accelerator_4x4_vectors`, `tb_accelerator_4x4_top`, and
  `tb_accelerator_4x4_top_v2`. There is no dedicated registered-controller
  testbench. Existing Python `golden_model.matmul_4x4` is the numerical oracle.


### Mapping and decisions

| Proposed logical interface/state | Actual v3.0 implementation |
|---|---|
| Top level | New `accelerator_4x4_top_v3`; released `accelerator_4x4_top_v2` and all shared RTL remain unchanged |
| `load`, `load_ready`, `a_matrix`, `b_matrix` | Existing `in_valid`, `in_ready`, signed `a_data`/`b_data`; 16 accepted paired beats form A and B in row-major order. No duplicate load-ready port or full-matrix load input |
| `start`, `start_ready` | Preserve v2 automatic scheduling: internal `compute_start = rst_n && IDLE && matrix_ready`; no external start request existed in v2. `matrix_ready` identifies the oldest complete input pair |
| ACTIVE bank | Existing buffer state named COMPUTING; equivalent ownership and write protection |
| `c_out[0:3][0:3]` | Retain signed ACC_W-bit **live** accumulator output, as in v2; it is not the output-handshake payload |
| `out_matrix[0:3][0:3]` | New signed ACC_W-bit registered output payload, paired with out_valid/out_ready |
| `done` | One registered clock pulse after final DRAIN edge E11, when all live c_out values are complete. Independent of output capture and downstream ready |
| `busy` | High in CLEAR/FEED/DRAIN/RESULT_PENDING; unlike v2 it remains high during the completion pulse and pending-result stall |
| `acc_result_valid` | Explicit internal decode of RESULT_PENDING, masked during reset |
| MATRIX_DIM / buffer counts | Fixed architecture constants 4 / 2 / 1, not tunable module parameters; retain DATA_W=8 and ACC_W=32 parameters from v2 |

No v2 public port is removed or repurposed. The full-matrix load/start ports
shown in section 4.1 belong to the older `accelerator_4x4_top`, not the actual
v2 streaming top. The multi-cycle input mapping above follows section 4.3;
automatic scheduling preserves v2 behavior instead of introducing manual starts.
A beat is accepted only with in_valid && in_ready on a rising edge. Producers
hold valid and both elements through stalls. Complete pairs execute in input
order; an incomplete pair is never scheduled. No acceptance occurs in reset.

### Timing and resource ownership

| Edge relative to accepted internal start E0 | Behavior after edge settles |
|---|---|
| E0 | Pop oldest completed bank ID, mark bank COMPUTING, enter CLEAR |
| E1 | Clear accumulators; enter FEED with k=0 |
| E2–E5 | Feed slices k=0..3; enter DRAIN at E5 |
| E6–E10 | Drain remaining products |
| E11 | Final PE update; done=1; busy=1; enter RESULT_PENDING; acc_result_valid=1; release input bank |
| E12 | done=0; earliest output capture using stable completed c_out; return IDLE only if output slot can accept |
| Later pending edges | Keep busy=1, acc_result_valid=1, done=0, feed/clear/start=0 until capture is possible |
| Edge after capture | Earliest next queued computation start, regardless of unread output occupancy |

Input bank release at E11 is conservative: operands have left the bank at E5,
but it remains protected through DRAIN. This is permitted by section 5.2.
v2 released the bank at E12. Freed storage is writable at the next edge;
there is no same-edge ready bypass. The unchanged bank-ID FIFO supports
simultaneous enqueue/dequeue and availability-based selection. During a
pending-result stall, both released input banks may accept future work.
Maximum complete outstanding transactions: two in input banks, one in the
accumulators, one in the single output buffer.

Never copy at E11: nonblocking assignment semantics would read the pre-final-MAC
accumulator values. The first capture opportunity is E12. Define output_fire
as out_valid && out_ready, output_can_accept as !output_full || output_fire,
and result_capture as acc_result_valid && output_can_accept. A capture takes
priority over clearing output_full on consumption, so old-output consumption
and new-result replacement share an edge without a valid bubble. out_matrix
is written only on capture or reset; c_out can change during the next compute.

Reset is asynchronous active-low. It cancels partial, queued, active, pending,
and output transactions; resets control/metadata and datapath; and clears
out_matrix as well as valid/done. Clearing payload is the optional reset
choice permitted by section 11. Input data banks themselves need not clear.
As in v2, ACC_W >= 2*DATA_W is required for the PE product extension;
2*DATA_W+2 retains every four-product sum. Default INT8/ACC32 does not overflow.

### Corrections to the earlier v3 draft

The earlier draft was based on the eight summary requirements before this
full specification was available. Its registered c_out and capture-time done
are superseded: c_out is live, out_matrix is separately registered, and done
pulses at compute completion E11 even under backpressure. Tests must count
completed computations independently of output copies and output transfers.
Output numerical comparisons occur only on successful output handshakes;
separate payload snapshots check stability between transfers. Live c_out is
checked on completion and while pending to cover legacy behavior/protection.

### Verification and release status

The user-supplied requirements in section 12 are the verification contract.
The regression includes all eleven original testbenches and the v3 bench.
Mandatory coverage includes three-way load/compute/output-transfer overlap,
compute under output stall, both banks occupied, simultaneous queue push/pop,
same-edge output consume/replace, once-per-computation done, and reset recovery.
See `accelerator_4x4_v3_verification.md` for implementation coverage and actual
execution results. No local simulator was found. EDA Playground PASS is now
author-reported; the run's source snapshot, configuration, and logs have not
been independently verified. No
unresolved interface decision remains against the supplied text; the explicit
streaming/automatic-start mapping above is the compatibility adaptation.
No synthesis, timing closure, formal proof, commit, tag, or release is implied.
