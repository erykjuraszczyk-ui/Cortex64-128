`timescale 1ns/1ps

module cortex_mem_protocol_assertions_tb;
  localparam integer TIMEOUT_CYCLES = 3;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic up_req_valid = 1'b0;
  logic up_req_ready;
  logic [63:0] up_req_addr = 64'd0;
  logic up_req_write = 1'b0;
  logic [63:0] up_req_wdata = 64'd0;
  logic [7:0] up_req_wstrb = 8'd0;
  logic up_rsp_valid;
  logic up_rsp_ready = 1'b0;
  logic [63:0] up_rsp_rdata;
  logic up_rsp_error;

  logic down_req_valid;
  logic down_req_ready = 1'b0;
  logic [63:0] down_req_addr, down_req_wdata;
  logic down_req_write;
  logic [7:0] down_req_wstrb;
  logic down_rsp_valid = 1'b0;
  logic down_rsp_ready;
  logic [63:0] down_rsp_rdata = 64'd0;
  logic down_rsp_error = 1'b0;
  integer accepted_count = 0;
  integer target_rsp_count = 0;
  integer upstream_rsp_count = 0;

  cortex_mem_timeout_adapter #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut (
    .clk(clk), .rst_n(rst_n),
    .up_req_valid(up_req_valid), .up_req_ready(up_req_ready),
    .up_req_addr(up_req_addr), .up_req_write(up_req_write),
    .up_req_wdata(up_req_wdata), .up_req_wstrb(up_req_wstrb),
    .up_rsp_valid(up_rsp_valid), .up_rsp_ready(up_rsp_ready),
    .up_rsp_rdata(up_rsp_rdata), .up_rsp_error(up_rsp_error),
    .down_req_valid(down_req_valid), .down_req_ready(down_req_ready),
    .down_req_addr(down_req_addr), .down_req_write(down_req_write),
    .down_req_wdata(down_req_wdata), .down_req_wstrb(down_req_wstrb),
    .down_rsp_valid(down_rsp_valid), .down_rsp_ready(down_rsp_ready),
    .down_rsp_rdata(down_rsp_rdata), .down_rsp_error(down_rsp_error)
  );

  cortex_mem_protocol_assertions u_protocol_assertions (
    .clk(clk), .rst_n(rst_n),
    .up_req_valid(up_req_valid), .up_req_ready(up_req_ready),
    .up_req_addr(up_req_addr), .up_req_write(up_req_write),
    .up_req_wdata(up_req_wdata), .up_req_wstrb(up_req_wstrb),
    .up_rsp_valid(up_rsp_valid), .up_rsp_ready(up_rsp_ready),
    .up_rsp_rdata(up_rsp_rdata), .up_rsp_error(up_rsp_error),
    .down_req_valid(down_req_valid), .down_req_ready(down_req_ready),
    .down_req_addr(down_req_addr), .down_req_write(down_req_write),
    .down_req_wdata(down_req_wdata), .down_req_wstrb(down_req_wstrb),
    .down_rsp_valid(down_rsp_valid), .down_rsp_ready(down_rsp_ready),
    .down_rsp_rdata(down_rsp_rdata), .down_rsp_error(down_rsp_error)
  );

  always @(posedge clk) begin
    if (rst_n) begin
      if (down_req_valid && down_req_ready)
        accepted_count <= accepted_count + 1;
      if (down_rsp_valid && down_rsp_ready)
        target_rsp_count <= target_rsp_count + 1;
      if (up_rsp_valid && up_rsp_ready)
        upstream_rsp_count <= upstream_rsp_count + 1;
    end
  end

  task automatic issue_request(input logic [63:0] addr);
    begin
      @(negedge clk);
      up_req_addr = addr;
      up_req_write = 1'b0;
      up_req_wdata = 64'd0;
      up_req_wstrb = 8'd0;
      up_req_valid = 1'b1;
      do @(posedge clk); while (!(up_req_valid && up_req_ready));
      @(negedge clk);
      up_req_valid = 1'b0;
    end
  endtask

  task automatic accept_downstream;
    begin
      do @(posedge clk); while (!(down_req_valid && down_req_ready));
      @(negedge clk);
    end
  endtask

  task automatic consume_response;
    begin
      @(negedge clk);
      up_rsp_ready = 1'b1;
      do @(posedge clk); while (!(up_rsp_valid && up_rsp_ready));
      @(negedge clk);
      up_rsp_ready = 1'b0;
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Request-accept timeout reports an error but may not withdraw VALID.
    issue_request(64'h80);
    wait (up_rsp_valid === 1'b1);
    #1;
    if (up_rsp_error !== 1'b1 || down_req_valid !== 1'b1 || down_req_addr !== 64'h80)
      $fatal(1, "timeout must report error while retaining stalled request");
    repeat (2) begin
      @(posedge clk); #1;
      if (!up_rsp_valid || !up_rsp_error || !down_req_valid || down_req_addr !== 64'h80)
        $fatal(1, "request/timeout response changed under backpressure");
    end
    consume_response();
    if (up_req_ready !== 1'b0 || down_req_valid !== 1'b1)
      $fatal(1, "quarantine did not retain old request and block reuse");

    // Target eventually accepts the timed-out request; the now-stale response
    // is consumed and discarded before a new transaction can begin.
    down_req_ready = 1'b1;
    accept_downstream();
    down_req_ready = 1'b0;
    @(negedge clk);
    down_rsp_rdata = 64'hBAD0_0080;
    down_rsp_error = 1'b0;
    down_rsp_valid = 1'b1;
    @(posedge clk); #1;
    @(negedge clk);
    down_rsp_valid = 1'b0;
    if (up_req_ready !== 1'b1)
      $fatal(1, "adapter failed to leave quarantine after stale response drain");

    // Normal transaction with requester backpressure; assertion checker verifies
    // one-to-one request/response accounting and stable output payload.
    down_req_ready = 1'b1;
    issue_request(64'h88);
    accept_downstream();
    down_req_ready = 1'b0;
    repeat (1) @(posedge clk);
    @(negedge clk);
    down_rsp_rdata = 64'h1234_5678_9ABC_DEF0;
    down_rsp_error = 1'b0;
    down_rsp_valid = 1'b1;
    @(posedge clk); #1;
    if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b0 ||
        up_rsp_rdata !== 64'h1234_5678_9ABC_DEF0)
      $fatal(1, "normal response not captured");
    @(negedge clk);
    down_rsp_valid = 1'b0;
    repeat (2) begin
      @(posedge clk); #1;
      if (!up_rsp_valid || up_rsp_error || up_rsp_rdata !== 64'h1234_5678_9ABC_DEF0)
        $fatal(1, "normal response changed while upstream stalled");
    end
    consume_response();

    if (accepted_count != 2 || target_rsp_count != 2 || upstream_rsp_count != 2)
      $fatal(1, "ledger mismatch: target accepts=%0d target responses=%0d upstream responses=%0d",
             accepted_count, target_rsp_count, upstream_rsp_count);

    $display("PASS: protocol assertions (VALID stability, payload stability, single-outstanding ledgers), timed-out request retained, stale response drained");
    $finish;
  end

  initial begin
    repeat (500) @(posedge clk);
    $fatal(1, "TIMEOUT: protocol assertions bench did not complete");
  end
endmodule
