interface cortex_mem_if #(parameter int ADDR_W = 64, DATA_W = 64) (input logic clk);
  localparam int STRB_W = DATA_W / 8;

  logic                 req_valid;
  logic                 req_ready;
  logic [ADDR_W-1:0]    req_addr;
  logic                 req_write;
  logic [DATA_W-1:0]    req_wdata;
  logic [STRB_W-1:0]    req_wstrb;

  logic                 rsp_valid;
  logic                 rsp_ready;
  logic [DATA_W-1:0]    rsp_rdata;
  logic                 rsp_error;

  // Requester drives request; target drives req_ready and response.
  modport requester (
    output req_valid, req_addr, req_write, req_wdata, req_wstrb, rsp_ready,
    input  req_ready, rsp_valid, rsp_rdata, rsp_error
  );

  modport target (
    input  req_valid, req_addr, req_write, req_wdata, req_wstrb, rsp_ready,
    output req_ready, rsp_valid, rsp_rdata, rsp_error
  );
endinterface
