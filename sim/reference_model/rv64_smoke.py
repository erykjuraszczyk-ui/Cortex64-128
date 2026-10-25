#!/usr/bin/env python3
"""Small software reference interpreter for the v0.1.2 smoke image only.

This verifies the generated test program's expected architectural outcomes. It is
not a complete RISC-V emulator and does not simulate or prove the SystemVerilog RTL.
"""
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMAGE = ROOT / "sim" / "programs" / "smoke_test.hex"
MEM_BYTES = 4096
MASK64 = (1 << 64) - 1


def sext(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (value & sign)


def load_image() -> bytearray:
    qwords = [int(line.strip(), 16) for line in IMAGE.read_text(encoding="ascii").splitlines() if line.strip()]
    memory = bytearray()
    for qword in qwords:
        memory.extend(qword.to_bytes(8, "little"))
    if len(memory) != MEM_BYTES:
        raise AssertionError(f"image memory size {len(memory)} != {MEM_BYTES}")
    return memory


def run_program() -> tuple[list[int], bytearray, int, int]:
    regs = [0] * 32
    memory = load_image()
    pc = 0
    retired = 0

    for _ in range(1000):
        if pc < 0 or pc + 4 > len(memory) or (pc & 3):
            raise AssertionError(f"PC out of range or misaligned: {pc:#x}")
        insn = int.from_bytes(memory[pc : pc + 4], "little")
        opcode = insn & 0x7F
        rd = (insn >> 7) & 0x1F
        funct3 = (insn >> 12) & 0x7
        rs1 = (insn >> 15) & 0x1F
        rs2 = (insn >> 20) & 0x1F
        funct7 = (insn >> 25) & 0x7F
        imm_i = sext((insn >> 20) & 0xFFF, 12)
        next_pc = pc + 4
        halted = False
        result = None

        a = regs[rs1]
        b = regs[rs2]
        if opcode == 0x13:  # OP-IMM instructions used by this program
            if funct3 == 0:  # ADDI
                result = (a + imm_i) & MASK64
            elif funct3 == 1 and ((insn >> 26) & 0x3F) == 0:  # SLLI
                result = (a << ((insn >> 20) & 0x3F)) & MASK64
            else:
                raise AssertionError(f"unsupported OP-IMM encoding {insn:08x} at {pc:#x}")
        elif opcode == 0x33 and funct3 == 0 and funct7 == 0:  # ADD
            result = (a + b) & MASK64
        elif opcode == 0x37:  # LUI, sign extend the 32-bit result on RV64
            result = sext(insn & 0xFFFF_F000, 32) & MASK64
        elif opcode == 0x63 and funct3 == 1:  # BNE
            b_imm = (((insn >> 31) & 1) << 12)
            b_imm |= (((insn >> 7) & 1) << 11)
            b_imm |= (((insn >> 25) & 0x3F) << 5)
            b_imm |= (((insn >> 8) & 0xF) << 1)
            if a != b:
                next_pc = pc + sext(b_imm, 13)
        elif opcode == 0x23:  # stores
            s_imm = (((insn >> 25) & 0x7F) << 5) | ((insn >> 7) & 0x1F)
            addr = (a + sext(s_imm, 12)) & MASK64
            width = {0: 1, 1: 2, 2: 4, 3: 8}.get(funct3)
            if width is None or addr + width > len(memory):
                raise AssertionError(f"invalid store at {pc:#x}: {insn:08x}")
            for lane in range(width):
                memory[addr + lane] = (b >> (lane * 8)) & 0xFF
        elif opcode == 0x03:  # loads
            addr = (a + imm_i) & MASK64
            width = {0: 1, 1: 2, 2: 4, 3: 8, 4: 1, 5: 2, 6: 4}.get(funct3)
            if width is None or addr + width > len(memory):
                raise AssertionError(f"invalid load at {pc:#x}: {insn:08x}")
            raw = int.from_bytes(memory[addr : addr + width], "little")
            result = sext(raw, width * 8) & MASK64 if funct3 <= 3 else raw
        elif opcode == 0x73 and insn == 0x0010_0073:  # EBREAK terminates this test image
            halted = True
        else:
            raise AssertionError(f"unsupported instruction {insn:08x} at {pc:#x}")

        if result is not None and rd != 0:
            regs[rd] = result & MASK64
        regs[0] = 0
        retired += 1
        if halted:
            return regs, memory, pc, retired
        pc = next_pc

    raise AssertionError("reference program exceeded 1000 instructions")


def main() -> None:
    regs, memory, pc, retired = run_program()
    expected = {
        1: 5,
        2: 7,
        3: 12,
        7: 12,
        8: 0xFFFF_FFFF_FFFF_FF80,
        9: 0xFFFF_FFFF_FFFF_FF80,
        10: 128,
        11: 0xFFFF_FFFF_FFFF_FF80,
        12: 0xFF80,
        13: 0xFFFF_FFFF_8000_0000,
        14: 0xFFFF_FFFF_8000_0000,
        15: 0x8000_0000,
        17: 0xFF80,
        18: 0x8000_0000,
        31: 0x5A,
    }
    for reg, value in expected.items():
        if regs[reg] != value:
            raise AssertionError(f"x{reg}: got {regs[reg]:#018x}, expected {value:#018x}")
    if int.from_bytes(memory[0x100:0x108], "little") != 12:
        raise AssertionError("SD/LD memory marker mismatch")
    if pc != 128:
        raise AssertionError(f"expected success EBREAK at PC 128, got {pc}")
    print(f"PASS: software reference model; {retired} instructions; success marker x31={regs[31]:#x}")
    print("NOTE: this checks the test image, not the SystemVerilog RTL.")


if __name__ == "__main__":
    main()
