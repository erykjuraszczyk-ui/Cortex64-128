from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / "rtl" / "cpu" / "cortex_core.sv"
DOC = ROOT / "docs" / "RV64I_VERIFICATION_v0.1.14.md"


def test_rv64i_verification_inventory_exists():
    assert DOC.is_file()
    text = DOC.read_text(encoding="utf-8")
    for group in ("Arithmetic/logical", "RV64 word operations", "Loads/stores",
                  "Control flow", "Exceptions/CSR", "Retirement"):
        assert group in text


def test_core_contains_expected_base_integer_opcode_groups():
    text = RTL.read_text(encoding="utf-8")
    # Opcode-level inventory: this is a structural guard, not an execution test.
    for opcode in ("7'h37", "7'h17", "7'h13", "7'h33", "7'h1b", "7'h3b",
                   "7'h63", "7'h03", "7'h23", "7'h6f", "7'h67", "7'h0f",
                   "7'h73"):
        assert opcode in text


def test_core_contains_signed_unsigned_load_store_and_branch_cases():
    text = RTL.read_text(encoding="utf-8")
    for fragment in ("3'b000: regs[mem_rd_q]", "3'b100: regs[mem_rd_q]",
                     "3'b010: mem_wstrb_q", "3'b110: branch_taken",
                     "3'b111: branch_taken", "jalr_target",
                     "mem_fault_addr_q"):
        assert fragment in text


def test_core_documents_unsupported_encodings_and_traps():
    text = RTL.read_text(encoding="utf-8")
    for fragment in ("exec_illegal", "take_trap(pc, 64'd2",
                     "take_trap(pc, 64'd4", "take_trap(pc, 64'd6"):
        assert fragment in text
