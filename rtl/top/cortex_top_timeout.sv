// Portable CPU top with an optional bounded-latency memory adapter.
module cortex_top_timeout #(
  parameter logic [63:0] RESET_PC = 64'h0000_0000_0000_0000,
  parameter integer TIMEOUT_CYCLES = 64
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
  logic cpu_req_valid, cpu_req_ready, cpu_req_write;
  logic [63:0] cpu_req_addr, cpu_req_wdata;
  logic [7:0] cpu_req_wstrb;
  logic cpu_rsp_valid, cpu_rsp_ready, cpu_rsp_error;
  logic [63:0] cpu_rsp_rdata;

  cortex_core #(.RESET_PC(RESET_PC)) u_core (
    .clk(clk), .rst_n(rst_n),
    .mem_req_valid(cpu_req_valid), .mem_req_ready(cpu_req_ready),
    .mem_req_addr(cpu_req_addr), .mem_req_write(cpu_req_write),
    .mem_req_wdata(cpu_req_wdata), .mem_req_wstrb(cpu_req_wstrb),
    .mem_rsp_valid(cpu_rsp_valid), .mem_rsp_ready(cpu_rsp_ready),
    .mem_rsp_rdata(cpu_rsp_rdata), .mem_rsp_error(cpu_rsp_error),
    .halted(halted), .fault(fault), .fault_code(fault_code),
    .pc_debug(pc_debug), .instret(instret)
  );
  cortex_mem_timeout_adapter #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_timeout (
    .clk(clk), .rst_n(rst_n),
    .up_req_valid(cpu_req_valid), .up_req_ready(cpu_req_ready),
    .up_req_addr(cpu_req_addr), .up_req_write(cpu_req_write),
    .up_req_wdata(cpu_req_wdata), .up_req_wstrb(cpu_req_wstrb),
    .up_rsp_valid(cpu_rsp_valid), .up_rsp_ready(cpu_rsp_ready),
    .up_rsp_rdata(cpu_rsp_rdata), .up_rsp_error(cpu_rsp_error),
    .down_req_valid(mem_req_valid), .down_req_ready(mem_req_ready),
    .down_req_addr(mem_req_addr), .down_req_write(mem_req_write),
    .down_req_wdata(mem_req_wdata), .down_req_wstrb(mem_req_wstrb),
    .down_rsp_valid(mem_rsp_valid), .down_rsp_ready(mem_rsp_ready),
    .down_rsp_rdata(mem_rsp_rdata), .down_rsp_error(mem_rsp_error)
  );
endmodule
