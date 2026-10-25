# Cortex64/128 v0.1.4 — Implementation status

## Change in this increment

This is a verification-focused increment built on v0.1.3. The CPU datapath is intentionally not advertised as broader ISA support. A new directed SystemVerilog testbench, `sim/tb/cortex_csr_trap_tb.sv`, drives the existing core through:

- selected `mscratch` CSR read/modify/write operations (`CSRRW`, `CSRRS`, `CSRRWI`, `CSRRC`);
- `ECALL` trap entry with `mcause=11`, `mepc` set to the faulting instruction, and `mtval=0`;
- trap handler dispatch, `mepc` update, and `MRET` return;
- an attempted write to read-only `misa`, expected to trap as an illegal instruction (`mcause=2`), with instruction bits recorded in `mtval`;
- a second `MRET` and final architectural-state assertions.

The test is included in `tools/test.sh` and `tools/lint.sh` for Verilator and Icarus Verilog.

## Checks performed in this workspace

- `python3 -m pytest -q tests/unit`: **6 passed**. These tests check test-program structure and encoded instruction fields; they do not simulate the RTL.
- `python3 sim/reference_model/rv64_smoke.py`: **passed**, software model reports 33 instructions and marker `x31=0x5a`; this checks the smoke image/model, not the SystemVerilog core.
- `./tools/test.sh`: Python checks pass, then exits **127** because neither Verilator nor Icarus Verilog is installed.
- `./tools/lint.sh`: exits **127** because Verilator is not installed. Installing from the configured Debian repository was attempted, but DNS resolution for `deb.debian.org` failed in this workspace.
- FPGA synthesis / timing: **not run**.

Run the following from the project root on a system with Python 3 and `pytest`:

```sh
python3 -m pytest -q tests/unit
python3 sim/reference_model/rv64_smoke.py
./tools/test.sh
./tools/lint.sh
```

`tools/test.sh` exits with an error when no RTL simulator is installed; it does not silently report full verification success.

## Known limitations

- This remains an RV64 execution subset, not a compliant full RV64I implementation.
- Only machine mode is intended. No interrupt controller, delegation, supervisor/user modes, paging, or architectural debug module is implemented.
- `fault` and `fault_code` are sticky diagnostics for the most recently taken trap in this prototype. They are not a substitute for architectural trap handling and do not mean that software failed to handle the exception.
- The BRAM/scratchpad module is not a DDR4 controller or PHY.
- No RTL simulation, formal verification, FPGA synthesis, timing closure, or physical-board validation should be claimed until those flows actually pass.

## Next recommended step

Run the new directed bench on Verilator, fix any failing assertions/RTL bugs, then add separate directed tests for misaligned accesses and instruction/data bus errors. After simulation passes, run synthesis on a selected FPGA board and begin the DDR4 adapter/controller integration as a separate task.
