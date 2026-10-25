`timescale 1ns/1ps
module cortex_mem_timeout_adapter_tb;
  localparam integer TIMEOUT_CYCLES = 4;

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
  integer target_abort_count = 0;
  integer upstream_response_count = 0;
  logic target_outstanding = 1'b0;
  logic request_stalled_q = 1'b0;
  logic [63:0] stalled_addr_q, stalled_wdata_q;
  logic stalled_write_q;
  logic [7:0] stalled_wstrb_q;

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

  always @(posedge clk) begin
    if (rst_n) begin
      if (down_req_valid && down_req_ready) begin
        if (target_outstanding)
          $fatal(1, "more than one downstream request outstanding");
        target_outstanding <= 1'b1;
        target_accept_count <= target_accept_count + 1;
      end
      if (down_rsp_valid && down_rsp_ready) begin
        if (!target_outstanding)
          $fatal(1, "unsolicited or duplicate target response");
        target_outstanding <= 1'b0;
        target_response_count <= target_response_count + 1;
      end
      if (up_rsp_valid && up_rsp_ready)
        upstream_response_count <= upstream_response_count + 1;

      if (request_stalled_q) begin
        if (down_req_valid !== 1'b1) begin
          $fatal(1, "downstream VALID withdrawn before READY handshake");
        end else if (down_req_addr !== stalled_addr_q ||
                     down_req_write !== stalled_write_q || down_req_wdata !== stalled_wdata_q ||
                     down_req_wstrb !== stalled_wstrb_q) begin
          $fatal(1, "downstream request changed while waiting for req_ready");
        end else if (down_req_ready) begin
          request_stalled_q <= 1'b0;
        end
      end else if (down_req_valid && !down_req_ready) begin
        request_stalled_q <= 1'b1;
        stalled_addr_q <= down_req_addr;
        stalled_write_q <= down_req_write;
        stalled_wdata_q <= down_req_wdata;
        stalled_wstrb_q <= down_req_wstrb;
      end
    end else begin
      if (target_outstanding) begin
        target_abort_count <= target_abort_count + 1;
        target_outstanding <= 1'b0;
      end
      request_stalled_q <= 1'b0;
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
      do @(posedge clk); while (up_req_ready !== 1'b1);
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

    // Case 1: request-accept timeout. The adapter returns one error upstream,
    // but holds downstream VALID and its payload until the target finally accepts
    // the old request. Its eventual response is drained before port reuse.
    down_req_ready = 1'b0;
    issue_request(64'h100);
    wait (up_rsp_valid === 1'b1);
    #1;
    if (up_rsp_error !== 1'b1 || up_rsp_rdata !== 64'd0)
      $fatal(1, "request-accept timeout must return zero data and error=1");
    if (down_req_valid !== 1'b1 || down_req_addr !== 64'h100)
      $fatal(1, "downstream request VALID/payload must remain asserted after pre-accept timeout");
    repeat (2) begin
      @(posedge clk); #1;
      if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b1 ||
          down_req_valid !== 1'b1 || down_req_addr !== 64'h100)
        $fatal(1, "timeout response or stalled request changed under backpressure");
    end
    consume_upstream_response();
    if (up_req_ready !== 1'b0 || down_req_valid !== 1'b1)
      $fatal(1, "adapter must quarantine the not-yet-accepted downstream request");
    if (target_accept_count != 0)
      $fatal(1, "a request was counted as accepted while req_ready was low");

    // The target eventually becomes ready. The timed-out request must still be
    // accepted once, and its response must be drained as stale.
    down_req_ready = 1'b1;
    wait_downstream_accept();
    down_req_ready = 1'b0;
    @(negedge clk);
    down_rsp_rdata = 64'hDEAD_BEEF_0000_0100;
    down_rsp_error = 1'b0;
    down_rsp_valid = 1'b1;
    #1;
    if (down_rsp_ready !== 1'b1)
      $fatal(1, "adapter did not assert ready to drain response for timed-out request");
    @(posedge clk); #1;
    @(negedge clk);
    down_rsp_valid = 1'b0;
    if (up_req_ready !== 1'b1)
      $fatal(1, "adapter did not return to idle after request-timeout cleanup");

    // Case 2: target accepts the request but never responds. The timeout error
    // is delivered once; a new request is blocked until the late response drains.
    down_req_ready = 1'b1;
    issue_request(64'h108);
    wait_downstream_accept();
    down_req_ready = 1'b0;
    wait (up_rsp_valid === 1'b1);
    #1;
    if (up_rsp_error !== 1'b1 || up_rsp_rdata !== 64'd0)
      $fatal(1, "response timeout must return zero data and error=1");
    consume_upstream_response();
    repeat (2) begin
      @(posedge clk); #1;
      if (up_req_ready !== 1'b0)
        $fatal(1, "adapter accepted a new request while a late response was possible");
    end

    // The late target response is consumed and discarded in quarantine.
    @(negedge clk);
    down_rsp_rdata = 64'hDEAD_BEEF_0000_0108;
    down_rsp_error = 1'b0;
    down_rsp_valid = 1'b1;
    #1;
    if (down_rsp_ready !== 1'b1)
      $fatal(1, "adapter did not assert ready to drain a late response");
    @(posedge clk); #1;
    @(negedge clk);
    down_rsp_valid = 1'b0;
    if (up_req_ready !== 1'b1)
      $fatal(1, "adapter did not leave quarantine after late response drain");

    // Case 3: following the late response, a new request completes normally.
    down_req_ready = 1'b1;
    issue_request(64'h110);
    wait_downstream_accept();
    down_req_ready = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    down_rsp_rdata = 64'hBEEF_CAFE_1234_5678;
    down_rsp_error = 1'b0;
    down_rsp_valid = 1'b1;
    @(posedge clk); #1;
    if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b0 ||
        up_rsp_rdata !== 64'hBEEF_CAFE_1234_5678)
      $fatal(1, "normal response after quarantine was lost or corrupted");
    @(negedge clk);
    down_rsp_valid = 1'b0;
    repeat (2) begin
      @(posedge clk); #1;
      if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b0 ||
          up_rsp_rdata !== 64'hBEEF_CAFE_1234_5678)
        $fatal(1, "normal response was not held stable under upstream backpressure");
    end
    consume_upstream_response();

    // Case 4: a target response valid on the exact timeout boundary wins over
    // timeout, rather than being converted into an error or quarantined.
    down_req_ready = 1'b1;
    issue_request(64'h114);
    wait_downstream_accept();
    down_req_ready = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    down_rsp_rdata = 64'h1140_1234_ABCD_5678;
    down_rsp_error = 1'b0;
    down_rsp_valid = 1'b1;
    @(posedge clk); #1;
    if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b0 ||
        up_rsp_rdata !== 64'h1140_1234_ABCD_5678)
      $fatal(1, "response on the timeout boundary must take priority over timeout");
    @(negedge clk);
    down_rsp_valid = 1'b0;
    consume_upstream_response();

    // Case 5: another accepted transaction times out, then a coordinated
    // reset clears both adapter quarantine and the simulated target transaction.
    down_req_ready = 1'b1;
    issue_request(64'h118);
    wait_downstream_accept();
    down_req_ready = 1'b0;
    wait (up_rsp_valid === 1'b1);
    #1;
    if (up_rsp_error !== 1'b1)
      $fatal(1, "expected timeout error before coordinated-reset test");
    consume_upstream_response();
    if (up_req_ready !== 1'b0)
      $fatal(1, "expected quarantine before coordinated reset");

    @(negedge clk);
    rst_n = 1'b0;
    down_rsp_valid = 1'b0;
    down_req_ready = 1'b0;
    repeat (3) @(posedge clk);
    #1;
    if (target_abort_count != 1 || target_outstanding !== 1'b0)
      $fatal(1, "coordinated reset did not account for and clear the target transaction");
    if (up_req_ready !== 1'b1)
      $fatal(1, "reset failed to clear adapter quarantine");

    @(negedge clk);
    rst_n = 1'b1;
    down_req_ready = 1'b1;
    issue_request(64'h120);
    wait_downstream_accept();
    down_req_ready = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    down_rsp_rdata = 64'h1200_CAFE_5678_BEEF;
    down_rsp_error = 1'b0;
    down_rsp_valid = 1'b1;
    @(posedge clk); #1;
    if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b0 ||
        up_rsp_rdata !== 64'h1200_CAFE_5678_BEEF)
      $fatal(1, "transaction after coordinated reset did not complete normally");
    @(negedge clk);
    down_rsp_valid = 1'b0;
    consume_upstream_response();

    if (target_accept_count != 6)
      $fatal(1, "expected six accepted downstream requests, got %0d", target_accept_count);
    if (target_response_count != 5)
      $fatal(1, "expected two timeout-cleanup responses plus three normal target responses, got %0d", target_response_count);
    if (target_abort_count != 1)
      $fatal(1, "expected one coordinated-reset abort, got %0d", target_abort_count);
    if (target_accept_count != target_response_count + target_abort_count)
      $fatal(1, "target transaction ledger mismatch: accepted=%0d responses=%0d aborted=%0d",
             target_accept_count, target_response_count, target_abort_count);
    if (upstream_response_count != 6)
      $fatal(1, "expected exactly six upstream response handshakes, got %0d", upstream_response_count);
    if (target_outstanding !== 1'b0 || up_req_ready !== 1'b1 || up_rsp_valid !== 1'b0)
      $fatal(1, "adapter/target not idle after timeout and reset recovery tests");

    $display("PASS: ready/valid-stable request timeout, response timeout, boundary priority, late-response quarantine/drain, coordinated reset/recovery; target_accepts=%0d target_responses=%0d target_aborts=%0d upstream_responses=%0d",
             target_accept_count, target_response_count, target_abort_count, upstream_response_count);
    $finish;
  end

  initial begin
    repeat (1000) @(posedge clk);
    $fatal(1, "TIMEOUT: memory timeout adapter test did not complete");
  end
endmodule
