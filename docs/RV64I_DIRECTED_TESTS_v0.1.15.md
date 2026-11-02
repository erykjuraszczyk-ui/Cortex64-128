# Cortex64/128 v0.1.15 — Directed RV64I RTL execution tests

## Scope

Adds a dedicated testbench that drives the actual SystemVerilog cortex_core through its memory request/response interface and checks architectural state after a directed program. This increment focuses on integer ALU operations.

## Directed program

ADDI, ADD, SUB, XOR, OR, AND, SLT, SLTU, SLLI, SRLI and SRAI. Operands include zero, one, all-ones and the sign bit. Expected destination registers are asserted independently in the testbench.

## Assertions

- x1 through x12 are checked against fixed 64-bit expected values.
- instret must equal 12; EBREAK follows the core's existing halt convention.
- Any synchronous fault fails the test.
- A watchdog prevents a hung core from passing.

## Verification boundary

This is an RTL execution test, unlike Python source-structure checks. It is not a complete RV64I compliance suite. Word operations, all load/store widths, branches, jumps, CSR/trap precision and exception retirement semantics remain future work. Run with Verilator 5.x or Icarus Verilog using ./tools/test.sh. Python guards only check bench presence and runner wiring; they do not execute RTL.
