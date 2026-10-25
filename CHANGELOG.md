# Changelog

## 0.1.12 — Ready/valid protocol assertions and timeout correction

- Added `sim/checkers/cortex_mem_protocol_assertions.sv`, a simulation-only monitor for request/response VALID stability and payload stability under backpressure on all four interface channels.
- Added transaction-accounting checks for unsolicited/duplicate responses and more than one outstanding request on either side.
- Added `sim/tb/cortex_mem_protocol_assertions_tb.sv`, testing request-accept timeout, retained downstream request VALID, delayed target acceptance, stale response drain, and a normal transaction under upstream response backpressure.
- Corrected `cortex_mem_timeout_adapter`: request-accept timeout returns an upstream error without withdrawing downstream VALID/payload before READY. The old request remains quarantined until target acceptance + stale response drain or coordinated reset.
- Updated the existing timeout and minimum-timeout benches to assert the new ready/valid behavior and adjusted transaction ledgers.
- Integrated the assertion bench into Verilator, Icarus Verilog, and Verilator lint runners; added Python structural checks.
- Python structural tests do not execute RTL; local simulation/lint and FPGA synthesis remain unverified unless supported tools actually run.

## 0.1.11 — Minimum-timeout boundary regression

- Added `sim/tb/cortex_mem_timeout_min_tb.sv` with `TIMEOUT_CYCLES=1`, the minimum legal adapter setting.
- Verifies prompt request-accept timeout, acceptance priority at the one-cycle boundary, and target response/error priority on the response-wait boundary.
- Checks that an error response's data and error flag remain stable while the requester applies backpressure.
- Checks coordinated reset clears a response held upstream and returns the adapter to idle.
- Wired the new testbench into Verilator simulation, Icarus Verilog simulation, and Verilator lint.
- Added Python structural checks; they verify testbench coverage and integration but do not execute SystemVerilog.
- Local RTL simulation and lint remain unverified: Verilator/Icarus are unavailable and the Debian package-index refresh timed out.

## 0.1.10 — Deterministic randomized-latency stress verification

- Added `sim/tb/cortex_mem_random_latency_tb.sv`, a repeatable pseudo-random target that varies downstream request stalls and response delays for 40 sequential transactions.
- Added protocol monitors for stable upstream/downstream request payload under backpressure and stable upstream response payload while the requester is stalled.
- Added target and requester ledgers to detect overlapping requests, unsolicited/duplicate responses, lost completions, and unexpected timeout errors.
- Integrated the new bench into Verilator binary simulation, Icarus Verilog simulation, and Verilator lint runners.
- Added Python structural checks for deterministic seed, stress count, protocol checks, and runner wiring. These checks do not simulate RTL.
- Local RTL simulation/lint remains unverified unless a supported simulator actually runs the new bench and full suite.

## 0.1.9 — Timeout adapter + BRAM end-to-end integration

- Added `rtl/top/cortex_timeout_bram_soc.sv`, a portable integration wrapper connecting the CPU, timeout adapter and generic BRAM target.
- Added `sim/tb/cortex_timeout_bram_soc_tb.sv`, which runs the full smoke program through the timeout adapter and BRAM rather than testing the adapter alone.
- Added checks for arithmetic/load-store results, final program marker, memory writeback, and one-to-one CPU/target request-response transaction accounting.
- Added the integrated bench to both Verilator and Icarus simulation paths and lint checks; added Python structural checks for wrapper and runner integration.
- Python structural tests pass (21/21), but the integrated RTL bench has not been simulated in the authoring environment because neither Verilator nor Icarus Verilog is installed; Python checks do not verify RTL behavior.

## 0.1.8 — Memory timeout adapter and late-response quarantine

- Added synthesizable `cortex_mem_timeout_adapter.sv` with bounded downstream request-acceptance and response-wait phases.
- Timeout returns exactly one upstream error response; an accepted transaction that times out enters quarantine until its late response is drained or a coordinated reset occurs.
- Response handshake wins over timeout on the boundary cycle; request payload is registered and held stable under downstream backpressure.
- Added `cortex_top_timeout.sv`, a CPU wrapper that actually places the timeout adapter on the external memory path, with configurable `TIMEOUT_CYCLES` (default 64).
- Added `cortex_mem_timeout_adapter_tb.sv` covering request-accept timeout, response timeout, late response drain, response stability and successful subsequent transaction.
- Integrated the module and directed testbench into Verilator/Icarus test flows and Verilator lint; added Python structural checks and interface documentation.
- RTL simulation/lint and FPGA synthesis must be assessed independently; structural Python tests do not simulate the RTL.

## 0.1.7 — No-response, reset-abort and transaction accounting

- Added `sim/tb/cortex_bus_reset_recovery_tb.sv`, which accepts a request but suppresses its response for a bounded testbench watchdog interval.
- Verifies coordinated reset clears a stuck requester/target transaction and permits the program to restart and complete.
- Added a transaction ledger for accepted requests, completed responses and reset-aborted transactions; detects overlapping requests, unsolicited/duplicate responses and ledger mismatches.
- Verifies a post-reset load/store program reaches the success marker and that exactly one response completes each accepted request in the recovery epoch.
- Integrated the new bench into Verilator/Icarus test flows and Verilator lint; added Python structural checks. These checks do not simulate the RTL.
- Explicitly documents that the CPU has no autonomous response timeout: the watchdog interval and recovery are directed testbench behavior, not a newly implemented CPU feature.

## 0.1.6 — Memory protocol backpressure and response latency

- Added `sim/tb/cortex_mem_backpressure_tb.sv` with deliberate request stalls and multi-cycle response latency.
- Added checks for stable request payload while `VALID` is stalled, correct store/load round-trip, request counts, and PASS/FAIL program marker.
- Integrated the directed bench into Verilator/Icarus simulation and Verilator lint flows.
- Added Python structural checks for the test program and runner integration; these do not replace RTL simulation.
- Documented verification scope and protocol limitations in `docs/IMPLEMENTATION_STATUS_v0.1.6.md`.

## 0.1.5 — Memory access fault verification

- Added `sim/tb/cortex_mem_fault_tb.sv` to exercise misaligned `LD`/`SD` exceptions and injected load/store `rsp_error` responses.
- Added directed checks for `mcause`, `mepc`, `mtval`, handler return/resumption, and exactly one injected load and store bus error.
- Included the new bench in Verilator/Icarus test flows and Verilator lint.
- Added Python structural checks for instruction encodings and expected exception metadata. These checks do not simulate RTL.
- Documented outstanding verification and hardware limitations in `docs/IMPLEMENTATION_STATUS_v0.1.5.md`.

## 0.1.4 — Directed CSR and trap verification

- Added `sim/tb/cortex_csr_trap_tb.sv`: selected CSR read/write operations, `ECALL` trap entry, `mepc` update, `MRET` return, and a read-only `misa` write that must raise an illegal-instruction exception.
- Added checks for `mcause`, `mtval`, `mstatus`, final resume PC, retired-instruction count, and sticky diagnostic outputs.
- Integrated the directed bench into `tools/test.sh` and `tools/lint.sh` for Verilator and Icarus Verilog flows.
- Added Python structural checks for the directed test program encodings. These do not replace RTL simulation.
- RTL simulation/lint and FPGA synthesis remain unverified if no simulator/toolchain is available in the environment; see `docs/IMPLEMENTATION_STATUS_v0.1.4.md`.

## 0.1.3 — Selected machine CSRs and synchronous traps

- Added selected machine-mode CSR state/read/write paths and Zicsr operations.
- Added synchronous trap entry state updates, `ECALL`, and `MRET` handling.
- Added `HALT_ON_EBREAK` configuration for smoke-test behavior.
- Added `docs/IMPLEMENTATION_STATUS_v0.1.3.md` with verified checks and outstanding validation.
- RTL simulation and FPGA synthesis remain unverified in the current environment.

## 0.1.2 — Portable BRAM integration

- Added a generic single-port BRAM/scratchpad memory target.
- Added a board-neutral CPU+BRAM SoC top.
- Added memory-protocol tests for full-word access, byte strobes, range errors and alignment errors.
- Added a generated test program covering signed/unsigned loads and SB/SH/SW/SD.
- Expanded test and lint scripts to include the new modules and benches.
- Documented the distinction between Python structural tests and actual RTL simulation.

## 0.1.1 — First executable RTL subset

- Added a portable multi-cycle CPU implementation for a documented RV64I subset.
- Added a 64-bit aligned, little-endian, single-outstanding memory request/response interface.
- Added a smoke-test program covering arithmetic, branch redirects, SD/LD and EBREAK.
- Added simulation memory model and Python encoding checks.
