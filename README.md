# Cortex64/128 v0.1.12 — Portable FPGA prototype

A board-neutral, single-hart SystemVerilog prototype targeting a documented subset of RV64. v0.1.12 adds simulation-time protocol assertions and fixes request-accept timeout behavior so downstream `VALID` and payload remain stable until `READY` or a coordinated reset. This builds on the minimum-timeout regression, deterministic latency/backpressure test, and CPU + timeout adapter + BRAM integration. This remains a prototype, not a complete RV64I implementation.

## Scope

- CPU: multi-cycle execution, one outstanding memory request, documented RV64 instruction subset.
- Privilege: machine mode only; selected `mstatus`, `misa`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mcycle` and `instret` CSRs.
- System operations: selected CSR operations, `ECALL`, `MRET`, illegal-instruction and memory-fault paths. `EBREAK` behavior is controlled by `HALT_ON_EBREAK`.
- Memory: generic local BRAM/scratchpad target. It is **not** a DDR4 controller or PHY.
- Platform: no FPGA vendor dependency in portable RTL; real board integration requires target-specific constraints and a memory controller.

## Requirements and commands

Requires Python 3.10+ and `pytest` for structural tests, plus Verilator 5.x (recommended) or Icarus Verilog for RTL simulation.

```sh
python3 -m pip install pytest
python3 -m pytest -q tests/unit
python3 sim/reference_model/rv64_smoke.py
./tools/test.sh
./tools/lint.sh
```

Python tests and the software model do not simulate the SystemVerilog. The test script exits with an error if neither supported RTL simulator is available; no RTL pass should be claimed unless the local test run reports it.

## Repository map

- `rtl/cpu/cortex_core.sv` — CPU core and selected CSR/trap logic.
- `rtl/memory/cortex_bram_mem.sv` — generic local memory target.
- `rtl/common/cortex_mem_timeout_adapter.sv` — bounded request/response wait, timeout error response, late-response quarantine.
- `rtl/top/cortex_top_timeout.sv` — CPU plus timeout adapter wrapper exposing the downstream memory pins.
- `rtl/top/cortex_timeout_bram_soc.sv` — integrated CPU + timeout adapter + generic BRAM smoke-test SoC.
- `rtl/top/cortex_bram_soc.sv` — CPU plus BRAM integration.
- `rtl/top/cortex_top.sv` — board-neutral wrapper.
- `sim/tb/` — core, CSR/trap, memory-fault, BRAM, SoC, backpressure, reset-recovery, directed timeout, minimum-timeout boundary, deterministic randomized-latency and timeout+BRAM integration testbenches.
- `sim/programs/` — smoke test image.
- `sim/reference_model/` — software reference model, not an RTL simulator.
- `tests/unit/` — Python structural tests.
- `docs/` — spec, interface contract and version status reports.
- `tools/` — test, lint and image-generation scripts.

## v0.1.8 memory timeout contract

`cortex_mem_timeout_adapter` applies `TIMEOUT_CYCLES` to both downstream request acceptance and downstream response wait. It returns one error response (`rsp_error=1`, data zero) to the CPU when either phase expires. A request-accept timeout does **not** withdraw downstream `VALID`: the adapter keeps the original request and payload stable until the target accepts it or a coordinated reset clears both adapter and target. If the target accepts that timed-out request later, the adapter drains/discards its stale response before reopening the port. If an accepted request times out waiting for a response, the adapter similarly blocks new requests and drains a late response. A response/acceptance handshake on the timeout boundary takes priority over timeout.

The bus has no transaction IDs or explicit cancellation, so an accepted request's late response cannot safely be distinguished from a new response without waiting for the late response or coordinating a reset with the target/controller. If that response never arrives, the adapter remains quarantined until reset. **The adapter reset must be coordinated with the downstream target** (or a platform-level flush guarantee) if a timed-out transaction may survive reset. Default `TIMEOUT_CYCLES=64` is a configuration choice, not a measured DDR4 latency guarantee. `cortex_top_timeout.sv` is the wrapper that actually places this adapter between the CPU and the external memory pins; the original `cortex_top.sv` remains the direct, no-timeout top.

## v0.1.7 coordinated reset recovery

`sim/tb/cortex_bus_reset_recovery_tb.sv` deliberately accepts an initial fetch request and suppresses its response. The test waits through a bounded watchdog interval, asserts reset on the core and target together to abort the in-flight transaction, then runs a memory load/store smoke program normally. A transaction ledger checks that the first request is counted as aborted and every post-reset accepted request receives exactly one response, with no duplicate or unsolicited response. This complements, but does not replace, the v0.1.8 adapter timeout.

## Limitations

This is a research prototype, not a fully compliant RV64I implementation. It does not implement interrupts, supervisor/user modes, virtual memory, atomics, compressed instructions, floating point, vector instructions, debug, caches, or a DDR4 controller/PHY. RTL simulation, lint, synthesis and hardware validation must be evaluated independently; no such result is implied by Python test success.

## v0.1.9 timeout + BRAM end-to-end integration

`cortex_timeout_bram_soc.sv` connects `cortex_top_timeout` to `cortex_bram_mem` so the existing smoke program can be run through the same timeout adapter that is exposed for external memory integration. `cortex_timeout_bram_soc_tb.sv` checks the program success marker, selected architectural register values, a stored memory word, and separate CPU-side and target-side request/response ledgers. The intended invariant is one response handshake for every accepted request in this smoke scenario. This is a directed integration test; only an actual Verilator or Icarus run can establish RTL simulation success.




## v0.1.12 protocol assertion checks and ready/valid timeout fix

`sim/checkers/cortex_mem_protocol_assertions.sv` is a simulation-only checker for upstream/downstream request and response payload stability during backpressure, plus single-outstanding request/response ledgers. `sim/tb/cortex_mem_protocol_assertions_tb.sv` runs a pre-accept timeout, retains the downstream request until late acceptance, drains its stale response, then completes a normal transaction while upstream is stalled. A review of the standard ready/valid contract showed that dropping downstream `VALID` after a pre-accept timeout is unsafe: the target may later accept a request that the adapter believes was cancelled. v0.1.12 fixes this by holding the request until handshake or coordinated reset. The checker is simulation-time assertion logic, not a formal proof. Python tests inspect testbench structure only; run `./tools/test.sh` with a supported simulator to verify RTL behavior.

## v0.1.11 minimum-timeout boundary regression

`cortex_mem_timeout_min_tb.sv` instantiates the adapter with `TIMEOUT_CYCLES=1`, the minimum supported configuration. It checks that a request-accept handshake on the boundary takes priority over the request timer, a target response (including `rsp_error=1`) on the first response-wait cycle takes priority over timeout, and the returned response remains stable while the requester stalls. It also asserts reset while a successful response is being held and verifies that reset returns the adapter to idle. This coordinated reset intentionally drops the held upstream response; the test does not imply that an already-reset requester can recover a response from before reset. Python checks only inspect testbench structure; run `./tools/test.sh` with Verilator or Icarus to execute RTL.

## v0.1.10 deterministic latency stress

`cortex_mem_random_latency_tb.sv` uses a fixed-seed LFSR to vary request acceptance gaps and downstream response latency across 40 single-outstanding transactions. It checks upstream/downstream request stability under backpressure, response stability while the requester stalls, no overlapping target transactions, and matching upstream/target request-response ledgers with no timeout errors. This is a deterministic stress test: it is repeatable, but it is not exhaustive constrained-random verification. Python checks only validate the testbench structure; the bench must be compiled and executed by Verilator or Icarus to claim RTL simulation success.


## v0.1.14 RV64I verification baseline

See [RV64I verification inventory](docs/RV64I_VERIFICATION_v0.1.14.md) for the current decoder inventory, verification boundaries and required directed RTL tests. Static Python checks are structural guards only; they do not prove instruction execution or full RV64I compliance.
