"""Structural checks for the generated smoke image; RTL simulation is separate."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HEX = ROOT / "sim" / "programs" / "smoke_test.hex"


def read_instructions() -> list[int]:
    qwords = [int(line.strip(), 16) for line in HEX.read_text(encoding="ascii").splitlines() if line.strip()]
    instructions: list[int] = []
    for qword in qwords:
        instructions.extend((qword & 0xFFFF_FFFF, (qword >> 32) & 0xFFFF_FFFF))
    return instructions


def branch_offset(insn: int) -> int:
    imm = (((insn >> 31) & 1) << 12)
    imm |= (((insn >> 7) & 1) << 11)
    imm |= (((insn >> 25) & 0x3F) << 5)
    imm |= (((insn >> 8) & 0xF) << 1)
    return imm - (1 << 13) if imm & (1 << 12) else imm


def test_image_has_expected_shape_and_base_instructions():
    qwords = [int(line.strip(), 16) for line in HEX.read_text(encoding="ascii").splitlines() if line.strip()]
    insns = read_instructions()
    assert len(qwords) == 512
    assert insns[0] == 0x00500093  # ADDI x1,x0,5
    assert insns[1] == 0x00700113  # ADDI x2,x0,7
    assert insns[2] == 0x002081B3  # ADD x3,x1,x2
    assert insns[6] == 0x00333023  # SD x3,0(x6)
    assert insns[7] == 0x00033383  # LD x7,0(x6)
    assert insns[32] == 0x00100073  # EBREAK success path


def test_every_failure_branch_targets_failure_marker():
    insns = read_instructions()
    fail_pc = 33 * 4
    branch_pcs = [16, 32, 80, 88, 92, 104, 108, 120]
    for pc in branch_pcs:
        assert pc + branch_offset(insns[pc // 4]) == fail_pc
    assert insns[33] == 0x03300F93  # ADDI x31,x0,0x33


def test_program_covers_signed_and_unsigned_load_variants():
    insns = read_instructions()
    # LOAD opcode 0x03, funct3 LB/LH/LW/LD/LBU/LHU/LWU = 0..6.
    funct3s = {((insn >> 12) & 0x7) for insn in insns if (insn & 0x7F) == 0x03}
    assert funct3s == set(range(7))
    # STORE opcode 0x23 covers SB/SH/SW/SD.
    store_funct3s = {((insn >> 12) & 0x7) for insn in insns if (insn & 0x7F) == 0x23}
    assert store_funct3s == {0, 1, 2, 3}
