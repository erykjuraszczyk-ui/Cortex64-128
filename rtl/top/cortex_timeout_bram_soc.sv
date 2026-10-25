// Cortex64/128 integration top: CPU -> timeout adapter -> generic BRAM.
// This is a portable simulation target, not a DDR4 controller or PHY.
module cortex_timeout_bram_soc #(
  parameter logic [63:0] RESET_PC = 64'h0000_0000_0000_0000,
  parameter logic [63:0] MEM_BASE_ADDR = 64'h0000_0000_0000_0000,
  parameter integer MEM_WORDS = 512,
  parameter INIT_FILE = "",
  parameter integer TIMEOUT_CYCLES = 64
) (
  input logic clk, input logic rst_n,
  output logic halted, output logic fault, output logic [7:0] fault_code,
  output logic [63:0] pc_debug, output logic [63:0] instret
);
  logic mem_req_valid, mem_req_ready, mem_req_write;
  logic [63:0] mem_req_addr, mem_req_wdata, mem_rsp_rdata;
  logic [7:0] mem_req_wstrb;
  logic mem_rsp_valid, mem_rsp_ready, mem_rsp_error;

  cortex_top_timeout #(.RESET_PC(RESET_PC), .TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_top (
    .clk(clk), .rst_n(rst_n),
    .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
    .mem_req_addr(mem_req_addr), .mem_req_write(mem_req_write),
    .mem_req_wdata(mem_req_wdata), .mem_req_wstrb(mem_req_wstrb),
    .mem_rsp_valid(mem_rsp_valid), .mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_rdata(mem_rsp_rdata), .mem_rsp_error(mem_rsp_error),
    .halted(halted), .fault(fault), .fault_code(fault_code),
    .pc_debug(pc_debug), .instret(instret)
  );
  cortex_bram_mem #(.BASE_ADDR(MEM_BASE_ADDR), .WORDS(MEM_WORDS), .INIT_FILE(INIT_FILE)) u_mem (
    .clk(clk), .rst_n(rst_n),
    .req_valid(mem_req_valid), .req_ready(mem_req_ready),
    .req_addr(mem_req_addr), .req_write(mem_req_write),
    .req_wdata(mem_req_wdata), .req_wstrb(mem_req_wstrb),
    .rsp_valid(mem_rsp_valid), .rsp_ready(mem_rsp_ready),
    .rsp_rdata(mem_rsp_rdata), .rsp_error(mem_rsp_error)
  );
endmodule
