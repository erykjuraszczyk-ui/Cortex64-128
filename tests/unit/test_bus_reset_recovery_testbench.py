"""Structural checks for the v0.1.7 no-response/reset-recovery testbench.

These checks validate directed vectors and test integration only; they do not
compile or simulate SystemVerilog.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
TB = ROOT / "sim" / "tb" / "cortex_bus_reset_recovery_tb.sv"


def instruction_map() -> dict[int, int]:
    text = TB.read_text(encoding="utf-8")
    pairs = re.findall(
        r"put_word\(16'h([0-9a-fA-F_]+),\s*32'h([0-9a-fA-F_]+)\)", text
    )
    return {
        int(addr.replace("_", ""), 16): int(insn.replace("_", ""), 16)
        for addr, insn in pairs
    }


def test_recovery_program_encodings_and_success_fail_markers():
    insns = instruction_map()
    assert insns[0x0000] == 0x10000093  # ADDI x1,x0,0x100
    assert insns[0x0004] == 0x02A00113  # ADDI x2,x0,42
    assert insns[0x0008] == 0x0020B023  # SD x2,0(x1)
    assert insns[0x000C] == 0x0000B183  # LD x3,0(x1)
    assert insns[0x0014] == 0x00419663  # BNE x3,x4,+12
    assert insns[0x0018] == 0x05A00F93  # success marker x31=0x5a
    assert insns[0x0020] == 0x03300F93  # failure marker x31=0x33


def test_no_response_reset_and_transaction_ledger_are_present():
    text = TB.read_text(encoding="utf-8")
    for token in (
        "NO_RESPONSE_WATCH_CYCLES = 8",
        "suppress_responses = 1'b1",
        "expected one outstanding transaction before reset",
        "expected exactly one transaction aborted by reset",
        "unsolicited or duplicate response",
        "accepted_recovery != 10",
        "responses_recovery != accepted_recovery",
        "accepted_total != responses_total + aborted_total",
        "transaction still outstanding at completion",
    ):
        assert token in text
    assert "one response per accepted request" in text
    assert "no RTL bus" in text


def test_reset_recovery_bench_is_integrated_in_all_flows():
    test_script = (ROOT / "tools" / "test.sh").read_text(encoding="utf-8")
    lint_script = (ROOT / "tools" / "lint.sh").read_text(encoding="utf-8")
    assert test_script.count("cortex_bus_reset_recovery_tb") >= 4
    assert "cortex_bus_reset_recovery_tb" in lint_script
