# RTL naming refactor

The current checkout uses the names below. Parameters, ports, arithmetic,
registers, cycle timing, instance names, and test behavior are preserved.
The core, controller, v1 top, and v2 top retain their module names.

| Historical RTL file/module | Current RTL file/module |
|---|---|
| `rtl/accelerator_4x4_pe.sv` / `accelerator_4x4_pe` | `rtl/systolic_pe.sv` / `systolic_pe` |
| `rtl/accelerator_4x4.sv` / `accelerator_4x4` | `rtl/systolic_array_4x4.sv` / `systolic_array_4x4` |

The renamed array instantiates `systolic_pe`; `accelerator_4x4_core` instantiates
`systolic_array_4x4`. The core's existing instance name `u_accelerator_4x4` is
retained intentionally to preserve hierarchy paths.

The corresponding unit-test filenames and module declarations are now
`tb/tb_systolic_pe.sv` / `tb_systolic_pe` and
`tb/tb_systolic_array_4x4.sv` / `tb_systolic_array_4x4`. They instantiate
`systolic_pe` and `systolic_array_4x4`, respectively. Their stimulus,
scoreboards, assertions, timing, and expected results are unchanged.
Other testbench names, including `tb_accelerator_4x4_interconnect` and
`tb_accelerator_4x4_top_v2`, remain unchanged.

## Unit-test commands

From the repository root, with a compatible Verilator installation, compile
and run each renamed testbench separately. These commands have not been
executed in the current environment:

```sh
verilator --binary --timing -Wno-fatal --top-module tb_systolic_pe \
  rtl/systolic_pe.sv tb/tb_systolic_pe.sv
./obj_dir/Vtb_systolic_pe

verilator --binary --timing -Wno-fatal --top-module tb_systolic_array_4x4 \
  rtl/systolic_pe.sv rtl/systolic_array_4x4.sv tb/tb_systolic_array_4x4.sv
./obj_dir/Vtb_systolic_array_4x4
```

Review all compiler warnings even though `-Wno-fatal` permits them.

Current hierarchy/directory examples are updated in README.md. The lint source
list in `accelerator_4x4_top_v2_integration.md` and the simulation source list in
`tb_accelerator_4x4_top_v2.md` use the renamed files. No standalone simulation
scripts, compilation file lists, or PDF generation scripts were found in this
project snapshot.

## Historical PDF audit

PDFs were inspected by extracting text from every page. No corresponding
editable specification source or reproducible PDF generation workflow was
found in the project; no PDFs were rewritten or regenerated.

| PDF | Remaining references to renamed RTL |
|---|---|
| `4x4_accelerator_v1.0_specification.pdf` | Page 3 hierarchy: `accelerator_4x4`; page 5 directory tree: `accelerator_4x4.sv` |
| `4x4_accelerator_controller_v1.0_specification.pdf` | None found in extracted text |
| `accelerator_4x4_v2_pingpong_input_buffer_design_spec.pdf` | None found in extracted text |

The old names in the v1.0 specification describe the historical release and
should be interpreted using the mapping above when working with the current
checkout. Historical release information and Git tags remain intact.
An additional all-page text search found no references to either of the two
superseded unit-test names in these PDFs.

## Validation status

Static comparison checks that every existing RTL/testbench change is only the
intended name substitution, with unrelated identifiers unchanged. Current
editable source references and documented compilation paths are checked for
consistency. These checks are not a behavioral equivalence proof.

Neither `verilator` nor `iverilog` was found on PATH during this refactor.
Compilation and simulation were not executed. No new simulation PASS, release,
commit, or push is claimed. Use the updated command in
`tb_accelerator_4x4_top_v2.md` when a compatible simulator becomes available.
