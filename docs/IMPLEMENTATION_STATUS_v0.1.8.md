# Cortex64/128 v0.1.8 — Implementation status

## Delivered

- Added `rtl/common/cortex_mem_timeout_adapter.sv` with a configurable `TIMEOUT_CYCLES` parameter.
- Both waiting for downstream request acceptance and waiting for a response are bounded.
- Timeout responses are held until the upstream requester consumes them.
- After a timed-out request that was accepted downstream, new requests are blocked until the late response is drained or a coordinated reset clears adapter and target state.
- Added `rtl/top/cortex_top_timeout.sv`, routing the core memory port through the adapter while preserving the original direct `cortex_top.sv`.
- Added a directed testbench for request backpressure timeout, accepted-request response timeout, timeout-boundary response priority, quarantine, late-response drain, coordinated reset recovery, transaction accounting and subsequent successful transactions.
- Added the new adapter test to Verilator/Icarus test execution and Verilator lint; added Python structural tests.

## Verification status

The Python unit tests and software reference model validate test vectors/structure and program image only. They do **not** compile or simulate SystemVerilog. In this environment, neither `verilator` nor `iverilog` was found, so the RTL testbench, RTL lint and synthesis cannot be claimed as passing. Run `./tools/test.sh` and `./tools/lint.sh` in an environment with Verilator 5.x installed to validate the executable RTL.

## Important protocol decisions

- `TIMEOUT_CYCLES` defaults to 64 in `cortex_top_timeout`; it is a configurable engineering default, not a guarantee of a specific DRAM/DDR4 latency.
- If the target doesn't accept a request before timeout, the adapter returns an error and does not quarantine because no target transaction was accepted.
- If the target accepts a request but doesn't return its response before timeout, the adapter returns an error and enters quarantine. It drains the late response before permitting another transaction. If no late response arrives, coordinated reset is required.
- `rst_n` must be coordinated with the downstream target/controller (or the platform must provide a documented flush/reset guarantee). The protocol has no transaction IDs or cancellation channel; resetting only the adapter while an old response can survive could allow a stale response to be misattributed.
- A real downstream `rsp_valid` at the timeout boundary has priority over the timeout event.

## Not implemented / not verified

- No DDR4 controller or PHY, target calibration, CDC bridge, cache, or multi-outstanding transaction IDs.
- No automatic target-side cancellation.
- No successful Verilator/Icarus simulation, RTL lint, FPGA synthesis, timing closure, or physical hardware validation has been demonstrated in this run.
