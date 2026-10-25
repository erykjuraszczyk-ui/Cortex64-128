# v0.1.12 protocol assertions and timeout-boundary verification

`sim/checkers/cortex_mem_protocol_assertions.sv` checks ready/valid payload stability on all four channels and enforces single-outstanding upstream/target ledgers. The dedicated `cortex_mem_protocol_assertions_tb.sv` exercises a request-accept timeout followed by late acceptance and stale-response drain, then a normal response held under upstream backpressure. These are simulation-time assertions and a directed test, not a formal proof.

The adapter was corrected to retain downstream request `VALID` through request-accept timeout. Under a ready/valid contract, a producer cannot retract `VALID` merely because its local timeout expired. The CPU is told about the timeout, but the port remains quarantined until the original request is accepted and its response drained or a coordinated reset clears both ends.

The added `cortex_mem_timeout_min_tb.sv` exercises the adapter at `TIMEOUT_CYCLES=1`: request acceptance on the boundary, target response/error priority on the first response-wait cycle, response stability under upstream backpressure, and coordinated reset while a response is held. It is registered in both simulator branches of `tools/test.sh` and in Verilator lint.

This authoring environment ran the Python structural suite and software reference model only. Verilator and Icarus Verilog are not installed; `apt-get update` timed out while contacting the Debian repositories. The new RTL bench has therefore **not** been compiled or simulated locally. A green CI job running the committed workflow is still required for RTL verification.

---

# Verification Strategy

## Test layers

1. **Static/lint:** elaboration, width warnings, latch detection, unreachable branches.
2. **Unit:** ALU, register file, decoder, CSR, timer, address decoder, bus adapter.
3. **Architectural:** instruction tests compared with a reference model pinned to the same ISA profile.
4. **Protocol:** accepted requests receive exactly one response; signals remain stable under backpressure; errors propagate.
5. **Integration:** boot ROM program, UART output, timer interrupt, traps, BRAM read/write.
6. **Hardware:** clock/reset, bitstream boot, DDR4 calibration, memory pattern test, long-duration stress.

## Required edge cases

- x0 write attempts;
- maximum/minimum signed values;
- unsigned comparisons;
- shift amount boundaries;
- branches taken and not taken;
- load/store byte lanes and sign extension;
- misaligned data accesses;
- unknown MMIO addresses;
- target not ready for multiple cycles;
- response error and timeout;
- reset while idle and reset with an in-flight request;
- DDR4 not-yet-ready condition.

## Pass criteria

Each test run must produce a deterministic pass/fail exit code and preserve logs. CI must fail on test failure or prohibited lint diagnostics. Hardware reports must identify board, tool version, controller IP version, clock settings and memory part/topology when known.

## v0.1.1 supplied smoke test

`sim/tb/cortex_core_tb.sv` models a byte-addressed little-endian 4 KiB memory with one-cycle response latency and no outstanding transaction overlap. Its program checks ADDI, ADD, BNE, SD, LD, EBREAK, the x0 baseline indirectly, the expected register results, and the memory write. `tests/unit/test_test_program.py` separately validates the smoke program encodings and branch targets; these Python checks do not exercise RTL.

Run `./tools/test.sh` to run the Python checks and then the RTL simulation. If no Verilator or Icarus executable is present, the script exits with a clear missing-simulator error rather than reporting a simulation pass.

## v0.1.2 BRAM and integration tests

The v0.1.2 increment adds:

- `cortex_bram_mem_tb.sv`: full-word write/read, partial byte-mask write, out-of-range error, and misaligned bus request error.
- `cortex_bram_soc_tb.sv`: runs the program from `sim/programs/smoke_test.hex` through the CPU and BRAM target, checking signed and unsigned load results and the pass marker.
- `tools/gen_smoke_hex.py`: deterministic generator for a 512-word little-endian memory image. The file stores two 32-bit RISC-V instructions per 64-bit word, lower-address instruction in the low half.

Run these through `./tools/test.sh`. Python tests validate the image shape, selected instruction encodings, branch targets, and load/store opcode coverage. They do not substitute for RTL simulation.


## v0.1.4 directed CSR/trap path

`sim/tb/cortex_csr_trap_tb.sv` exercises this scenario in one deterministic program:

1. Write and read `mscratch` using `CSRRW`, `CSRRS`, `CSRRWI`, and `CSRRC`.
2. Execute `ECALL`; check the handler sees `mcause=11`, the faulting PC in `mepc`, and zero `mtval`.
3. Increment `mepc` in the handler and execute `MRET`, proving execution resumes after the `ECALL`.
4. Attempt to write read-only `misa`; check the illegal-instruction cause (`mcause=2`) and instruction bits in `mtval`.
5. Return again and check final state, including `mstatus`, `mepc`, `mcause`, `mtval`, and `instret`.

The test expects the prototype's `fault`/`fault_code` outputs to remain sticky diagnostics for the most recently taken trap; thus a correctly handled exception still sets `fault`. Python structural tests only check test-vector encodings and branch targets. The RTL path is verified only when the new bench actually runs and prints its `PASS` line under Verilator or Icarus Verilog.


## Directed memory-fault test (v0.1.5)

`sim/tb/cortex_mem_fault_tb.sv` injects one load response error at `0x200` and one store response error at `0x300`. It also tests misaligned `LD` at `0x101` and `SD` at `0x201`. Each path is expected to enter the machine trap handler, expose the expected `mcause`/`mepc`/`mtval`, and resume with `MRET`. The test has been added to `tools/test.sh` and `tools/lint.sh`. Python structural tests are not a substitute for RTL simulation.


The test's exception-number expectations follow the standard synchronous exception encodings in the [RISC-V Machine-Level ISA reference](https://docs.riscv.org/reference/isa/priv/machine.html): 4 (load address misaligned), 5 (load access fault), 6 (store/AMO address misaligned), and 7 (store/AMO access fault). The prototype's expectation that `mtval` captures the faulting address is an implementation contract for these tests; it is not a claim that every platform must report `mtval` identically for all exceptions.


## v0.1.6 request backpressure and response latency

`sim/tb/cortex_mem_backpressure_tb.sv` inserts multi-cycle request-ready stalls between transactions and varies the number of cycles before each response. It asserts that request VALID and all payload fields remain stable after a stall until acceptance; it also checks one `SD` and one `LD` round-trip, request count and the final success marker. This primarily covers request-side backpressure because the current core asserts response-ready while waiting for a response. The RTL testbench must pass under Verilator or Icarus before this protocol path can be called RTL-verified.


## v0.1.7 no-response and reset recovery

`sim/tb/cortex_bus_reset_recovery_tb.sv` first allows a fetch request to be accepted while intentionally suppressing its response for eight clock cycles. It verifies the CPU remains waiting, then coordinates reset across the CPU and target to abort the transaction. The same smoke program is run after reset with normal delayed responses. A transaction ledger rejects overlapping requests, unsolicited/duplicate responses, unaccounted accepts, and unfinished requests at completion; it checks that the first transaction is counted as aborted and the ten recovery-epoch requests receive ten responses.

Important distinction: the eight-cycle watchdog window belongs to this directed testbench. `cortex_core.sv` does not autonomously time out or trap on a response that never arrives. A production design must add timeout/error handling to the core or memory adapter if such failures need automatic recovery. Python tests confirm vector text and test-flow integration only; RTL behavior is verified only when the testbench passes under a supported simulator.


## v0.1.8 memory timeout adapter

`sim/tb/cortex_mem_timeout_adapter_tb.sv` exercises the dedicated `cortex_mem_timeout_adapter` used by `cortex_top_timeout`:

- request-accept timeout while the target keeps `req_ready` low; the adapter returns one upstream error but keeps the downstream `VALID` and request payload stable until handshake or coordinated reset;
- response timeout after the target accepted a request; the adapter returns one error response and blocks the next request while a late response may still arrive;
- late-response drain in quarantine, followed by a successful new transaction;
- a valid response exactly on the timeout boundary, which must win over the timeout event;
- coordinated reset of the adapter and simulated target while quarantined, with the aborted transaction counted and a subsequent request succeeding;
- target-side and upstream-side transaction ledgers, including exactly one upstream response per issued request.

These are directed RTL checks only when run by Verilator or Icarus. Python tests verify the module/test integration and selected source structure; they do not execute SystemVerilog. The no-ID protocol requires reset coordination with a target that can preserve an old response: resetting only the adapter while the old response can survive is unsafe.


## v0.1.9 timeout + BRAM end-to-end test

`sim/tb/cortex_timeout_bram_soc_tb.sv` instantiates `cortex_timeout_bram_soc`, so the smoke program traverses `cortex_core` -> `cortex_mem_timeout_adapter` -> `cortex_bram_mem`. It checks selected register values and the success marker `x31=0x5a`, validates the expected stored word, and maintains separate handshaken-request/response ledgers at the CPU and target interfaces. The test is only RTL-verified after it compiles and executes successfully under Verilator or Icarus; the Python source-structure test is not a simulation substitute.

## v0.1.10 deterministic randomized-latency stress

`sim/tb/cortex_mem_random_latency_tb.sv` runs 40 sequential transactions through `cortex_mem_timeout_adapter` with a fixed-seed LFSR varying downstream request acceptance gaps and response delays (1–6 cycles). The target delay is deliberately below `TIMEOUT_CYCLES=32`, so this no-fault scenario expects zero timeout responses. Procedural protocol monitors require request payload stability on both sides during backpressure, stable upstream response payload while held, no overlapping or unsolicited/duplicate target response, and matching accepted-request/response counters. It is deterministic pseudo-random stress, not exhaustive constrained-random or formal verification. Python structural checks do not run this bench; RTL verification requires a successful Verilator or Icarus compile/run.
