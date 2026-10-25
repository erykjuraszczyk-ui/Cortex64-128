`timescale 1ns/1ps
module cortex_bram_mem_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req_valid = 1'b0;
  logic req_ready;
  logic [63:0] req_addr = 64'd0;
  logic req_write = 1'b0;
  logic [63:0] req_wdata = 64'd0;
  logic [7:0] req_wstrb = 8'd0;
  logic rsp_valid;
  logic rsp_ready = 1'b0;
  logic [63:0] rsp_rdata;
  logic rsp_error;
  logic [63:0] data;
  logic err;

  always #5 clk = ~clk;

  cortex_bram_mem #(
    .BASE_ADDR(64'h1000), .WORDS(8), .INIT_FILE("")
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr),
    .req_write(req_write), .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
    .rsp_rdata(rsp_rdata), .rsp_error(rsp_error)
  );

  task automatic transact(
    input logic write,
    input logic [63:0] addr,
    input logic [63:0] wdata,
    input logic [7:0] wstrb,
    output logic [63:0] rdata,
    output logic error
  );
    begin
      @(negedge clk);
      req_valid = 1'b1;
      req_write = write;
      req_addr = addr;
      req_wdata = wdata;
      req_wstrb = wstrb;
      if (req_ready !== 1'b1) $fatal(1, "Request was not ready when issued");
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      wait (rsp_valid === 1'b1);
      #1;
      rdata = rsp_rdata;
      error = rsp_error;
      rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      rsp_ready = 1'b0;
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    transact(1'b1, 64'h1008, 64'h1122_3344_5566_7788, 8'hff, data, err);
    if (err) $fatal(1, "Valid full-word write reported error");
    transact(1'b0, 64'h1008, 64'd0, 8'h00, data, err);
    if (err || data !== 64'h1122_3344_5566_7788) $fatal(1, "Readback mismatch: %h err=%b", data, err);

    transact(1'b1, 64'h1008, 64'h0000_0000_aabb_0000, 8'h0c, data, err);
    if (err) $fatal(1, "Valid partial-word write reported error");
    transact(1'b0, 64'h1008, 64'd0, 8'h00, data, err);
    if (err || data !== 64'h1122_3344_aabb_7788) $fatal(1, "Byte-strobe readback mismatch: %h err=%b", data, err);

    transact(1'b0, 64'h1100, 64'd0, 8'h00, data, err);
    if (!err) $fatal(1, "Out-of-range read did not report an error");
    transact(1'b0, 64'h1009, 64'd0, 8'h00, data, err);
    if (!err) $fatal(1, "Misaligned request did not report an error");

    $display("PASS: Cortex64/128 v0.1.2 BRAM bounds, response and byte-strobe tests");
    $finish;
  end

  initial begin
    repeat (1000) @(posedge clk);
    $fatal(1, "TIMEOUT: BRAM test did not finish");
  end
endmodule
