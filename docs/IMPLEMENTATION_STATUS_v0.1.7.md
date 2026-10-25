# Cortex64/128 v0.1.7 — Implementation and verification status

## Scope of this increment

v0.1.7 adds directed protocol testing; it does not change the CPU RTL or add a CPU-level timeout feature. The key artifact is `sim/tb/cortex_bus_reset_recovery_tb.sv`.

The testbench does the following:

1. Accepts the first instruction-fetch request while a target-side fault injection suppresses its response.
2. Waits through an eight-cycle testbench watchdog window and checks the core has not falsely halted or received a response.
3. Asserts reset to the requester and target together, accounting for the in-flight request as aborted.
4. Restarts the program with normal multi-cycle target responses.
5. Checks the program writes and reads value 42, reaches `x31=0x5a`, reports no CPU fault, and leaves no transaction pending.
6. Maintains a transaction ledger: post-reset accepts must equal completed responses, no response may be unsolicited/duplicated, and total accepts must equal completed responses plus reset-aborted requests.

## Checks performed in the authoring environment

- `python3 -m pytest -q tests/unit`: **15 passed**. These validate vectors and runner integration, not RTL execution.
- `python3 sim/reference_model/rv64_smoke.py`: **PASS**, 33 software-model instructions and success marker `x31=0x5a`; it does not execute `cortex_core.sv`.
- `sh -n tools/test.sh tools/lint.sh`: **PASS**.
- `./tools/test.sh`: Python checks and reference model passed, then exited **127** because neither Verilator nor Icarus Verilog is installed.
- `./tools/lint.sh`: exited **127** because Verilator is not installed.
- RTL bench compilation/simulation, FPGA synthesis, timing closure, formal verification, and board testing: **not performed**.

## Important limitations

- The test demonstrates a testbench-injected no-response interval and coordinated reset recovery, not autonomous CPU timeout recovery. The core currently waits indefinitely in a response-wait state if a target never responds and reset is not asserted.
- Reset recovery is tested with requester and target reset together. Resetting only the core while a target continues an old response is not proven safe by this test.
- The CPU remains a documented RV64 subset, not a fully compliant RV64I implementation.
- DDR4 controller/PHY, vendor constraints and physical board integration remain outside this release.

## Run commands

```sh
python3 -m pytest -q tests/unit
python3 sim/reference_model/rv64_smoke.py
./tools/test.sh
./tools/lint.sh
```
