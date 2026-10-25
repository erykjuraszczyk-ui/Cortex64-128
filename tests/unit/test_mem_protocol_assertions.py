"""Structural checks for the v0.1.12 simulation-time protocol assertion monitor."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "sim" / "checkers" / "cortex_mem_protocol_assertions.sv"
TB = ROOT / "sim" / "tb" / "cortex_mem_protocol_assertions_tb.sv"
ADAPTER = ROOT / "rtl" / "common" / "cortex_mem_timeout_adapter.sv"


def test_protocol_checker_covers_stability_on_all_four_channels():
    text = CHECKER.read_text(encoding="utf-8")
    for token in (
        "up_req_stalled_q", "down_req_stalled_q", "up_rsp_stalled_q",
        "down_rsp_stalled_q", "upstream request VALID dropped before READY",
        "downstream request VALID dropped before READY",
        "upstream response VALID dropped before READY",
        "downstream response VALID dropped before READY",
        "payload changed under backpressure",
    ):
        assert token in text


def test_protocol_checker_accounts_for_single_outstanding_transactions():
    text = CHECKER.read_text(encoding="utf-8")
    assert "up_outstanding_q" in text
    assert "down_outstanding_q" in text
    assert "second upstream request accepted while one is outstanding" in text
    assert "second target request accepted while one is outstanding" in text
    assert "unsolicited or duplicate upstream response" in text
    assert "unsolicited or duplicate target response" in text


def test_adapter_keeps_valid_and_payload_after_request_accept_timeout():
    text = ADAPTER.read_text(encoding="utf-8")
    assert "ST_UP_RSP_SEND" in text
    assert "ST_QUARANTINE_SEND" in text
    assert "down_req_valid = (state_q == ST_SEND) ||" in text
    assert "Request-accept timeout cannot retract the request" in text
    assert "state_q <= ST_UP_RSP_SEND;" in text


def test_assertion_bench_covers_timeout_late_acceptance_drain_and_normal_response():
    text = TB.read_text(encoding="utf-8")
    for token in (
        "retaining stalled request",
        "quarantine did not retain old request and block reuse",
        "Target eventually accepts the timed-out request", "consumed and discarded",
        "normal response changed while upstream stalled", "accepted_count != 2",
        "target_rsp_count != 2", "upstream_rsp_count != 2", "PASS: protocol assertions",
    ):
        assert token in text


def test_assertion_bench_is_wired_into_both_simulators_and_lint():
    test_script = (ROOT / "tools" / "test.sh").read_text(encoding="utf-8")
    lint_script = (ROOT / "tools" / "lint.sh").read_text(encoding="utf-8")
    assert test_script.count("cortex_mem_protocol_assertions_tb") >= 4
    assert "sim/checkers/cortex_mem_protocol_assertions.sv" in test_script
    assert "cortex_mem_protocol_assertions_tb" in lint_script
    assert "sim/checkers/cortex_mem_protocol_assertions.sv" in lint_script
