# Cortex64/128 v0.1.11 — Implementation status

## Delivered

- Added `sim/tb/cortex_mem_timeout_min_tb.sv` with `TIMEOUT_CYCLES=1`, the minimum supported timeout setting.
- Exercises a request that is never accepted and requires a single error response.
- Exercises target acceptance on the one-cycle boundary and confirms it is not converted to a request timeout.
- Exercises a target response carrying `rsp_error=1` on the first response-wait cycle; checks boundary priority and holds both response data and error flag stable while upstream `rsp_ready=0`.
- Exercises reset while a successful upstream response is held, checking that the adapter returns to idle and clears response valid. This reset scenario is coordinated with the target in the testbench.
- Added two Python structural tests and registered the testbench with Verilator binary tests, Icarus tests, and Verilator lint.

## Verification checkpoint

- Python structural tests: **26 passed** (`python3 -m pytest -q tests/unit`).
- Software reference model: **PASS**, 33 model instructions, success marker `x31=0x5a`; this checks the smoke image/reference model, not the RTL.
- Shell syntax: **PASS** (`sh -n tools/test.sh`, `sh -n tools/lint.sh`).
- Full `tools/test.sh`: returned **127** after Python/model checks because neither Verilator nor Icarus Verilog is installed.
- `tools/lint.sh`: returned **127** because Verilator is unavailable.
- `apt-get update` timed out contacting Debian package repositories; no simulator could be installed in this environment.
- RTL simulation, RTL lint, synthesis, timing closure and physical FPGA validation are **not verified**.

## Scope and limitations

This is a verification-focused release; CPU datapath, ISA subset, adapter RTL and DDR4 support are unchanged. The minimum-timeout bench checks boundary intent but still requires execution by Verilator/Icarus to demonstrate correct SystemVerilog behavior. Reset intentionally flushes the response held upstream and must be coordinated with the downstream target if a target request may still be outstanding. The target interface has no transaction IDs or cancellation operation.

## Next steps

Run the updated GitHub Actions workflow with Verilator, resolve any lint/simulation failures, then add assertions or formal properties for timeout-counter boundaries, no unsolicited responses, exactly-one response per accepted transaction (except explicitly aborted by coordinated reset), and the quarantine transition.
