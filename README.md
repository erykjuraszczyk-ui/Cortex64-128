# Cortex64/128 — v0.1.12

Portable, board-neutral SystemVerilog prototype for an FPGA-targeted, single-hart RV64 subset.

## Current release

v0.1.12 corrects request-accept timeout handling in the memory adapter and adds a simulation-only ready/valid protocol checker. The adapter now keeps downstream `VALID` and the captured payload stable until `READY` handshake or a coordinated reset. After reporting a timeout to the CPU, it quarantines the old transaction and drains its stale response before allowing port reuse.

## Project scope

- Multi-cycle RV64 subset core, machine mode only.
- Selected machine CSRs and synchronous trap paths.
- Generic BRAM/scratchpad target and SoC wrappers.
- Single-outstanding request/response memory interface.
- Configurable memory timeout adapter.
- Directed SystemVerilog testbenches and Python structural checks.
- Board-neutral RTL; board-specific constraints and DDR4 controller/PHY are not included.

## v0.1.12 key files in this repository

- `rtl/common/cortex_mem_timeout_adapter.sv` — timeout adapter and late-response quarantine.
- `sim/checkers/cortex_mem_protocol_assertions.sv` — simulation-only protocol assertions.
- `sim/tb/cortex_mem_protocol_assertions_tb.sv` — timeout, backpressure, late acceptance and stale-response regression.
- `docs/IMPLEMENTATION_STATUS_v0.1.12.md` — implementation status and verification limitations.
- `CHANGELOG.md` — release history summary.

## Verification

Requirements: Python 3.10+, pytest, and Verilator 5.x (recommended) or Icarus Verilog.

```sh
python3 -m pip install pytest
python3 -m pytest -q tests/unit
python3 sim/reference_model/rv64_smoke.py
./tools/test.sh
./tools/lint.sh
```

Python tests and the software reference model do not simulate SystemVerilog. RTL simulation is only considered passed when a supported simulator actually compiles and runs the testbenches. FPGA synthesis and hardware validation are separate steps.

## Important limitations

This is a research prototype, not a fully compliant RV64I implementation. Interrupts, supervisor/user modes, virtual memory, atomics, compressed instructions, floating point, vector instructions, debug, caches, and a DDR4 controller/PHY are not implemented. A timed-out accepted transaction may require a coordinated reset/flush of both adapter and downstream target if the late response never arrives. The bus has no transaction IDs or explicit cancellation.
