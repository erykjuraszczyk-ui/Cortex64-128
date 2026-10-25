# Cortex64/128 v0.1 — Portable Technical Specification

## 1. Status and scope

This is a portable architecture contract for an FPGA prototype. It separates vendor-independent CPU/system RTL from board-specific clocking, I/O constraints, DDR4 controller IP and PHY. It is not a claim that a functional CPU or tested FPGA bitstream already exists.

### v0.1 objectives

1. Execute a documented RV64 instruction profile in simulation.
2. Boot a small test program from on-chip ROM/BRAM.
3. expose memory and MMIO over a simple request/response interconnect.
4. Run CPU, memory-map, timer, interrupt and UART tests.
5. Add DDR4 through a board/vendor adapter without changing CPU RTL.
6. Produce reproducible simulation, lint and synthesis reports.

Out of scope for the first functional baseline: multi-core, full Linux support, virtual-memory translation, advanced branch prediction, cache coherence, and a complete standard RISC-V Vector implementation.

## 2. Portability rules

- No vendor-specific primitive may be instantiated inside `rtl/cpu/`, `rtl/common/` or `rtl/chipset/`.
- All board-specific code must live under `fpga/boards/<board-name>/` or a vendor integration directory.
- Keep clocks/resets explicit. Do not create derived clocks in ordinary RTL; use clock-enable logic unless a board-specific clocking IP is required.
- Parameters determine reset PC, memory map bases, bus timeouts and optional features.
- Use explicit widths and signedness; avoid unsized constants in datapaths.
- No inferred latches. All sequential state uses `always_ff`; combinational logic uses `always_comb` where supported by the chosen toolchain.
- Use one canonical simulator and lint command in continuous integration.
- Document any synthesis or simulation limitation instead of silently changing behavior between targets.

## 3. ISA contract

### 3.1 Scalar base

- XLEN = 64.
- Base ISA: RV64I, little-endian memory model.
- Integer register file: x0–x31, each 64 bits. x0 reads as zero and ignores writes.
- Program counter: 64 bits; reset vector is a parameter (`RESET_PC`).
- Initial implementation is in-order and single-hart (hart ID 0).
- Instruction fetch starts with 32-bit instructions. If extension C is enabled, 16-bit instruction alignment and decompression are required; do not advertise C before tests pass.

### 3.2 Extension policy

Implement and validate extensions in this order:

1. RV64I.
2. Zicsr and the required machine-level privileged behavior.
3. Zifencei, with defined instruction-fetch synchronization behavior.
4. M (integer multiply/divide).
5. C (compressed instructions), if wanted by the chosen toolchain/profile.
6. A (atomic instructions), only after the memory system defines atomicity and ordering.
7. Standard V extension or a clearly named non-standard custom-vector extension as a separate project milestone.

A software-visible ISA string must exactly describe implemented behavior. Never claim an extension merely because some of its operations exist. Consult the official ratified specification release pinned by the project; do not build compliance around a moving draft snapshot.

### 3.3 Privilege and traps

- v0.1 starts in M-mode only.
- Implement required machine CSRs, trap entry, `mepc`, `mcause`, `mtval` where applicable, `mstatus`, `mtvec`, and `mret` according to the pinned privileged specification.
- Unsupported or illegal instructions raise an illegal-instruction exception.
- Misaligned data accesses may trap; v0.1 chooses precise address-misaligned exceptions rather than silently splitting transactions.
- Interrupt sources in the initial platform: machine timer and machine external interrupt. Machine software interrupt may be added if needed by the platform contract.

## 4. CPU microarchitecture

The implementation may start as a simple multi-cycle core or a five-stage in-order pipeline. The selected microarchitecture must be documented and kept consistent with the tests. The reference plan assumes a five-stage IF/ID/EX/MEM/WB pipeline but does not require a fixed number of FPGA clock cycles per instruction.

Required blocks:

- `cortex_core`: CPU integration and architectural state.
- `fetch_unit`: instruction request, PC update, redirect handling.
- `decoder`: opcode and control decode.
- `register_file`: 32 × 64-bit integer registers.
- `alu`: 64-bit arithmetic, logic, compare and shift operations.
- `branch_unit`: branch and jump target/condition calculation.
- `load_store_unit`: access size, sign/zero extension, byte enables, exception generation.
- `csr_file`: CSR read/write and trap state.
- `muldiv_unit`: later M-extension milestone.
- `vector_unit`: reserved for later milestone; not required by v0.1 scalar acceptance.

Pipeline hazard management must be explicit. A simple design may stall on dependencies and memory waits; forwarding and prediction are optimizations, not correctness prerequisites.

## 5. C-RAM — memory subsystem

### 5.1 Components

- Boot ROM / BRAM for the first program.
- Optional scratchpad BRAM.
- Request arbiter between CPU and optional DMA.
- Memory-map decoder.
- Generic memory request/response interface.
- DDR4 adapter translating the generic interface into the selected controller's application/user interface.
- Optional I-cache/D-cache only after the uncached path works. If caches are added, define fence, ordering, and cacheability behavior first.

### 5.2 Generic request/response protocol

v0.1 supports one outstanding transaction per port. Request fields:

- `req_valid`: requester offers a request.
- `req_ready`: target accepts a request on a rising edge when both are high.
- `req_addr[63:0]`: byte address.
- `req_write`: 1 for write, 0 for read.
- `req_wdata[63:0]`: write data.
- `req_wstrb[7:0]`: byte enables; bit 0 controls the lowest-addressed byte in the little-endian data word.

Response fields:

- `rsp_valid`: response is available.
- `rsp_ready`: requester accepts the response on a rising edge when both are high.
- `rsp_rdata[63:0]`: read data, with unused bytes zeroed by the target unless the local contract says otherwise.
- `rsp_error`: transaction failed (unmapped address, controller error, or timeout).

Handshake rules:

1. Requester holds `req_valid` and all request fields stable until a `req_valid && req_ready` edge.
2. After acceptance, requester deasserts `req_valid` for that transaction and waits for the response.
3. Target holds `rsp_valid`, `rsp_rdata`, and `rsp_error` stable until `rsp_valid && rsp_ready`.
4. Exactly one response is returned for every accepted request, including errors.
5. Request acceptance and response completion are separate events.
6. Reset cancels in-flight transactions; each bridge must document how it recovers if the downstream controller does not reset at the same time.
7. v0.1 does not support multiple outstanding transactions, IDs, out-of-order responses, or bursts on the generic side.

The DDR4 adapter may combine/split the generic transaction into controller-specific beats, but it must preserve the single-request ordering and return exactly one response.

### 5.3 DDR4 boundary

The CPU/system RTL must not generate DDR4 command/address, DQ, DQS, reset, or calibration signals directly. These belong to vendor-supported controller and PHY IP. A board adapter exposes only:

- controller clock/reset integration;
- controller initialization/calibration status;
- read/write application interface;
- errors/timeouts where exposed;
- pin constraints and timing constraints in the board project.

Before issuing a DDR transaction, the adapter waits for controller initialization/calibration. A simulation memory model mimics readiness and response latency but does not prove physical DDR4 timing correctness.

## 6. C-Chipset

Required v0.1 blocks:

- `system_interconnect`: routes one or more requesters to targets.
- `address_decoder`: one-hot target selection and unmapped-address response.
- `timer_block`: free-running counter and compare register for machine timer interrupt.
- `interrupt_controller`: aggregates timer/external interrupts into CPU input(s).
- `uart_controller`: optional but strongly recommended diagnostic console; can begin as a simulation-only UART sink.
- `gpio_controller`: optional for board bring-up.
- `reset_controller`: synchronous release per clock domain.
- `boot_controller`: status registers for boot and memory readiness.
- `dma_controller`: deferred; if added, treat it as an independent bus master requiring arbitration and memory protection policy.

Do not bundle board-specific USB/PCIe/SATA/Ethernet controllers into v0.1. They add large verification and integration costs and are not needed to prove the CPU.

## 7. Provisional memory map

All ranges are byte-addressed, little-endian, parameterized, and must be checked for overlap at elaboration/build time.

| Region | Default base | Default size | Notes |
|---|---:|---:|---|
| Boot ROM / BRAM | `0x0000_0000` | 64 KiB | Reset code / bring-up test |
| Scratchpad BRAM | `0x0001_0000` | 64 KiB | Optional, can be disabled |
| Chipset MMIO | `0x1000_0000` | 64 KiB | Shared system registers |
| Interrupt/timer MMIO | `0x1001_0000` | 64 KiB | Timer and interrupt configuration |
| UART/GPIO MMIO | `0x1002_0000` | 64 KiB | Optional peripherals |
| DDR4 RAM | `0x8000_0000` | platform-dependent | Actual size and top address from board configuration |

The map is provisional; parameter values must be centralized in a package or configuration file. The physical DDR4 capacity is not inferred from the base address.

## 8. Reset and clocking

- `RESET_PC` defaults to the boot ROM base.
- The design exposes a primary system clock and an active-low or active-high reset with one documented polarity; adapters normalize vendor reset polarity at the boundary.
- Reset assertion may be asynchronous if required, but deassertion must be synchronized independently in each clock domain.
- CPU remains in reset until its clock is stable and the reset controller releases it.
- DDR4 readiness is separate from CPU reset: firmware or the boot controller waits for calibration before placing executable data in DDR4.
- Avoid clock gating in v0.1; use clock enables.

## 9. Diagnostics and observability

At minimum expose:

- boot status;
- current PC or trace output in simulation;
- trap cause and fault address;
- accepted request and completed response counts;
- DDR4 ready/calibrated status;
- reset cause, if implemented;
- sticky error bits for unmapped access, timeout and memory-controller fault.

Diagnostic signals may be removed or reduced in production builds through parameters, but must remain accessible in simulation.

## 10. Portability and board support package

Every new board profile must provide:

1. `board_top.sv` binding portable `cortex_top` to board resources.
2. Clock/reset configuration.
3. Pin constraints and timing constraints.
4. Vendor DDR4 controller/PHY instance and the adapter mapping.
5. Memory size and bus-frequency metadata.
6. Build script and instructions.
7. A hardware smoke-test result.

No board-neutral spec can guarantee DDR4 operation without a specific FPGA, memory device/topology, pinout, clock input and vendor IP version.

## 11. Definition of done for v0.1

- ISA behavior is documented and pinned to a ratified specification release.
- CPU instruction tests pass against a reference model.
- Invalid instruction, misalignment, reset and trap tests pass.
- Memory protocol assertions pass, including wait states and errors.
- MMIO map has no overlapping decode ranges.
- ROM/BRAM boot works in simulation.
- Lint and synthesis/elaboration are clean for a selected target.
- DDR4 test passes on a selected board before the full FPGA prototype is called hardware-validated.
- Reports separate simulated, synthesized and hardware-measured results.

## 12. v0.1.1 implementation delta — important

The architecture above is the longer-term platform contract, not the list of features already implemented. The first RTL increment in v0.1.1 is intentionally smaller:

- `rtl/cpu/cortex_core.sv` implements a multi-cycle RV64 integer instruction **subset** and a simple diagnostic stop/fault model.
- The v0.1.1 core is not yet a complete RV64I-compliant processor: architectural CSRs, machine trap entry/return, interrupts, and some required instruction behaviors are not implemented.
- The 128-bit vector unit, full C-Chipset, BRAM controller, and DDR4 adapter are not implemented in this increment.
- `FENCE` and `FENCE.I` are treated as no-ops only in the current uncached serialized test environment. This must be revisited before adding caches, DMA, or multiple requesters.
- The smoke test is designed to prove basic ALU/branch/LD/SD operation when run on a simulator. It does not by itself prove ISA compliance.

See `IMPLEMENTATION_STATUS_v0.1.1.md` for the exact support list and test limitations.

## 13. v0.1.2 implementation delta — local BRAM path

The portable design now includes `rtl/memory/cortex_bram_mem.sv` and `rtl/top/cortex_bram_soc.sv`. They provide an initial single-port, 64-bit scratchpad target that shares the CPU's generic request/response contract. This is a simulation and bring-up milestone, not the complete C-RAM subsystem and not a DDR4 controller.

- The BRAM target maps a configurable `[BASE_ADDR, BASE_ADDR + WORDS*8)` range.
- Writes honor byte strobes in little-endian lanes.
- Responses remain asserted until consumed; the target supports one outstanding transaction.
- Unmapped-range and bus-word alignment errors are reported via `rsp_error`.
- A generated smoke image exercises signed/unsigned load extension and SB/SH/SW/SD.
- FPGA block-RAM inference and initialization-file behavior still require verification in the selected vendor toolchain.

See `IMPLEMENTATION_STATUS_v0.1.2.md` and `MEMORY_BRIDGE.md` for the exact implementation and protocol status.


## Optional memory timeout policy (v0.1.8)

For deployments that require bounded waits, `cortex_top_timeout` inserts `cortex_mem_timeout_adapter` between the CPU and external target. The adapter's parameter `TIMEOUT_CYCLES` bounds the request-accept handshake and the response wait. Timeout is reported to the CPU as `rsp_error=1`. A request-accept timeout does not cancel or withdraw downstream `VALID`; the original payload remains stable until the target accepts it or a coordinated reset/flush clears both ends. If a request has been accepted but its response arrives too late, the adapter quarantines the port and drains/discards that response before accepting another request. With no transaction IDs or cancellation, a target that never completes the old request requires a coordinated reset/flush before the bus can be reused. The original `cortex_top` remains available without this policy.


### v0.1.9 timeout adapter + BRAM integration

The optional `cortex_timeout_bram_soc` connects the timeout-enabled CPU wrapper to the generic BRAM target. Its simulation smoke test checks execution and load/store results across the adapter. It is intended to exercise the integrated path without a vendor DDR4 IP and does not change the ISA or the external bus contract.
