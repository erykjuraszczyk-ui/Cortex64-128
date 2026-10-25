// Cortex64/128 portable single-port BRAM/scratchpad target.
// Generic RTL only: final block-RAM mapping and INIT_FILE support are FPGA-tool dependent.
module cortex_bram_mem #(
  parameter logic [63:0] BASE_ADDR = 64'h0000_0000_0000_0000,
  parameter integer WORDS = 512,
  parameter INIT_FILE = ""
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic [63:0] req_addr,
  input  logic        req_write,
  input  logic [63:0] req_wdata,
  input  logic [7:0]  req_wstrb,
  output logic        rsp_valid,
  input  logic        rsp_ready,
  output logic [63:0] rsp_rdata,
  output logic        rsp_error
);
  localparam logic [63:0] MEM_BYTES = WORDS * 64'd8;
  localparam integer INDEX_BITS = (WORDS < 2) ? 1 : $clog2(WORDS);
  logic [63:0] mem [0:WORDS-1];
  logic [63:0] offset_addr;
  logic [INDEX_BITS-1:0] word_index;
  assign offset_addr = req_addr - BASE_ADDR;
  assign word_index = offset_addr[INDEX_BITS+2:3];
  integer init_i;
  integer lane;

  initial begin
    for (init_i = 0; init_i < WORDS; init_i = init_i + 1)
      mem[init_i] = 64'd0;
    if (INIT_FILE != "")
      $readmemh(INIT_FILE, mem);
  end

  // One accepted request is followed by one held response.
  assign req_ready = ~rsp_valid;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rsp_valid <= 1'b0;
      rsp_rdata <= 64'd0;
      rsp_error <= 1'b0;
    end else begin
      if (rsp_valid && rsp_ready)
        rsp_valid <= 1'b0;
      if (req_valid && req_ready) begin
        rsp_valid <= 1'b1;
        rsp_rdata <= 64'd0;
        rsp_error <= 1'b0;
        if (req_addr < BASE_ADDR) begin
          rsp_error <= 1'b1;
        end else if ((req_addr - BASE_ADDR) >= MEM_BYTES) begin
          rsp_error <= 1'b1;
        end else if (req_addr[2:0] != 3'b000) begin
          rsp_error <= 1'b1;
        end else if (req_write) begin
          for (lane = 0; lane < 8; lane = lane + 1)
            if (req_wstrb[lane])
              mem[word_index][lane*8 +: 8] <= req_wdata[lane*8 +: 8];
        end else begin
          rsp_rdata <= mem[word_index];
        end
      end
    end
  end
endmodule
