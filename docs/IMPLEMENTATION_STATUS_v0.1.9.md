# Cortex64/128 v0.1.9 — Implementation status

## Delivered

- Added `rtl/top/cortex_timeout_bram_soc.sv` connecting the CPU, `cortex_mem_timeout_adapter`, and generic `cortex_bram_mem`.
- Added `sim/tb/cortex_timeout_bram_soc_tb.sv` to execute the existing smoke program through the timeout-adapter path.
- Added checks for selected registers (`x1`, `x2`, `x3`, `x7`, `x31`), BRAM word 32 writeback, successful halt without fault, and matching CPU-side and target-side request/response handshakes.
- Integrated the new test into Verilator and Icarus branches of `tools/test.sh`, and added the integration top and testbench to `tools/lint.sh`.
- Added Python structural tests for the wrapper, testbench expectations and runner integration.

## Verification checkpoint

- Python structural tests: **21 passed** (`python3 -m pytest -q tests/unit`).
- Software reference model: **PASS**, 33 executed model instructions and success marker `x31=0x5a`; this checks the program/model, not RTL.
- Shell syntax: **PASS** (`sh -n tools/test.sh` and `sh -n tools/lint.sh`).
- Full `tools/test.sh`: stopped with exit code 127 after Python/model checks because neither Verilator nor Icarus Verilog is installed.
- `tools/lint.sh`: stopped with exit code 127 because Verilator is not installed.
- RTL simulation: not claimed unless a supported simulator actually compiles and runs `cortex_timeout_bram_soc_tb` and the other benches.
- Lint, synthesis, timing closure and physical FPGA validation are separate and are not implied by a passing Python test.

## Integration contract

The wrapper defaults to `TIMEOUT_CYCLES=64`, `MEM_BASE_ADDR=0`, `MEM_WORDS=512`, and optional `INIT_FILE`. The top is a simulation and portable scratchpad integration aid. It is not a DDR4 controller or PHY, and the memory adapter reset must remain coordinated with the target reset if an accepted request can survive reset.

## Limitations / next work

- No DDR4 controller/PHY or vendor board constraints.
- No multi-outstanding transactions or transaction IDs.
- No evidence of successful RTL simulation until the test runner is executed in a Verilator or Icarus-enabled environment.
- Next: run the complete RTL suite in CI, review simulator warnings, then add assertions/randomized wait-state tests before board-specific integration.
