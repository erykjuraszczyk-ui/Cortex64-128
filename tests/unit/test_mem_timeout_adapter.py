"""Structural checks for the v0.1.8 timeout adapter; no RTL simulation is implied."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "rtl" / "common" / "cortex_mem_timeout_adapter.sv"
WRAPPER = ROOT / "rtl" / "top" / "cortex_top_timeout.sv"
TB = ROOT / "sim" / "tb" / "cortex_mem_timeout_adapter_tb.sv"


def test_timeout_adapter_defines_both_timeout_phases_and_quarantine():
    text = ADAPTER.read_text(encoding="utf-8")
    for token in (
        "parameter integer TIMEOUT_CYCLES = 64",
        "ST_SEND",
        "ST_WAIT_RSP",
        "ST_UP_RSP",
        "ST_QUARANTINE",
        "ST_UP_RSP_SEND",
        "ST_QUARANTINE_SEND",
        "timer_q >= (TIMEOUT_CYCLES - 1)",
        "down_req_valid = (state_q == ST_SEND) ||",
        "(state_q == ST_UP_RSP_SEND)",
        "(state_q == ST_QUARANTINE_SEND)",
        "quarantine_after_rsp_q <= 1'b1",
        "stale_pending_q <= 1'b1",
        "down_rsp_valid",
        "up_rsp_error",
        "down_rsp_ready",
    ):
        assert token in text
    wait_block = text.split("ST_WAIT_RSP: begin", 1)[1].split("ST_UP_RSP_SEND: begin", 1)[0]
    assert wait_block.index("if (downstream_rsp_fire)") < wait_block.index("else if (timer_q >= (TIMEOUT_CYCLES - 1))")


def test_timeout_top_places_adapter_between_cpu_and_external_bus():
    text = WRAPPER.read_text(encoding="utf-8")
    assert "cortex_core #(.RESET_PC(RESET_PC)) u_core" in text
    assert "cortex_mem_timeout_adapter #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_timeout" in text
    assert ".down_req_valid(mem_req_valid)" in text
    assert ".up_req_valid(cpu_req_valid)" in text


def test_timeout_testbench_exercises_timeout_late_response_and_recovery():
    text = TB.read_text(encoding="utf-8")
    for token in (
        "request-accept timeout",
        "response timeout",
        "late response",
        "quarantine",
        "normal response after quarantine",
        "response on the timeout boundary must take priority over timeout",
        "target_accept_count != 6",
        "target_response_count != 5",
        "target_abort_count != 1",
        "upstream_response_count != 6",
        "downstream request changed while waiting for req_ready",
        "downstream VALID withdrawn before READY handshake",
        "downstream request VALID/payload must remain asserted after pre-accept timeout",
    ):
        assert token in text
    assert "PASS: ready/valid-stable request timeout, response timeout, boundary priority" in text


def test_timeout_bench_is_integrated_in_test_and_lint_scripts():
    test_script = (ROOT / "tools" / "test.sh").read_text(encoding="utf-8")
    lint_script = (ROOT / "tools" / "lint.sh").read_text(encoding="utf-8")
    assert test_script.count("cortex_mem_timeout_adapter_tb") >= 4
    assert "cortex_mem_timeout_adapter_tb" in lint_script
    assert "cortex_top_timeout" in lint_script


def test_timeout_adapter_is_integrated_with_bram_soc_smoke_test():
    top = ROOT / "rtl" / "top" / "cortex_timeout_bram_soc.sv"
    tb = ROOT / "sim" / "tb" / "cortex_timeout_bram_soc_tb.sv"
    top_text = top.read_text(encoding="utf-8")
    tb_text = tb.read_text(encoding="utf-8")
    assert "cortex_top_timeout" in top_text
    assert "cortex_bram_mem" in top_text
    assert ".TIMEOUT_CYCLES(TIMEOUT_CYCLES)" in top_text
    assert 'INIT_FILE("sim/programs/smoke_test.hex")' in tb_text
    assert "dut.u_top.u_core.regs[31] !== 64'h5a" in tb_text
    assert "target_accept_count != target_response_count" in tb_text
    assert "cpu_request_count != cpu_response_count" in tb_text


def test_timeout_bram_soc_tb_is_in_test_and_lint_scripts():
    test_script = (ROOT / "tools" / "test.sh").read_text(encoding="utf-8")
    lint_script = (ROOT / "tools" / "lint.sh").read_text(encoding="utf-8")
    assert test_script.count("cortex_timeout_bram_soc_tb") >= 4
    assert "cortex_timeout_bram_soc" in lint_script
    assert "cortex_timeout_bram_soc_tb" in lint_script
