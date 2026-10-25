# Changelog

## v0.1.12
- Fixed request-accept timeout behavior to preserve downstream VALID and payload until handshake or coordinated reset.
- Added quarantine states to drain late responses before reusing the memory port.
- Added simulation-only protocol assertions for ready/valid stability and single-outstanding transaction accounting.
- Added a regression test for timeout, late acceptance, stale response drain and a subsequent normal transaction.
- RTL simulation, synthesis and hardware validation remain unconfirmed until run in a simulator/toolchain-enabled environment.

## v0.1.11
- Added minimum-timeout boundary testbench for TIMEOUT_CYCLES=1.
- Improved CI simulator reporting.

## v0.1.10
- Added deterministic 40-transaction latency/backpressure stress test.

## v0.1.9
- Added CPU + timeout adapter + BRAM end-to-end smoke integration.

## v0.1.8
- Added configurable request/response timeout adapter and late-response quarantine.

## v0.1.7
- Added coordinated-reset recovery test.

## v0.1.6
- Added delayed-response and backpressure stability test.

## v0.1.5
- Added memory-fault test scenarios.

## v0.1.4
- Added CSR and trap regression scaffolding.

## v0.1.1–v0.1.3
- Initial portable core, BRAM integration, and selected machine-mode CSR/trap support.
