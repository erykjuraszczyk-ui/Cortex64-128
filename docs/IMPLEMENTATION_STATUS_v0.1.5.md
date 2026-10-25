# Cortex64/128 v0.1.5 — Implementation status

## Scope of this increment

v0.1.5 adds a directed SystemVerilog testbench for the CPU's existing load/store exception paths. It is a verification increment, not a claim of broader ISA compliance and not a DDR4 integration increment.

`sim/tb/cortex_mem_fault_tb.sv` checks four scenarios with a deterministic one-outstanding memory model:

| Scenario | Faulting instruction PC | Expected `mcause` | Expected `mtval` |
|---|---:|---:|---:|
| Misaligned `LD` from `0x101` | `0x004` | 4 — load address misaligned | `0x101` |
| `LD` at `0x200` receives `rsp_error` | `0x018` | 5 — load access fault | `0x200` |
| Misaligned `SD` to `0x201` | `0x02c` | 6 — store/AMO address misaligned | `0x201` |
| `SD` at `0x300` receives `rsp_error` | `0x040` | 7 — store/AMO access fault | `0x300` |

The handler snapshots `mcause`, `mepc`, and `mtval`, increments `mepc`, and uses `MRET` to resume execution. The end-of-test checks all four snapshots, verifies exactly one injected read bus error and one injected write bus error, and checks the success marker `x31=0x5a`.

The test is wired into `tools/test.sh` and `tools/lint.sh` for Verilator and into the simulation branch of `tools/test.sh` for Icarus Verilog.

## Checks performed in this workspace

- `python3 -m pytest -q tests/unit`: **9 passed**. The tests validate generated smoke-image structure, instruction encodings, and source-level expectations; they do not simulate the RTL.
- `python3 sim/reference_model/rv64_smoke.py`: **PASS**, 33 instructions in the software model and success marker `x31=0x5a`. This validates the test image/model only, not the SystemVerilog core.
- `./tools/test.sh`: Python checks passed, then exited **127** because neither Verilator nor Icarus Verilog is installed.
- `./tools/lint.sh`: cannot run because Verilator is not installed.
- `sh -n tools/test.sh tools/lint.sh`: **PASS**.
- Attempt to refresh package lists: timed out; no RTL simulator was installed.
- FPGA synthesis, timing closure, and physical-board validation: **not run**.

Run from the project root:

```sh
python3 -m pytest -q tests/unit
python3 sim/reference_model/rv64_smoke.py
./tools/test.sh
./tools/lint.sh
```

`tools/test.sh` intentionally exits with an error when neither Verilator nor Icarus Verilog is available; Python success does not imply RTL success.

## Limitations

- This is still a partial RV64 execution subset, not a compliant implementation of all RV64I and privileged architecture requirements.
- Exception behavior and CSR implementation require review against the chosen RISC-V ISA/privileged specification versions and successful directed RTL simulation.
- The BRAM/scratchpad remains a local-memory target, not a DDR4 controller or PHY.
- No formal verification, FPGA synthesis, timing closure, or board validation is claimed by this increment.

## Next step

Run all directed benches under Verilator, resolve any simulation findings, and add assertions/coverage for backpressure and response timing. Only after that should the project select a target FPGA and begin board-specific clock/reset, constraints, BRAM inference, and DDR4-controller integration.
