# Cortex64/128 v0.1.10 — Implementation status

## Delivered

- Added `sim/tb/cortex_mem_random_latency_tb.sv`, a deterministic LFSR-driven stress bench for `cortex_mem_timeout_adapter`.
- Exercises 40 sequential requests with variable downstream acceptance gaps and target response delays of 1–6 cycles, below the configured 32-cycle timeout.
- Monitors stable upstream and downstream request payloads under backpressure, stable upstream responses while held, and rejects unsolicited/duplicate target responses.
- Checks matching accepted-request/response ledgers on both sides and requires zero timeout/error responses during the no-fault stress run.
- Integrated the bench into Verilator simulation, Icarus Verilog simulation and Verilator lint scripts.
- Added Python structural tests for deterministic stimulus and test-runner integration.

## Verification checkpoint

- Python structural tests: **24 passed** (`python3 -m pytest -q tests/unit`). These tests inspect source/testbench structure and do not execute SystemVerilog.
- Software reference model: **PASS**, 33 model instructions, success marker `x31=0x5a`; this validates the smoke image/reference model, not the RTL random-latency bench.
- Shell syntax: **PASS** (`sh -n tools/test.sh`, `sh -n tools/lint.sh`).
- Full `tools/test.sh`: returned **127** after the Python/model checks because neither Verilator nor Icarus Verilog is installed.
- `tools/lint.sh`: returned **127** because Verilator is not installed.
- RTL simulation, RTL lint, synthesis, timing closure and physical FPGA validation are **not verified** in this environment.

## Scope and limitations

This version is verification-focused; it does not change the CPU datapath, ISA subset, timeout adapter RTL, or DDR4 support. The target model is deterministic pseudo-random rather than exhaustive constrained-random verification. One transaction may be outstanding at a time and there are no transaction IDs. The adapter can remain quarantined if an accepted request times out and its late response never arrives, unless a coordinated target reset/flush clears it.

## Next steps

Run `./tools/lint.sh` and `./tools/test.sh` in a Verilator-enabled CI runner, resolve any reported RTL issues, then add corner cases for minimum timeout values, response errors during backpressure, timeout-boundary acceptance, reset while a response is held, and integration-level randomized delays.
