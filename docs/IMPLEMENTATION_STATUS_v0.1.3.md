# Cortex64/128 v0.1.3 — Implementation status

## Added in this increment

- Selected machine-mode CSR storage/read paths: `mstatus`, `misa`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mcycle`, and `instret` aliases.
- Selected Zicsr operations: `CSRRW[I]`, `CSRRS[I]`, and `CSRRC[I]`.
- Synchronous trap entry helper saving EPC/cause/tval and redirecting to direct-mode `mtvec`.
- `MRET` and `ECALL` handling in the execution state machine, plus sticky diagnostic outputs.
- `HALT_ON_EBREAK` parameter for testbench-friendly termination behavior.

## Checks performed in this workspace

- `python3 -m pytest -q tests/unit`: **3 passed**.
- `python3 sim/reference_model/rv64_smoke.py`: **passed**, 33 software-model instructions, success marker `x31=0x5a`.
- RTL simulation: **not run**; neither Verilator nor Icarus Verilog is installed in this workspace.
- FPGA synthesis: **not run**.

The Python reference model validates the smoke-test program/image, not the SystemVerilog implementation. These results must not be interpreted as proof that CSR/trap RTL works.

## Required next verification

1. Add directed RTL tests for each supported CSR instruction and CSR read-only behavior.
2. Test `ECALL -> trap handler -> MRET`, verifying `mepc`, `mcause`, `mtval`, `mstatus.MPIE/MIE/MPP`, and the resumed PC.
3. Test illegal CSR addresses, writes to read-only CSRs, misaligned loads/stores, and bus response errors.
4. Run Verilator lint and RTL testbenches; fix all functional errors and review warnings.
5. Run synthesis and timing analysis in the target FPGA vendor flow.

## Known limitations and review notes

- Only machine mode is intended; no supervisor/user privilege modes, interrupt controller, delegation, or virtual memory.
- The ISA implementation remains a subset, not full RV64I/Zicsr/privileged-spec compliance.
- Trap/CSR logic has not been simulator-verified and needs a focused correctness review before hardware use.
- The BRAM module is not a DDR4 controller/PHY; DDR4 integration is a separate milestone.
- `fault` and `fault_code` are diagnostic outputs in this prototype and do not replace a complete architectural exception/interrupt framework.
