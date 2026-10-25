"""Structural checks for the v0.1.6 delayed-response/backpressure bench.

These tests validate the directed test program and runner integration only;
they do not simulate or prove the SystemVerilog implementation.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
TB = ROOT / "sim" / "tb" / "cortex_mem_backpressure_tb.sv"


def instruction_map() -> dict[int, int]:
    text = TB.read_text(encoding="utf-8")
    pairs = re.findall(
        r"put_word\(16'h([0-9a-fA-F_]+),\s*32'h([0-9a-fA-F_]+)\)", text
    )
    return {
        int(addr.replace("_", ""), 16): int(insn.replace("_", ""), 16)
        for addr, insn in pairs
    }


def test_backpressure_program_encodings_and_failure_branch():
    insns = instruction_map()
    assert insns[0x0000] == 0x10000093  # ADDI x1,x0,0x100
    assert insns[0x0004] == 0x02A00113  # ADDI x2,x0,42
    assert insns[0x0008] == 0x0020B023  # SD x2,0(x1)
    assert insns[0x000C] == 0x0000B183  # LD x3,0(x1)
    assert insns[0x0010] == 0x02A00213  # ADDI x4,x0,42
    assert insns[0x0014] == 0x00419663  # BNE x3,x4,+12
    assert insns[0x0018] == 0x05A00F93  # PASS marker
    assert insns[0x0020] == 0x03300F93  # FAIL marker


def test_bench_has_stability_assertion_and_stall_coverage():
    text = TB.read_text(encoding="utf-8")
    assert "request payload changed while stalled" in text
    assert "request_stall_cycles < 10" in text
    assert "response_delay_cycles < 20" in text
    assert "accepted_count != 10" in text
    assert "mem_rsp_valid && mem_rsp_ready" in text


def test_test_and_lint_scripts_include_backpressure_bench():
    test_script = (ROOT / "tools" / "test.sh").read_text(encoding="utf-8")
    lint_script = (ROOT / "tools" / "lint.sh").read_text(encoding="utf-8")
    assert "cortex_mem_backpressure_tb" in test_script
    assert "cortex_mem_backpressure_tb" in lint_script
