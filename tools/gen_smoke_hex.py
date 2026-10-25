#!/usr/bin/env python3
"""Generate a deterministic 64-bit-word memory image for v0.1.2 smoke tests."""
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "sim" / "programs" / "smoke_test.hex"
MEM_WORDS = 512


def enc_i(opcode: int, rd: int, funct3: int, rs1: int, imm: int) -> int:
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_r(opcode: int, rd: int, funct3: int, rs1: int, rs2: int, funct7: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(opcode: int, funct3: int, rs1: int, rs2: int, imm: int) -> int:
    imm &= 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | opcode


def enc_b(opcode: int, funct3: int, rs1: int, rs2: int, offset: int) -> int:
    if offset & 1:
        raise ValueError("RISC-V branch offset must be even")
    imm = offset & 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | opcode


def enc_u(opcode: int, rd: int, imm20: int) -> int:
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def encode_program() -> list[int]:
    # Entries are (operation, arguments); label entries do not consume space.
    p: list[tuple] = [
        ("addi", 1, 0, 5),
        ("addi", 2, 0, 7),
        ("add", 3, 1, 2),
        ("addi", 4, 0, 12),
        ("bne", 3, 4, "fail"),
        ("addi", 6, 0, 0x100),
        ("sd", 3, 6, 0),
        ("ld", 7, 6, 0),
        ("bne", 7, 3, "fail"),
        ("addi", 8, 0, -128),
        ("sb", 8, 6, 8),
        ("lb", 9, 6, 8),
        ("lbu", 10, 6, 8),
        ("sh", 8, 6, 10),
        ("lh", 11, 6, 10),
        ("lhu", 12, 6, 10),
        ("lui", 13, 0x80000),
        ("sw", 13, 6, 12),
        ("lw", 14, 6, 12),
        ("lwu", 15, 6, 12),
        ("bne", 9, 8, "fail"),
        ("addi", 16, 0, 128),
        ("bne", 10, 16, "fail"),
        ("bne", 11, 8, "fail"),
        ("lui", 17, 0x10),
        ("addi", 17, 17, -128),
        ("bne", 12, 17, "fail"),
        ("bne", 14, 13, "fail"),
        ("addi", 18, 0, 1),
        ("slli", 18, 18, 31),
        ("bne", 15, 18, "fail"),
        ("addi", 31, 0, 0x5A),
        ("ebreak",),
        ("label", "fail"),
        ("addi", 31, 0, 0x33),
        ("ebreak",),
    ]
    labels: dict[str, int] = {}
    pc = 0
    for item in p:
        if item[0] == "label":
            labels[item[1]] = pc
        else:
            pc += 4

    result: list[int] = []
    pc = 0
    for item in p:
        op, *a = item
        if op == "label":
            continue
        if op == "addi":
            insn = enc_i(0x13, a[0], 0, a[1], a[2])
        elif op == "slli":
            insn = enc_i(0x13, a[0], 1, a[1], a[2])
        elif op == "add":
            insn = enc_r(0x33, a[0], 0, a[1], a[2], 0)
        elif op == "lui":
            insn = enc_u(0x37, a[0], a[1])
        elif op == "bne":
            insn = enc_b(0x63, 1, a[0], a[1], labels[a[2]] - pc)
        elif op in ("lb", "lh", "lw", "ld", "lbu", "lhu", "lwu"):
            funct3 = {"lb": 0, "lh": 1, "lw": 2, "ld": 3, "lbu": 4, "lhu": 5, "lwu": 6}[op]
            insn = enc_i(0x03, a[0], funct3, a[1], a[2])
        elif op in ("sb", "sh", "sw", "sd"):
            funct3 = {"sb": 0, "sh": 1, "sw": 2, "sd": 3}[op]
            insn = enc_s(0x23, funct3, a[1], a[0], a[2])
        elif op == "ebreak":
            insn = 0x00100073
        else:
            raise ValueError(f"Unknown operation: {op}")
        result.append(insn)
        pc += 4
    return result


def main() -> None:
    instructions = encode_program()
    if len(instructions) > MEM_WORDS * 2:
        raise SystemExit("Program does not fit in configured memory")
    words = [0] * MEM_WORDS
    for i, instruction in enumerate(instructions):
        wi = i // 2
        if i % 2 == 0:
            words[wi] = (words[wi] & 0xFFFF_FFFF_0000_0000) | instruction
        else:
            words[wi] = (words[wi] & 0x0000_0000_FFFF_FFFF) | (instruction << 32)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(f"{word:016x}\n" for word in words), encoding="ascii")
    print(f"Generated {OUT.relative_to(ROOT)}: {len(instructions)} instructions, {MEM_WORDS} 64-bit words")


if __name__ == "__main__":
    main()
