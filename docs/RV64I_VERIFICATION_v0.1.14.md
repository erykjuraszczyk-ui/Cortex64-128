# Cortex64/128 v0.1.14 — RV64I verification baseline

## Purpose

This release adds an explicit verification inventory for the current single-hart SystemVerilog core. It does **not** certify full RV64I compliance. The current RTL is a documented implementation subset and requires instruction-level simulation before any compliance claim.

## Current decode inventory

| Group | RTL decode | Verification status in this release |
|---|---|---|
| U-type | LUI, AUIPC | Static decode inventory only |
| Integer immediate | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI | Static decode inventory only |
| Integer register | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND | Static decode inventory only |
| Word immediate | ADDIW, SLLIW, SRLIW, SRAIW | Static decode inventory only |
| Word register | ADDW, SUBW, SLLW, SRLW, SRAW | Static decode inventory only |
| Loads | LB, LH, LW, LD, LBU, LHU, LWU | Existing RTL path; directed simulation still required |
| Stores | SB, SH, SW, SD | Existing RTL path; directed simulation still required |
| Branches | BEQ, BNE, BLT, BGE, BLTU, BGEU | Existing RTL path; directed simulation still required |
| Jumps | JAL, JALR | Existing RTL path; directed simulation still required |
| Memory ordering | FENCE, FENCE.I | Serialized uncached implementation treats both as no-ops |
| Privileged/system | Selected machine CSRs, ECALL, MRET, configurable EBREAK | Selected subset only; not full privileged architecture |

The inventory is derived from the current RTL decoder. Static checks can detect accidental removal of decode branches, but cannot establish arithmetic correctness, retirement behavior, exception precision, or bus-level correctness.

## Required directed RTL verification

The next verification increment should add executable instruction programs and compare architectural state against an independent reference model:

1. Arithmetic/logical: zero operands, all-ones, signed extrema, shift amounts 0/1/31/32/63, signed and unsigned comparisons.
2. RV64 word operations: verify sign-extension of every 32-bit result to XLEN.
3. Loads/stores: each width, signed/unsigned extension, byte lanes 0–7, strobe masks, address alignment and memory round-trip.
4. Control flow: taken/not-taken branch pairs, positive/negative offsets, JAL/JALR link values and target alignment.
5. Exceptions/CSR: illegal encodings, misaligned access, access faults, ECALL, MRET, CSR read/write/set/clear and read-only CSR violations.
6. Retirement: exactly one increment per completed instruction; no increment for a synchronous exception before retirement.

## Compliance boundaries

Not implemented or not claimed by this baseline: M extension (multiply/divide), A extension (atomics), C extension, F/D floating point, V vectors, supervisor/user modes, virtual memory, interrupts, debug, caches, and a DDR4 controller/PHY. The prototype's misa and machine CSR behavior is a selected implementation and must be checked against the privileged specification before claiming architectural compliance.

## Commands

```sh
python3 -m pytest -q tests/unit
python3 sim/reference_model/rv64_smoke.py
./tools/test.sh
./tools/lint.sh
```

Only the Python tests and reference-model command can be reported as passed when those commands actually pass. Full RTL verification requires Verilator 5.x or Icarus Verilog and execution of the testbenches. A successful lint run is not a functional compliance result.
