from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
TB=ROOT/'sim/tb/cortex_rv64i_directed_tb.sv'
RUNNER=ROOT/'tools/test.sh'
LINTER=ROOT/'tools/lint.sh'
def test_directed_bench_checks_architectural_state():
    text=TB.read_text(encoding='utf-8')
    for s in ('cortex_core dut','enc_i','enc_r','dut.regs[1]','dut.regs[12]',"instret!==64'd12",'PASS: directed RV64I ALU execution'):
        assert s in text
def test_directed_bench_is_wired_into_tooling():
    assert 'cortex_rv64i_directed_tb' in RUNNER.read_text(encoding='utf-8')
    assert 'cortex_rv64i_directed_tb' in LINTER.read_text(encoding='utf-8')
