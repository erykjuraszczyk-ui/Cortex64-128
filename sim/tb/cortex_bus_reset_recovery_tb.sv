`timescale 1ns/1ps
module cortex_bus_reset_recovery_tb;
  localparam integer NO_RESPONSE_WATCH_CYCLES = 8;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic mem_req_valid, mem_req_ready, mem_req_write;
  logic [63:0] mem_req_addr, mem_req_wdata;
  logic [7:0] mem_req_wstrb;
  logic mem_rsp_valid, mem_rsp_ready, mem_rsp_error;
  logic [63:0] mem_rsp_rdata;
  logic halted, fault;
  logic [7:0] fault_code;
  logic [63:0] pc_debug, instret;

  logic [7:0] mem [0:4095];
  logic mem_busy;
  logic pending_write;
  logic [63:0] pending_addr, pending_wdata;
  logic [7:0] pending_wstrb;
  integer response_delay_q;
  integer ready_delay_q;
  integer k, init_i;

  // The first accepted request is intentionally never answered. The test
  // asserts reset, which resets the requester and target together, then runs
  // the same program with normal responses. This prototype has no RTL bus
  // timeout; NO_RESPONSE_WATCH_CYCLES is a testbench watchdog interval.
  logic suppress_responses = 1'b1;
  logic recovery_epoch = 1'b0;

  integer accepted_total = 0;
  integer responses_total = 0;
  integer aborted_total = 0;
  integer accepted_recovery = 0;
  integer responses_recovery = 0;
  logic outstanding_monitor = 1'b0;

  logic request_stalled_q = 1'b0;
  logic [63:0] stalled_addr_q = 64'd0, stalled_wdata_q = 64'd0;
  logic stalled_write_q = 1'b0;
  logic [7:0] stalled_wstrb_q = 8'd0;
  integer recovery_stall_cycles = 0;

  assign mem_req_ready = !mem_busy && !mem_rsp_valid && (ready_delay_q == 0);

  cortex_core dut (
    .clk(clk), .rst_n(rst_n),
    .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
    .mem_req_addr(mem_req_addr), .mem_req_write(mem_req_write),
    .mem_req_wdata(mem_req_wdata), .mem_req_wstrb(mem_req_wstrb),
    .mem_rsp_valid(mem_rsp_valid), .mem_rsp_ready(mem_rsp_ready),
    .mem_rsp_rdata(mem_rsp_rdata), .mem_rsp_error(mem_rsp_error),
    .halted(halted), .fault(fault), .fault_code(fault_code),
    .pc_debug(pc_debug), .instret(instret)
  );

  task automatic put_word(input integer addr, input logic [31:0] word_value);
    integer b;
    begin
      for (b = 0; b < 4; b = b + 1)
        mem[addr+b] = word_value[b*8 +: 8];
    end
  endtask

  initial begin
    for (init_i = 0; init_i < 4096; init_i = init_i + 1)
      mem[init_i] = 8'h00;

    // Program: store 42 at 0x100, load it back, branch around FAIL, EBREAK.
    put_word(16'h0000, 32'h1000_0093); // addi x1,x0,0x100
    put_word(16'h0004, 32'h02a0_0113); // addi x2,x0,42
    put_word(16'h0008, 32'h0020_b023); // sd x2,0(x1)
    put_word(16'h000c, 32'h0000_b183); // ld x3,0(x1)
    put_word(16'h0010, 32'h02a0_0213); // addi x4,x0,42
    put_word(16'h0014, 32'h0041_9663); // bne x3,x4,+12 -> FAIL
    put_word(16'h0018, 32'h05a0_0f93); // PASS marker x31=0x5a
    put_word(16'h001c, 32'h0010_0073); // ebreak
    put_word(16'h0020, 32'h0330_0f93); // FAIL marker x31=0x33
    put_word(16'h0024, 32'h0010_0073); // ebreak
  end

  // One-outstanding-request target. Reset clears in-flight request/response
  // state, modeling a coordinated system reset of the core and memory adapter.
  always @(posedge clk) begin
    if (!rst_n) begin
      mem_busy          <= 1'b0;
      pending_write     <= 1'b0;
      pending_addr      <= 64'd0;
      pending_wdata     <= 64'd0;
      pending_wstrb     <= 8'd0;
      response_delay_q  <= 0;
      ready_delay_q     <= 0;
      mem_rsp_valid     <= 1'b0;
      mem_rsp_rdata     <= 64'd0;
      mem_rsp_error     <= 1'b0;
    end else begin
      if (ready_delay_q > 0)
        ready_delay_q <= ready_delay_q - 1;

      if (mem_rsp_valid && mem_rsp_ready) begin
        mem_rsp_valid <= 1'b0;
        mem_busy      <= 1'b0;
        ready_delay_q <= 2;
      end else if (mem_busy && !mem_rsp_valid && !suppress_responses) begin
        if (response_delay_q > 0) begin
          response_delay_q <= response_delay_q - 1;
        end else begin
          if (pending_write) begin
            for (k = 0; k < 8; k = k + 1)
              if (pending_wstrb[k])
                mem[pending_addr[11:0] + k] <= pending_wdata[k*8 +: 8];
            mem_rsp_rdata <= 64'd0;
          end else begin
            mem_rsp_rdata <= {
              mem[pending_addr[11:0] + 12'd7], mem[pending_addr[11:0] + 12'd6],
              mem[pending_addr[11:0] + 12'd5], mem[pending_addr[11:0] + 12'd4],
              mem[pending_addr[11:0] + 12'd3], mem[pending_addr[11:0] + 12'd2],
              mem[pending_addr[11:0] + 12'd1], mem[pending_addr[11:0]]
            };
          end
          mem_rsp_error <= 1'b0;
          mem_rsp_valid <= 1'b1;
        end
      end

      if (mem_req_valid && mem_req_ready) begin
        mem_busy          <= 1'b1;
        pending_addr      <= mem_req_addr;
        pending_write     <= mem_req_write;
        pending_wdata     <= mem_req_wdata;
        pending_wstrb     <= mem_req_wstrb;
        response_delay_q  <= 2;
      end
    end
  end

  // Independent transaction ledger. An outstanding transaction removed by a
  // coordinated reset is counted as aborted, not as a completed response.
  always @(posedge clk) begin
    if (!rst_n) begin
      if (outstanding_monitor) begin
        aborted_total      <= aborted_total + 1;
        outstanding_monitor <= 1'b0;
      end
      request_stalled_q <= 1'b0;
    end else begin
      if (mem_req_valid && mem_req_ready) begin
        if (outstanding_monitor)
          $fatal(1, "more than one outstanding bus request");
        outstanding_monitor <= 1'b1;
        accepted_total <= accepted_total + 1;
        if (recovery_epoch)
          accepted_recovery <= accepted_recovery + 1;
      end

      if (mem_rsp_valid && mem_rsp_ready) begin
        if (!outstanding_monitor)
          $fatal(1, "unsolicited or duplicate response");
        outstanding_monitor <= 1'b0;
        responses_total <= responses_total + 1;
        if (recovery_epoch)
          responses_recovery <= responses_recovery + 1;
      end

      if (request_stalled_q) begin
        if (mem_req_valid !== 1'b1 || mem_req_addr !== stalled_addr_q ||
            mem_req_write !== stalled_write_q || mem_req_wdata !== stalled_wdata_q ||
            mem_req_wstrb !== stalled_wstrb_q)
          $fatal(1, "request payload changed while stalled at PC=%h", pc_debug);
        if (mem_req_ready)
          request_stalled_q <= 1'b0;
      end else if (mem_req_valid && !mem_req_ready) begin
        request_stalled_q <= 1'b1;
        stalled_addr_q    <= mem_req_addr;
        stalled_write_q   <= mem_req_write;
        stalled_wdata_q   <= mem_req_wdata;
        stalled_wstrb_q   <= mem_req_wstrb;
      end

      if (recovery_epoch && mem_req_valid && !mem_req_ready)
        recovery_stall_cycles <= recovery_stall_cycles + 1;
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Wait for the first accepted request, then prove the target withholds a
    // response for the watchdog interval while the CPU waits in FETCH_WAIT.
    wait (accepted_total == 1);
    repeat (NO_RESPONSE_WATCH_CYCLES) begin
      @(posedge clk);
      #1;
      if (mem_rsp_valid !== 1'b0)
        $fatal(1, "response unexpectedly arrived while no-response injection was active");
      if (halted)
        $fatal(1, "CPU halted despite outstanding fetch with no response");
    end
    if (mem_busy !== 1'b1 || outstanding_monitor !== 1'b1)
      $fatal(1, "expected one outstanding transaction before reset");

    // Reset requester and target together to abort the stuck transaction.
    @(negedge clk);
    rst_n = 1'b0;
    recovery_epoch = 1'b0;
    suppress_responses = 1'b0;
    repeat (3) @(posedge clk);
    #1;
    if (aborted_total != 1)
      $fatal(1, "expected exactly one transaction aborted by reset, got %0d", aborted_total);
    if (responses_total != 0)
      $fatal(1, "the deliberately suppressed transaction must not produce a response");

    @(negedge clk);
    recovery_epoch = 1'b1;
    rst_n = 1'b1;

    wait (halted == 1'b1);
    #1;
    if (fault !== 1'b0)
      $fatal(1, "unexpected CPU fault code=%0d pc=%h", fault_code, pc_debug);
    if (dut.regs[1] !== 64'h100)
      $fatal(1, "x1 expected 0x100, got %h", dut.regs[1]);
    if (dut.regs[2] !== 64'd42)
      $fatal(1, "x2 expected 42, got %h", dut.regs[2]);
    if (dut.regs[3] !== 64'd42)
      $fatal(1, "x3 load-back expected 42, got %h", dut.regs[3]);
    if (dut.regs[31] !== 64'h5a)
      $fatal(1, "FAIL path reached after reset recovery; x31=%h", dut.regs[31]);
    if (mem[256] !== 8'd42)
      $fatal(1, "store not committed after recovery: mem[0x100]=%h", mem[256]);
    if (accepted_recovery != 10)
      $fatal(1, "expected 10 accepted requests after reset, got %0d", accepted_recovery);
    if (responses_recovery != accepted_recovery)
      $fatal(1, "accepted/response mismatch after recovery: accepted=%0d responses=%0d",
             accepted_recovery, responses_recovery);
    if (accepted_total != responses_total + aborted_total)
      $fatal(1, "transaction ledger mismatch: accepted=%0d responses=%0d aborted=%0d",
             accepted_total, responses_total, aborted_total);
    if (outstanding_monitor || mem_busy || mem_rsp_valid)
      $fatal(1, "transaction still outstanding at completion");
    if (recovery_stall_cycles < 5)
      $fatal(1, "backpressure was not exercised after reset: %0d cycles", recovery_stall_cycles);

    $display("PASS: no-response watchdog window, reset abort/recovery, one response per accepted request; accepted=%0d responses=%0d aborted=%0d recovery=%0d instret=%0d",
             accepted_total, responses_total, aborted_total, accepted_recovery, instret);
    $finish;
  end

  initial begin
    repeat (5000) @(posedge clk);
    $fatal(1, "TIMEOUT: reset recovery test did not complete; pc=%h", pc_debug);
  end
endmodule
