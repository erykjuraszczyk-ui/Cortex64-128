"""Structural checks for the v0.1.11 minimum-timeout boundary bench."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TB = ROOT / "sim" / "tb" / "cortex_mem_timeout_min_tb.sv"


def test_minimum_legal_timeout_and_boundary_error_are_covered():
    text = TB.read_text(encoding="utf-8")
    assert "localparam integer TIMEOUT_CYCLES = 1" in text
    assert "target error on minimum-timeout boundary was not propagated" in text
    assert "response changed while upstream was stalled" in text
    assert "reset did not clear held response and return adapter to idle" in text
    assert "timed-out downstream request must remain asserted and block reuse" in text
    assert "coordinated reset did not clear stalled downstream request" in text
    assert "target_accept_count != 2 || target_response_count != 2" in text
    assert "PASS: TIMEOUT_CYCLES=1" in text


def test_minimum_timeout_bench_is_wired_into_test_and_lint_runners():
    test_script = (ROOT / "tools" / "test.sh").read_text(encoding="utf-8")
    lint_script = (ROOT / "tools" / "lint.sh").read_text(encoding="utf-8")
    assert test_script.count("cortex_mem_timeout_min_tb") >= 4
    assert "cortex_mem_timeout_min_tb" in lint_script
