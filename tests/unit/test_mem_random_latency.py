"""Structural checks for the v0.1.10 deterministic random-latency testbench."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TB = ROOT / "sim" / "tb" / "cortex_mem_random_latency_tb.sv"
ADAPTER = ROOT / "rtl" / "common" / "cortex_mem_timeout_adapter.sv"


def test_random_latency_bench_has_deterministic_seed_and_many_transactions():
    text = TB.read_text(encoding="utf-8")
    assert "rng_q = 32'h1ACE_B00C" in text
    assert "function automatic logic [31:0] lfsr_next" in text
    assert "localparam integer TRANSACTIONS = 40" in text
    assert "response_delay_q" in text
    assert "down_req_ready <= (rng_q[1:0] != 2'b00)" in text


def test_random_latency_bench_checks_request_response_stability_and_ledgers():
    text = TB.read_text(encoding="utf-8")
    for token in (
        "downstream request payload changed while stalled",
        "upstream request payload changed while stalled",
        "upstream response changed while stalled",
        "unsolicited or duplicate randomized target response",
        "target ledger mismatch",
        "upstream ledger mismatch",
        "unexpected timeout/error responses",
        "PASS: randomized-latency adapter stress",
    ):
        assert token in text


def test_random_latency_bench_uses_timeout_adapter_and_is_wired_into_runners():
    tb = TB.read_text(encoding="utf-8")
    assert "cortex_mem_timeout_adapter #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut" in tb
    test_script = (ROOT / "tools" / "test.sh").read_text(encoding="utf-8")
    lint_script = (ROOT / "tools" / "lint.sh").read_text(encoding="utf-8")
    assert test_script.count("cortex_mem_random_latency_tb") >= 4
    assert "cortex_mem_random_latency_tb" in lint_script
