# Cortex64/128 v0.1.1 — Implementation Status

## What this release is

v0.1.1 is the first RTL implementation increment after the portable v0.1 specification. It introduces a small, vendor-independent, multi-cycle CPU core and a smoke-test testbench. It is an **executable subset**, not yet a complete RV64I implementation or a complete SoC.

## Included RTL

- `rtl/cpu/cortex_core.sv`: single-hart core with 64-bit integer registers, fetch/execute/memory states, a 64-bit aligned request/response memory port, branch/jump operations, selected integer operations, loads and stores.
- `rtl/top/cortex_top.sv`: portable top-level wrapper around the core's memory port.
- `sim/tb/cortex_core_tb.sv`: byte-addressed, little-endian memory model and a program that checks arithmetic, branch redirects, `SD`, `LD`, and `EBREAK`.
- `tools/test.sh`: Python program-encoding checks followed by Verilator simulation or an Icarus Verilog fallback.
- `tools/lint.sh`: Verilator lint entry point.

## Supported instruction subset

The implemented subset includes:

- `LUI`, `AUIPC`, `JAL`, `JALR`;
- `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`;
- `LB`, `LH`, `LW`, `LD`, `LBU`, `LHU`, `LWU`;
- `SB`, `SH`, `SW`, `SD`;
- selected `OP-IMM`, `OP`, `OP-IMM-32`, and `OP-32` operations: integer add/subtract, bitwise logic, comparisons, and shifts as decoded in `cortex_core.sv`;
- `FENCE` / `FENCE.I` as no-ops only for the current serialized, uncached test environment;
- `EBREAK` as a test-harness stop instruction.

Unsupported encodings cause a sticky diagnostic halt with `fault_code=2`. These are implementation diagnostics, **not architecturally complete RISC-V traps**. Misaligned data access causes `fault_code=4`; instruction alignment problems cause `fault_code=3`; memory response errors cause `fault_code=1`.

## Explicitly not implemented

- full RV64I conformance coverage and required architectural trap behavior;
- M-mode CSR/trap architecture, `ECALL`, `MRET`, machine interrupts and privilege control;
- `M`, `A`, `C`, `F`, `D`, and standard `V` extensions;
- instruction/data caches, MMU, S-mode, cache coherence, DMA, full chipset peripherals;
- a physical DDR4 controller or PHY and board-level constraints;
- the 128-bit vector unit.

The memory port is an abstraction. The smoke test uses a simulation byte array; it does not validate DDR4 electrical timing or a board-specific controller.

## Protocol contract

- Byte addresses, little-endian byte lanes.
- One outstanding transaction at a time.
- `mem_req_valid && mem_req_ready` accepts a request.
- `mem_rsp_valid && mem_rsp_ready` completes it.
- All requests issued by this core are aligned to 8-byte bus words.
- Read responses return the aligned 64-bit word; the core extracts the requested byte/halfword/word/doubleword.
- `mem_req_wstrb[0]` controls the lowest-addressed byte in `mem_req_wdata`.

## Verification status

The testbench and automation are supplied in this package. Run `./tools/test.sh` using Verilator 5.x (recommended) or Icarus Verilog plus Python/pytest. The project was prepared in an environment without Verilator or Icarus Verilog, so an RTL simulation result has **not** been recorded for this package. Python checks validate the smoke-test instruction encodings and branch destinations only; they do not prove RTL correctness.

## Next milestone: v0.1.2

1. Run simulator and lint; fix all errors and meaningful warnings.
2. Add instruction-by-instruction tests against a pinned RISC-V reference model.
3. Complete the RV64I base plus required architectural exception/trap behavior.
4. Add timer/CSR/interrupt support only after the scalar core passes the ISA test suite.
5. Implement a BRAM subsystem and only then add the board-specific DDR4 adapter.
