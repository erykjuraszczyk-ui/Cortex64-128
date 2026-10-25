"""Structural checks for the directed CSR/trap RTL test program.

These tests validate instruction encodings only; they do not simulate RTL.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
TB = ROOT / "sim" / "tb" / "cortex_csr_trap_tb.sv"


def instruction_map() -> dict[int, int]:
    text = TB.read_text(encoding="utf-8")
    pairs = re.findall(
        r"put_word\(16'h([0-9a-fA-F_]+),\s*32'h([0-9a-fA-F_]+)\)", text
    )
    return {int(addr.replace("_", ""), 16): int(insn.replace("_", ""), 16) for addr, insn in pairs}


def branch_offset(insn: int) -> int:
    imm = (((insn >> 31) & 1) << 12)
    imm |= (((insn >> 7) & 1) << 11)
    imm |= (((insn >> 25) & 0x3F) << 5)
    imm |= (((insn >> 8) & 0xF) << 1)
    return imm - (1 << 13) if imm & (1 << 12) else imm


def test_csr_trap_image_contains_expected_system_instructions():
    insns = instruction_map()
    assert insns[0x018] == 0x00000073  # ECALL
    assert insns[0x11C] == 0x30200073  # MRET, ECALL path
    assert insns[0x130] == 0x30200073  # MRET, illegal-instruction path
    assert insns[0x024] == 0x00100073  # EBREAK terminal marker


def test_csr_instruction_fields_and_read_only_write_vector():
    insns = instruction_map()
    # CSRRS x2, mscratch, x0
    read_scratch = insns[0x008]
    assert (read_scratch & 0x7F) == 0x73
    assert ((read_scratch >> 20) & 0xFFF) == 0x340
    assert ((read_scratch >> 15) & 0x1F) == 0
    assert ((read_scratch >> 12) & 0x7) == 0b010
    assert ((read_scratch >> 7) & 0x1F) == 2

    # CSRRW x0, misa, x1 is intended to trap because misa is read-only.
    write_misa = insns[0x020]
    assert (write_misa & 0x7F) == 0x73
    assert ((write_misa >> 20) & 0xFFF) == 0x301
    assert ((write_misa >> 15) & 0x1F) == 1
    assert ((write_misa >> 12) & 0x7) == 0b001
    assert ((write_misa >> 7) & 0x1F) == 0


def test_trap_handler_branch_targets_illegal_path():
    insns = instruction_map()
    dispatch_pc = 0x108
    dispatch = insns[dispatch_pc]
    assert (dispatch & 0x7F) == 0x63  # B-type branch
    assert ((dispatch >> 12) & 0x7) == 0b001  # BNE
    assert ((dispatch >> 15) & 0x1F) == 5   # rs1 = mcause destination
    assert ((dispatch >> 20) & 0x1F) == 9   # rs2 = 11
    assert dispatch_pc + branch_offset(dispatch) == 0x120
