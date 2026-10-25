`timescale 1ns/1ps

// Boundary regression for TIMEOUT_CYCLES=1. Covers the minimum legal
// timeout, response/error priority at the boundary, response stability under
// upstream backpressure, and reset while a response is being held.
module cortex_mem_timeout_min_tb;
  localparam integer TIMEOUT_CYCLES = 1;

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

  integer target_accept_count = 0;
  integer target_response_count = 0;
  integer upstream_response_count = 0;

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

  // Testbench ledger. Reset does not erase historical counters.
  always @(posedge clk) begin
    if (rst_n) begin
      if (down_req_valid && down_req_ready)
        target_accept_count <= target_accept_count + 1;
      if (down_rsp_valid && down_rsp_ready)
        target_response_count <= target_response_count + 1;
      if (up_rsp_valid && up_rsp_ready)
        upstream_response_count <= upstream_response_count + 1;
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

  task automatic wait_downstream_accept;
    begin
      do @(posedge clk); while (!(down_req_valid && down_req_ready));
      @(negedge clk);
    end
  endtask

  task automatic consume_upstream_response;
    begin
      @(negedge clk);
      up_rsp_ready = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      up_rsp_ready = 1'b0;
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Case 1: the minimum timeout is legal and bounded. The target never
    // accepts the request; exactly one held error response must be produced.
    down_req_ready = 1'b0;
    issue_request(64'h1000);
    wait (up_rsp_valid === 1'b1);
    #1;
    if (up_rsp_error !== 1'b1 || up_rsp_rdata !== 64'd0)
      $fatal(1, "TIMEOUT_CYCLES=1 request timeout must return zero data/error");
    repeat (3) begin
      @(posedge clk); #1;
      if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b1 || up_rsp_rdata !== 64'd0)
        $fatal(1, "minimum-timeout response changed while upstream was stalled");
    end
    consume_upstream_response();
    if (down_req_valid !== 1'b1 || up_req_ready !== 1'b0)
      $fatal(1, "timed-out downstream request must remain asserted and block reuse");

    // Since the target never becomes ready, a coordinated reset is the only
    // safe cancellation mechanism for the still-unaccepted ready/valid request.
    @(negedge clk);
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    if (down_req_valid !== 1'b0 || up_req_ready !== 1'b1)
      $fatal(1, "coordinated reset did not clear stalled downstream request");
    @(negedge clk);
    rst_n = 1'b1;

    // Case 2: an error response arriving in the first response-wait cycle
    // wins over the minimum timeout and is propagated verbatim. Hold the
    // response upstream to exercise backpressure on error data as well as flag.
    down_req_ready = 1'b1;
    issue_request(64'h1008);
    wait_downstream_accept();
    down_req_ready = 1'b0;
    down_rsp_rdata = 64'hBAD0_E002_BAD0_E002;
    down_rsp_error = 1'b1;
    down_rsp_valid = 1'b1;
    @(posedge clk); #1;
    if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b1 ||
        up_rsp_rdata !== 64'hBAD0_E002_BAD0_E002)
      $fatal(1, "target error on minimum-timeout boundary was not propagated");
    @(negedge clk);
    down_rsp_valid = 1'b0;
    repeat (3) begin
      @(posedge clk); #1;
      if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b1 ||
          up_rsp_rdata !== 64'hBAD0_E002_BAD0_E002)
        $fatal(1, "target error response was not stable under upstream backpressure");
    end
    consume_upstream_response();

    // Case 3: a successful downstream response is held upstream, then a
    // coordinated reset clears the held response and returns the adapter idle.
    down_req_ready = 1'b1;
    issue_request(64'h1010);
    wait_downstream_accept();
    down_req_ready = 1'b0;
    down_rsp_rdata = 64'h1234_5678_ABCD_EF01;
    down_rsp_error = 1'b0;
    down_rsp_valid = 1'b1;
    @(posedge clk); #1;
    if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b0 ||
        up_rsp_rdata !== 64'h1234_5678_ABCD_EF01)
      $fatal(1, "normal response not captured before reset-held-response case");
    @(negedge clk);
    down_rsp_valid = 1'b0;
    repeat (2) begin
      @(posedge clk); #1;
      if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b0 ||
          up_rsp_rdata !== 64'h1234_5678_ABCD_EF01)
        $fatal(1, "normal response changed while held before reset");
    end
    @(negedge clk);
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    if (up_rsp_valid !== 1'b0 || up_req_ready !== 1'b1 || down_req_valid !== 1'b0)
      $fatal(1, "reset did not clear held response and return adapter to idle");

    if (target_accept_count != 2 || target_response_count != 2)
      $fatal(1, "target ledger mismatch at reset: accepts=%0d responses=%0d",
             target_accept_count, target_response_count);
    if (upstream_response_count != 2)
      $fatal(1, "upstream ledger mismatch: expected two consumed responses, got %0d",
             upstream_response_count);

    $display("PASS: TIMEOUT_CYCLES=1, boundary error propagation, held-response stability and reset clearing");
    $finish;
  end

  initial begin
    repeat (300) @(posedge clk);
    $fatal(1, "TIMEOUT: minimum-timeout boundary test did not complete");
  end
endmodule
