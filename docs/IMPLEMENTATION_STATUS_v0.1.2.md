# Cortex64/128 v0.1.2 — Implementation Status

## Scope of this increment

v0.1.2 adds a portable local BRAM/scratchpad target and an integrated CPU+BRAM simulation top. It keeps the original `cortex_core` unchanged, so this milestone focuses on memory integration and executable load/store coverage rather than claiming full RV64I compliance.

## New files

- `rtl/memory/cortex_bram_mem.sv` — generic 64-bit single-port memory target with byte strobes, range checks, a held response, and optional `$readmemh` initialization.
- `rtl/top/cortex_bram_soc.sv` — board-neutral top connecting the CPU to local BRAM.
- `sim/tb/cortex_bram_mem_tb.sv` — tests full-word write/read, partial-byte writes, out-of-range access, and misaligned bus requests.
- `sim/tb/cortex_bram_soc_tb.sv` — integration test running a generated program through the core and BRAM.
- `tools/gen_smoke_hex.py` / `sim/programs/smoke_test.hex` — deterministic instruction image testing LB/LH/LW/LD, unsigned loads, SB/SH/SW/SD, signed extension, zero extension, SLLI, conditional branches, and EBREAK.

## Memory contract

- Byte addresses, little-endian ordering.
- 64-bit aligned word transactions at the target boundary.
- `req_valid && req_ready` accepts a request.
- `rsp_valid && rsp_ready` consumes a response.
- Only one outstanding request/response is supported.
- `req_wstrb[n]` controls byte lane `n`, where lane 0 is the lowest-addressed byte.
- Out-of-range or unaligned bus-word accesses return `rsp_error=1`.
- The module has a generic synthesizable RTL description, but actual block-RAM inference, initialization-file support, and timing must be checked in the chosen FPGA toolchain.

## Verification status

Python program-image structural tests run in this environment and currently pass. RTL simulations are configured in `tools/test.sh` for Verilator or Icarus Verilog, but they have not been executed in this environment because no supported RTL simulator is installed. Therefore no simulation or synthesis success is claimed.

## Known limitations

- The CPU remains a subset implementation, not fully RV64I conformant.
- Architectural machine CSRs/traps, `ECALL`, `MRET`, interrupts, M/A/C/F/D/V extensions and a standard vector unit are not implemented.
- The BRAM adapter is not a DDR4 controller. Board-specific DDR4 controller/PHY integration and timing constraints remain future work.
- The current memory model and core bus are single-outstanding; no cache, burst transactions, DMA or coherency are included.
