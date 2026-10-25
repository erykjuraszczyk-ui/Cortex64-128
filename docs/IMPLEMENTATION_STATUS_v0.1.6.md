# Cortex64/128 v0.1.6 — Memory protocol backpressure and latency

## Scope

v0.1.6 adds a directed RTL testbench around the existing single-outstanding request/response interface. It is a verification increment; the CPU RTL and ISA scope are not intentionally expanded in this release.

`sim/tb/cortex_mem_backpressure_tb.sv` instantiates the CPU with a deterministic target that deliberately stalls request acceptance and returns each response after a multi-cycle delay. It checks:

- a small `ADDI`/`SD`/`LD` program stores and reads back `42` at address `0x100`;
- the CPU's request `VALID`, address, direction, write data and byte strobes remain stable after a stall and until acceptance;
- the target accepts exactly 10 instruction/data requests and exactly one write request;
- at least 10 request-backpressure cycles and 20 target-wait cycles were exercised;
- the program reaches `x31=0x5a` and does not take the failure branch or raise a CPU fault.

The target allows only one outstanding transaction and holds response data/valid until a response handshake. The current CPU raises `mem_rsp_ready` in its wait states, so this test principally stresses request-side backpressure and response latency; it does not claim to exercise response-side backpressure inside the CPU.

## Checks to run

```sh
python3 -m pytest -q tests/unit
python3 sim/reference_model/rv64_smoke.py
./tools/test.sh
./tools/lint.sh
```

Python structural checks validate the directed program encodings and that the bench is included by the scripts. They do not compile or simulate SystemVerilog.

## Checks performed in the authoring environment

- `python3 -m pytest -q tests/unit`: **12 passed**. These are structural/vector checks, not RTL simulation.
- `python3 sim/reference_model/rv64_smoke.py`: **PASS**, software model ran 33 instructions and reached marker `x31=0x5a`; this does not execute the SystemVerilog core.
- `sh -n tools/test.sh tools/lint.sh`: **PASS**.
- `./tools/test.sh`: Python steps passed, then exited **127** because neither Verilator nor Icarus Verilog is installed.
- `./tools/lint.sh`: exited **127** because Verilator is not installed.
- FPGA synthesis, timing closure, formal verification and board testing: **not run**.

## Known limitations

- This is a partial RV64 subset, not a claim of full RV64I or privileged-architecture compliance.
- The memory interface supports one outstanding transaction; no ID tags, burst protocol, coherent cache traffic or out-of-order responses are implemented.
- DDR4 controller and PHY remain external and unimplemented in this repository.
