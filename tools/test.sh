#!/usr/bin/env sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

python3 tools/gen_smoke_hex.py
python3 -m pytest -q tests/unit
python3 sim/reference_model/rv64_smoke.py

if command -v verilator >/dev/null 2>&1; then
  mkdir -p build
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_core_tb --Mdir build/obj_core rtl/cpu/cortex_core.sv sim/tb/cortex_core_tb.sv
  build/obj_core/Vcortex_core_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_csr_trap_tb --Mdir build/obj_csr_trap rtl/cpu/cortex_core.sv sim/tb/cortex_csr_trap_tb.sv
  build/obj_csr_trap/Vcortex_csr_trap_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_bram_mem_tb --Mdir build/obj_bram_mem rtl/memory/cortex_bram_mem.sv sim/tb/cortex_bram_mem_tb.sv
  build/obj_bram_mem/Vcortex_bram_mem_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_bram_soc_tb --Mdir build/obj_bram_soc rtl/cpu/cortex_core.sv rtl/memory/cortex_bram_mem.sv rtl/top/cortex_bram_soc.sv sim/tb/cortex_bram_soc_tb.sv
  build/obj_bram_soc/Vcortex_bram_soc_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_mem_fault_tb --Mdir build/obj_mem_fault rtl/cpu/cortex_core.sv sim/tb/cortex_mem_fault_tb.sv
  build/obj_mem_fault/Vcortex_mem_fault_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_mem_backpressure_tb --Mdir build/obj_mem_backpressure rtl/cpu/cortex_core.sv sim/tb/cortex_mem_backpressure_tb.sv
  build/obj_mem_backpressure/Vcortex_mem_backpressure_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_bus_reset_recovery_tb --Mdir build/obj_bus_reset_recovery rtl/cpu/cortex_core.sv sim/tb/cortex_bus_reset_recovery_tb.sv
  build/obj_bus_reset_recovery/Vcortex_bus_reset_recovery_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_mem_timeout_adapter_tb --Mdir build/obj_mem_timeout_adapter rtl/common/cortex_mem_timeout_adapter.sv sim/tb/cortex_mem_timeout_adapter_tb.sv
  build/obj_mem_timeout_adapter/Vcortex_mem_timeout_adapter_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_mem_timeout_min_tb --Mdir build/obj_mem_timeout_min rtl/common/cortex_mem_timeout_adapter.sv sim/tb/cortex_mem_timeout_min_tb.sv
  build/obj_mem_timeout_min/Vcortex_mem_timeout_min_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_timeout_bram_soc_tb --Mdir build/obj_timeout_bram_soc rtl/cpu/cortex_core.sv rtl/common/cortex_mem_timeout_adapter.sv rtl/top/cortex_top_timeout.sv rtl/memory/cortex_bram_mem.sv rtl/top/cortex_timeout_bram_soc.sv sim/tb/cortex_timeout_bram_soc_tb.sv
  build/obj_timeout_bram_soc/Vcortex_timeout_bram_soc_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_mem_random_latency_tb --Mdir build/obj_mem_random_latency rtl/common/cortex_mem_timeout_adapter.sv sim/tb/cortex_mem_random_latency_tb.sv
  build/obj_mem_random_latency/Vcortex_mem_random_latency_tb
  verilator --binary --timing --Wall -Wno-fatal --top-module cortex_mem_protocol_assertions_tb --Mdir build/obj_mem_protocol_assertions rtl/common/cortex_mem_timeout_adapter.sv sim/checkers/cortex_mem_protocol_assertions.sv sim/tb/cortex_mem_protocol_assertions_tb.sv
  build/obj_mem_protocol_assertions/Vcortex_mem_protocol_assertions_tb
elif command -v iverilog >/dev/null 2>&1; then
  mkdir -p build
  iverilog -g2012 -s cortex_core_tb -o build/cortex_core_tb.vvp rtl/cpu/cortex_core.sv sim/tb/cortex_core_tb.sv && vvp build/cortex_core_tb.vvp
  iverilog -g2012 -s cortex_csr_trap_tb -o build/cortex_csr_trap_tb.vvp rtl/cpu/cortex_core.sv sim/tb/cortex_csr_trap_tb.sv && vvp build/cortex_csr_trap_tb.vvp
  iverilog -g2012 -s cortex_bram_mem_tb -o build/cortex_bram_mem_tb.vvp rtl/memory/cortex_bram_mem.sv sim/tb/cortex_bram_mem_tb.sv && vvp build/cortex_bram_mem_tb.vvp
  iverilog -g2012 -s cortex_bram_soc_tb -o build/cortex_bram_soc_tb.vvp rtl/cpu/cortex_core.sv rtl/memory/cortex_bram_mem.sv rtl/top/cortex_bram_soc.sv sim/tb/cortex_bram_soc_tb.sv && vvp build/cortex_bram_soc_tb.vvp
  iverilog -g2012 -s cortex_mem_fault_tb -o build/cortex_mem_fault_tb.vvp rtl/cpu/cortex_core.sv sim/tb/cortex_mem_fault_tb.sv && vvp build/cortex_mem_fault_tb.vvp
  iverilog -g2012 -s cortex_mem_backpressure_tb -o build/cortex_mem_backpressure_tb.vvp rtl/cpu/cortex_core.sv sim/tb/cortex_mem_backpressure_tb.sv && vvp build/cortex_mem_backpressure_tb.vvp
  iverilog -g2012 -s cortex_bus_reset_recovery_tb -o build/cortex_bus_reset_recovery_tb.vvp rtl/cpu/cortex_core.sv sim/tb/cortex_bus_reset_recovery_tb.sv && vvp build/cortex_bus_reset_recovery_tb.vvp
  iverilog -g2012 -s cortex_mem_timeout_adapter_tb -o build/cortex_mem_timeout_adapter_tb.vvp rtl/common/cortex_mem_timeout_adapter.sv sim/tb/cortex_mem_timeout_adapter_tb.sv && vvp build/cortex_mem_timeout_adapter_tb.vvp
  iverilog -g2012 -s cortex_mem_timeout_min_tb -o build/cortex_mem_timeout_min_tb.vvp rtl/common/cortex_mem_timeout_adapter.sv sim/tb/cortex_mem_timeout_min_tb.sv && vvp build/cortex_mem_timeout_min_tb.vvp
  iverilog -g2012 -s cortex_timeout_bram_soc_tb -o build/cortex_timeout_bram_soc_tb.vvp rtl/cpu/cortex_core.sv rtl/common/cortex_mem_timeout_adapter.sv rtl/top/cortex_top_timeout.sv rtl/memory/cortex_bram_mem.sv rtl/top/cortex_timeout_bram_soc.sv sim/tb/cortex_timeout_bram_soc_tb.sv && vvp build/cortex_timeout_bram_soc_tb.vvp
  iverilog -g2012 -s cortex_mem_random_latency_tb -o build/cortex_mem_random_latency_tb.vvp rtl/common/cortex_mem_timeout_adapter.sv sim/tb/cortex_mem_random_latency_tb.sv && vvp build/cortex_mem_random_latency_tb.vvp
  iverilog -g2012 -s cortex_mem_protocol_assertions_tb -o build/cortex_mem_protocol_assertions_tb.vvp rtl/common/cortex_mem_timeout_adapter.sv sim/checkers/cortex_mem_protocol_assertions.sv sim/tb/cortex_mem_protocol_assertions_tb.sv && vvp build/cortex_mem_protocol_assertions_tb.vvp
else
  echo "ERROR: Python checks passed, but no RTL simulator was found." >&2
  echo "Install Verilator 5.x (recommended) or Icarus Verilog, then rerun ./tools/test.sh." >&2
  exit 127
fi
