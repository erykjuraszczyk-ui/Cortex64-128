# Cortex64/128 v0.1.12 — Implementation status

## Scope

This release adds simulation-time protocol assertions and corrects a ready/valid protocol violation in the request-accept timeout path. No CPU datapath, ISA, BRAM organization, or DDR4 controller/PHY is added in this release.

## RTL change: request-accept timeout

Previously, when `down_req_valid` stayed high while `down_req_ready` stayed low through the timeout, the adapter transitioned out of `ST_SEND` and deasserted `down_req_valid`. That violates a conventional ready/valid producer contract: once VALID is asserted, the producer must retain VALID and the payload until a handshake or an explicitly coordinated reset/cancel event. A target could otherwise accept a retracted request later, after the adapter had already reused the port.

The adapter now uses `ST_UP_RSP_SEND` and `ST_QUARANTINE_SEND`. On request-accept timeout it produces exactly one upstream error response but preserves downstream VALID and the captured address/write/data/strobes. If the upstream consumes the timeout response first, the adapter continues holding the original request and blocks new requests. If that request is eventually accepted, its response is discarded before the adapter returns to IDLE. Reset can clear this state only when the target is reset/flushed in coordination.

## Protocol checker and regression

`sim/checkers/cortex_mem_protocol_assertions.sv` is a simulation-only module. It checks:

- stable VALID and payload for stalled upstream/downstream requests;
- stable VALID and payload for stalled upstream/downstream responses;
- no second outstanding request without a completing response;
- no unsolicited or duplicate response handshakes;
- one-outstanding request/response accounting, with reset treated as a new coordinated accounting epoch.

`sim/tb/cortex_mem_protocol_assertions_tb.sv` checks request-accept timeout, late downstream acceptance, stale-response drain, and a successful normal transfer while the upstream response is backpressured. Existing timeout tests have been updated to ensure an unaccepted request is not withdrawn after timeout.

## Checks performed

- Python structural tests: run for this release; exact count reported in the delivery summary.
- Smoke reference model: run for this release; it tests the program against the software model only.
- Shell syntax checks: run for this release.
- ZIP integrity and SHA-256: generated and checked for the delivered archive.
- Verilator/Icarus simulation: **not run locally** unless a simulator command is available and actually succeeds.
- FPGA synthesis/place-and-route and physical hardware: not performed.

The protocol checker and SystemVerilog testbenches need to be compiled and executed by Verilator or Icarus to claim RTL simulation success. Python checks only inspect source/test structure; they are not proof of RTL correctness. The design remains a portable prototype, not a complete RV64I-compliant processor, and no DDR4 PHY/controller is included.

## Next work

1. Execute the full regression in a simulator-enabled CI environment and address any compile/runtime failures.
2. Add bounded liveness checking for the case where target READY or response never arrives, with reset policy documented for platform integration.
3. Only then start board-specific controller and DDR4 timing integration.
