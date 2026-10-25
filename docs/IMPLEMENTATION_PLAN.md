# Cortex64/128 v0.1 — Implementation Plan

## Phase 0 — Contract and environment

Tasks:
- Pin official RISC-V unprivileged/privileged specification releases.
- Confirm SystemVerilog subset and reset protocol.
- Freeze generic memory handshake and default memory map.
- Add formatting/lint/build commands to CI.

Acceptance:
- Documentation reviewed.
- Empty top elaborates in the reference simulator.
- No vendor dependencies in portable directories.

## Phase 1 — RV64I scalar core in simulation

Tasks:
- Implement PC/fetch, decoder, register file, ALU, branch/jump logic and load/store.
- Start with instruction ROM and simple deterministic memory model.
- Implement a simple multi-cycle controller or five-stage pipeline and document the choice.
- Add test/reference-model comparison and trace output.

Acceptance:
- All selected RV64I instruction tests pass.
- x0 invariant holds.
- Branch, jump, load/store and exception tests pass.
- No unexpected X/Z values after reset in defined state.

## Phase 2 — Machine-mode system behavior

Tasks:
- Implement CSR subset required by the pinned privileged spec.
- Implement trap entry/return and machine timer/external interrupt.
- Add boot ROM and UART diagnostic path.

Acceptance:
- Reset PC is correct.
- Illegal instruction and misaligned access generate defined traps.
- Timer interrupt can be raised, handled and returned from.

## Phase 3 — C-Chipset and common interconnect

Tasks:
- Implement address decoder and request/response routing.
- Implement timer, interrupt registers, boot status, optional UART/GPIO.
- Add bounds/overlap checks for memory map.
- Add protocol assertions and randomized wait-state tests.

Acceptance:
- Each mapped device responds to the correct address range.
- Unmapped accesses return an error.
- Exactly one response follows each accepted request.
- Wait states do not lose, duplicate or corrupt transactions.

## Phase 4 — C-RAM and generic DDR bridge

Tasks:
- Bring up BRAM first using the same generic memory interface.
- Implement adapter to selected vendor DDR4 application interface.
- Wait for calibration/initialization before allowing DDR use.
- Add test patterns, address tests and long-duration randomized tests.

Acceptance:
- BRAM tests pass on all runs.
- DDR4 calibration completes on selected hardware.
- CPU writes and reads back memory patterns across the configured range.
- All failures are reported; no unsupported timing/throughput claims.

## Phase 5 — FPGA integration

Tasks:
- Create board-specific wrapper, pin and timing constraints.
- Synthesize and run implementation/place-and-route.
- Inspect timing, utilization, clock constraints and CDC reports.
- Use an LED/UART or another low-risk observable health check.

Acceptance:
- Bitstream builds reproducibly for the selected board.
- Timing constraints are met or documented as failing.
- Boot test runs on hardware.
- Memory tests pass with actual DDR4.

## Phase 6 — Optional extensions

Implement one feature at a time, each behind an explicit parameter/profile:
- M extension;
- C extension;
- A extension after atomicity/order contract;
- F/D floating point;
- standard V extension or a clearly non-standard custom vector unit;
- caches, MMU/S-mode, DMA and then multiple cores.

Do not start multi-core or cache coherence until single-core ISA and external memory tests are stable.

## Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| DDR4 controller/PHY differs by FPGA family | High | Keep vendor IP in board adapter; begin with BRAM |
| ISA extension only partially implemented | High | Maintain explicit ISA profile and compliance tests |
| Bus handshake deadlock or duplicate response | High | Assertions and randomized backpressure tests |
| CDC/reset bugs | High | Reset synchronization per domain and CDC analysis |
| Scope expansion | Medium | Treat caches, vectors, DMA and multi-core as separate milestones |
| No physical board selected | Expected limitation | Keep portable simulation active; defer pin/DDR details |

## v0.1.1 implementation increment

The initial multi-cycle RTL subset and smoke test are now present in the repository. The first task for a developer environment is to run `./tools/test.sh` and `./tools/lint.sh`; do not mark RTL validated until these have actually run successfully. The next increment should fix findings and grow tests from the supported subset toward complete RV64I and architectural machine-mode trap behavior. DDR4 integration remains blocked on selecting hardware and its controller IP, while the CPU itself remains board-neutral.

## v0.1.2 implementation increment — local memory integration

Added a generic BRAM/scratchpad target and a board-neutral `cortex_bram_soc` wrapper. The generated program tests signed and unsigned loads plus byte, halfword, word and doubleword stores. Separate benches test memory protocol behavior and CPU-to-memory integration.

Acceptance for this increment:
- Python image/branch checks pass.
- `tools/test.sh` completes all three RTL benches in a configured simulator environment.
- `tools/lint.sh` completes without fatal diagnostics.
- A target FPGA flow must confirm block-RAM inference and initialization behavior.

Current authoring environment has no Verilator or Icarus Verilog, so RTL simulation is configured but not yet confirmed. Do not mark the increment hardware-verified until CI or a local simulator completes the test scripts.

## Current verification checkpoint — v0.1.6

The portable core currently has directed benches for basic execution, CSR/traps, data-memory faults, BRAM/SoC integration, and delayed memory responses with request backpressure. In the authoring environment, Python structural checks pass, but no RTL simulator is installed, so compile/simulation/lint results remain unconfirmed. Before widening the feature set, run all benches in CI with Verilator, review warnings and protocol assertion failures, and only then begin a vendor-specific FPGA/DDR4 integration phase.

## v0.1.9 integration checkpoint

Run the `cortex_timeout_bram_soc_tb` through `tools/test.sh` in a simulator-enabled environment. Confirm that CPU-side and target-side request counts match response counts, the smoke program reaches `x31=0x5a`, and no timeout error is raised with the default BRAM target. Python structural checks alone are insufficient. After this is confirmed, add randomized backpressure and assertion-based protocol checks before moving toward a board-specific memory interface.
