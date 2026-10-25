package cortex_pkg;
  parameter int unsigned XLEN = 64;
  parameter int unsigned ADDR_W = 64;
  parameter int unsigned DATA_W = 64;
  parameter int unsigned STRB_W = DATA_W / 8;

  typedef logic [ADDR_W-1:0] addr_t;
  typedef logic [DATA_W-1:0] data_t;
  typedef logic [STRB_W-1:0] strb_t;

  typedef struct packed {
    logic  valid;
    addr_t addr;
    logic  write;
    data_t wdata;
    strb_t wstrb;
  } mem_req_t;

  typedef struct packed {
    logic  valid;
    data_t rdata;
    logic  error;
  } mem_rsp_t;
endpackage
