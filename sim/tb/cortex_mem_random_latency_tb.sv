`timescale 1ns/1ps

// Deterministic pseudo-random protocol stress test for the timeout adapter.
// The LFSR varies request acceptance gaps and target response latency, while
// the checker verifies payload stability and one accepted request/one response.
module cortex_mem_random_latency_tb;
  localparam integer TIMEOUT_CYCLES = 32;
  localparam integer TRANSACTIONS = 40;
  localparam logic [63:0] RESPONSE_XOR = 64'hD00D_CAFE_1234_5678;

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

  logic [31:0] rng_q = 32'h1ACE_B00C;
  logic target_outstanding = 1'b0;
  logic [63:0] target_addr_q = 64'd0;
  logic [5:0] response_delay_q = 6'd0;

  integer target_accept_count = 0;
  integer target_response_count = 0;
  integer upstream_request_count = 0;
  integer upstream_response_count = 0;
  integer upstream_error_count = 0;

  logic down_stall_q = 1'b0;
  logic [63:0] down_stall_addr_q, down_stall_wdata_q;
  logic down_stall_write_q;
  logic [7:0] down_stall_wstrb_q;
  logic up_stall_q = 1'b0;
  logic [63:0] up_stall_addr_q, up_stall_wdata_q;
  logic up_stall_write_q;
  logic [7:0] up_stall_wstrb_q;
  logic rsp_stall_q = 1'b0;
  logic [63:0] rsp_stall_data_q;
  logic rsp_stall_error_q;

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

  function automatic logic [31:0] lfsr_next(input logic [31:0] value);
    lfsr_next = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
  endfunction

  // Deterministic pseudo-random target: acceptance has gaps and every accepted
  // request receives a response after 1..6 cycles. Delays stay below timeout.
  always @(posedge clk) begin
    if (!rst_n) begin
      rng_q <= 32'h1ACE_B00C;
      down_req_ready <= 1'b0;
      down_rsp_valid <= 1'b0;
      down_rsp_rdata <= 64'd0;
      down_rsp_error <= 1'b0;
      target_outstanding <= 1'b0;
      target_addr_q <= 64'd0;
      response_delay_q <= 6'd0;
      target_accept_count <= 0;
      target_response_count <= 0;
    end else begin
      rng_q <= lfsr_next(rng_q);
      down_req_ready <= (rng_q[1:0] != 2'b00);

      if (down_rsp_valid && down_rsp_ready) begin
        if (!target_outstanding)
          $fatal(1, "unsolicited or duplicate randomized target response");
        down_rsp_valid <= 1'b0;
        target_outstanding <= 1'b0;
        target_response_count <= target_response_count + 1;
      end else if (target_outstanding && !down_rsp_valid) begin
        if (response_delay_q <= 1) begin
          down_rsp_valid <= 1'b1;
          down_rsp_rdata <= target_addr_q ^ RESPONSE_XOR;
          down_rsp_error <= 1'b0;
        end else begin
          response_delay_q <= response_delay_q - 1'b1;
        end
      end

      if (down_req_valid && down_req_ready) begin
        if (target_outstanding)
          $fatal(1, "adapter issued overlapping downstream transactions");
        target_outstanding <= 1'b1;
        target_addr_q <= down_req_addr;
        response_delay_q <= {2'b00, ((rng_q[5:2] % 4'd6) + 4'd1)};
        target_accept_count <= target_accept_count + 1;
      end
    end
  end

  // Protocol monitor: request payload must stay stable across every stall,
  // both upstream (test driver) and downstream (adapter to target).
  always @(posedge clk) begin
    if (!rst_n) begin
      down_stall_q <= 1'b0;
      up_stall_q <= 1'b0;
    end else begin
      if (down_stall_q) begin
        if (down_req_valid !== 1'b1 || down_req_addr !== down_stall_addr_q ||
            down_req_write !== down_stall_write_q || down_req_wdata !== down_stall_wdata_q ||
            down_req_wstrb !== down_stall_wstrb_q)
          $fatal(1, "downstream request payload changed while stalled");
        if (down_req_ready)
          down_stall_q <= 1'b0;
      end else if (down_req_valid && !down_req_ready) begin
        down_stall_q <= 1'b1;
        down_stall_addr_q <= down_req_addr;
        down_stall_write_q <= down_req_write;
        down_stall_wdata_q <= down_req_wdata;
        down_stall_wstrb_q <= down_req_wstrb;
      end

      if (up_stall_q) begin
        if (up_req_valid !== 1'b1 || up_req_addr !== up_stall_addr_q ||
            up_req_write !== up_stall_write_q || up_req_wdata !== up_stall_wdata_q ||
            up_req_wstrb !== up_stall_wstrb_q)
          $fatal(1, "upstream request payload changed while stalled");
        if (up_req_ready)
          up_stall_q <= 1'b0;
      end else if (up_req_valid && !up_req_ready) begin
        up_stall_q <= 1'b1;
        up_stall_addr_q <= up_req_addr;
        up_stall_write_q <= up_req_write;
        up_stall_wdata_q <= up_req_wdata;
        up_stall_wstrb_q <= up_req_wstrb;
      end

      if (rsp_stall_q) begin
        if (up_rsp_valid !== 1'b1 || up_rsp_rdata !== rsp_stall_data_q ||
            up_rsp_error !== rsp_stall_error_q)
          $fatal(1, "upstream response changed while stalled");
        if (up_rsp_ready)
          rsp_stall_q <= 1'b0;
      end else if (up_rsp_valid && !up_rsp_ready) begin
        rsp_stall_q <= 1'b1;
        rsp_stall_data_q <= up_rsp_rdata;
        rsp_stall_error_q <= up_rsp_error;
      end

      if (up_req_valid && up_req_ready)
        upstream_request_count <= upstream_request_count + 1;
      if (up_rsp_valid && up_rsp_ready) begin
        upstream_response_count <= upstream_response_count + 1;
        if (up_rsp_error)
          upstream_error_count <= upstream_error_count + 1;
      end
    end
  end

  task automatic send_and_check(input integer txn_id);
    logic [63:0] addr;
    logic [63:0] data;
    logic [63:0] expected_response;
    integer hold_cycles;
    begin
      addr = 64'h0000_0000_0000_1000 + (txn_id * 8);
      data = 64'hCAFE_0000_1234_0000 ^ txn_id;
      expected_response = addr ^ RESPONSE_XOR;
      hold_cycles = txn_id % 5;

      @(negedge clk);
      up_req_addr = addr;
      up_req_write = txn_id[0];
      up_req_wdata = data;
      up_req_wstrb = (txn_id[7:0] == 0) ? 8'hFF : txn_id[7:0];
      up_req_valid = 1'b1;
      do @(posedge clk); while (!(up_req_valid && up_req_ready));
      @(negedge clk);
      up_req_valid = 1'b0;

      do @(posedge clk); while (up_rsp_valid !== 1'b1);
      #1;
      if (up_rsp_error !== 1'b0 || up_rsp_rdata !== expected_response)
        $fatal(1, "transaction %0d response mismatch: error=%b data=%h expected=%h",
               txn_id, up_rsp_error, up_rsp_rdata, expected_response);

      repeat (hold_cycles) begin
        @(posedge clk);
        #1;
        if (up_rsp_valid !== 1'b1 || up_rsp_error !== 1'b0 ||
            up_rsp_rdata !== expected_response)
          $fatal(1, "transaction %0d response not held stable under backpressure", txn_id);
      end

      @(negedge clk);
      up_rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      up_rsp_ready = 1'b0;
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    for (integer i = 0; i < TRANSACTIONS; i = i + 1)
      send_and_check(i);

    repeat (3) @(posedge clk);
    #1;
    if (target_accept_count != TRANSACTIONS || target_response_count != TRANSACTIONS)
      $fatal(1, "target ledger mismatch: accepts=%0d responses=%0d expected=%0d",
             target_accept_count, target_response_count, TRANSACTIONS);
    if (upstream_request_count != TRANSACTIONS || upstream_response_count != TRANSACTIONS)
      $fatal(1, "upstream ledger mismatch: requests=%0d responses=%0d expected=%0d",
             upstream_request_count, upstream_response_count, TRANSACTIONS);
    if (upstream_error_count != 0)
      $fatal(1, "unexpected timeout/error responses: %0d", upstream_error_count);
    if (target_outstanding !== 1'b0 || down_rsp_valid !== 1'b0)
      $fatal(1, "target still has a transaction outstanding at test end");

    $display("PASS: randomized-latency adapter stress; transactions=%0d, request/response ledgers balanced",
             TRANSACTIONS);
    $finish;
  end

  initial begin
    repeat (20000) @(posedge clk);
    $fatal(1, "TIMEOUT: randomized latency stress test did not finish");
  end
endmodule
