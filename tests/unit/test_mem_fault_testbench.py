"""Structural checks for the v0.1.5 data-fault RTL test program.

These tests check the test vector and expected exception metadata; they do not
execute or simulate the SystemVerilog core.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
TB = ROOT / "sim" / "tb" / "cortex_mem_fault_tb.sv"


def instruction_map() -> dict[int, int]:
    text = TB.read_text(encoding="utf-8")
    pairs = re.findall(
        r"put_word\(16'h([0-9a-fA-F_]+),\s*32'h([0-9a-fA-F_]+)\)", text
    )
    return {
        int(addr.replace("_", ""), 16): int(insn.replace("_", ""), 16)
        for addr, insn in pairs
    }


def test_four_memory_fault_scenarios_have_expected_instructions():
    insns = instruction_map()
    assert insns[0x004] == 0x0000B103  # LD with base 0x101 (misaligned)
    assert insns[0x018] == 0x0000B203  # LD from injected bus-error address 0x200
    assert insns[0x02C] == 0x0030B023  # SD with base 0x201 (misaligned)
    assert insns[0x040] == 0x0030B023  # SD to injected bus-error address 0x300
    assert insns[0x054] == 0x00100073  # EBREAK success marker


def test_handler_reads_trap_csrs_and_returns_with_mret():
    insns = instruction_map()
    assert insns[0x100] == 0x34202573  # CSRRs x10,mcause,x0
    assert insns[0x104] == 0x341025F3  # CSRRs x11,mepc,x0
    assert insns[0x108] == 0x34302673  # CSRRs x12,mtval,x0
    assert insns[0x110] == 0x34171073  # CSRRW x0,mepc,x14
    assert insns[0x114] == 0x30200073  # MRET


def test_expected_causes_and_fault_addresses_are_documented():
    text = TB.read_text(encoding="utf-8")
    for expected in (
        "cause 4, PC 0x004",
        "cause 5, PC 0x018",
        "cause 6, PC 0x02c",
        "cause 7, PC 0x040",
        "64'h200",
        "64'h300",
    ):
        assert expected in text
    assert "misaligned load trap mismatch" in text
    assert "load access fault mismatch" in text
    assert "misaligned store trap mismatch" in text
    assert "store access fault mismatch" in text
