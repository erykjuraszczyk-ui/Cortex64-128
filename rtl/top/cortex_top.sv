// Portable simulation/FPGA top exposing the abstract memory request/response port.
module cortex_top #(
  parameter logic [63:0] RESET_PC = 64'h0000_0000_0000_0000
) (
  input logic clk, input logic rst_n,
  output logic mem_req_valid, input logic mem_req_ready,
  output logic [63:0] mem_req_addr, output logic mem_req_write,
  output logic [63:0] mem_req_wdata, output logic [7:0] mem_req_wstrb,
  input logic mem_rsp_valid, output logic mem_rsp_ready,
  input logic [63:0] mem_rsp_rdata, input logic mem_rsp_error,
  output logic halted, output logic fault, output logic [7:0] fault_code,
  output logic [63:0] pc_debug, output logic [63:0] instret
);
  cortex_core #(.RESET_PC(RESET_PC)) u_core (.*);
endmodule
