#!/usr/bin/env sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
if ! command -v verilator >/dev/null 2>&1; then
  echo "ERROR: Verilator is not installed. Install Verilator 5.x or newer." >&2
  exit 127
fi
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_top rtl/cpu/cortex_core.sv rtl/top/cortex_top.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_bram_soc rtl/cpu/cortex_core.sv rtl/memory/cortex_bram_mem.sv rtl/top/cortex_bram_soc.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_bram_mem_tb rtl/memory/cortex_bram_mem.sv sim/tb/cortex_bram_mem_tb.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_csr_trap_tb rtl/cpu/cortex_core.sv sim/tb/cortex_csr_trap_tb.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_mem_fault_tb rtl/cpu/cortex_core.sv sim/tb/cortex_mem_fault_tb.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_mem_backpressure_tb rtl/cpu/cortex_core.sv sim/tb/cortex_mem_backpressure_tb.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_bus_reset_recovery_tb rtl/cpu/cortex_core.sv sim/tb/cortex_bus_reset_recovery_tb.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_top_timeout rtl/cpu/cortex_core.sv rtl/common/cortex_mem_timeout_adapter.sv rtl/top/cortex_top_timeout.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_mem_timeout_adapter_tb rtl/common/cortex_mem_timeout_adapter.sv sim/tb/cortex_mem_timeout_adapter_tb.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_mem_timeout_min_tb rtl/common/cortex_mem_timeout_adapter.sv sim/tb/cortex_mem_timeout_min_tb.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_timeout_bram_soc rtl/cpu/cortex_core.sv rtl/common/cortex_mem_timeout_adapter.sv rtl/top/cortex_top_timeout.sv rtl/memory/cortex_bram_mem.sv rtl/top/cortex_timeout_bram_soc.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_timeout_bram_soc_tb rtl/cpu/cortex_core.sv rtl/common/cortex_mem_timeout_adapter.sv rtl/top/cortex_top_timeout.sv rtl/memory/cortex_bram_mem.sv rtl/top/cortex_timeout_bram_soc.sv sim/tb/cortex_timeout_bram_soc_tb.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_mem_random_latency_tb rtl/common/cortex_mem_timeout_adapter.sv sim/tb/cortex_mem_random_latency_tb.sv
verilator --lint-only --timing --Wall -Wno-fatal --top-module cortex_mem_protocol_assertions_tb rtl/common/cortex_mem_timeout_adapter.sv sim/checkers/cortex_mem_protocol_assertions.sv sim/tb/cortex_mem_protocol_assertions_tb.sv
