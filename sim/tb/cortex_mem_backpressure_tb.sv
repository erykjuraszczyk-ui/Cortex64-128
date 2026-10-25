`timescale 1ns/1ps
module cortex_mem_backpressure_tb;
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
  integer accepted_count;
  integer writes_accepted;
  integer request_stall_cycles;
  integer response_delay_cycles;
  integer init_i, k;

  logic request_stalled_q;
  logic [63:0] stalled_addr_q, stalled_wdata_q;
  logic stalled_write_q;
  logic [7:0] stalled_wstrb_q;

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

    // Program: store 42 to 0x100, load it back and check it. The BNE
    // target is the failure marker at 0x20; success halts at 0x1c.
    put_word(16'h0000, 32'h1000_0093); // addi x1,x0,0x100
    put_word(16'h0004, 32'h02a0_0113); // addi x2,x0,42
    put_word(16'h0008, 32'h0020_b023); // sd   x2,0(x1)
    put_word(16'h000c, 32'h0000_b183); // ld   x3,0(x1)
    put_word(16'h0010, 32'h02a0_0213); // addi x4,x0,42
    put_word(16'h0014, 32'h0041_9663); // bne  x3,x4,+12 -> FAIL
    put_word(16'h0018, 32'h05a0_0f93); // addi x31,x0,0x5a (PASS)
    put_word(16'h001c, 32'h0010_0073); // ebreak
    put_word(16'h0020, 32'h0330_0f93); // addi x31,x0,0x33 (FAIL)
    put_word(16'h0024, 32'h0010_0073); // ebreak
  end

  // A deterministic target deliberately stalls request acceptance and delays
  // every response. It supports one outstanding transaction and holds each
  // response until the requester accepts it.
  always @(posedge clk) begin
    if (!rst_n) begin
      mem_busy             <= 1'b0;
      pending_write        <= 1'b0;
      pending_addr         <= 64'd0;
      pending_wdata        <= 64'd0;
      pending_wstrb        <= 8'd0;
      response_delay_q     <= 0;
      ready_delay_q        <= 0;
      mem_rsp_valid        <= 1'b0;
      mem_rsp_rdata        <= 64'd0;
      mem_rsp_error        <= 1'b0;
      accepted_count       <= 0;
      writes_accepted      <= 0;
      request_stall_cycles <= 0;
      response_delay_cycles <= 0;
    end else begin
      if (ready_delay_q > 0)
        ready_delay_q <= ready_delay_q - 1;

      if (mem_rsp_valid && mem_rsp_ready) begin
        mem_rsp_valid <= 1'b0;
        mem_busy      <= 1'b0;
        ready_delay_q <= 2 + (accepted_count % 3);
      end else if (mem_busy && !mem_rsp_valid) begin
        response_delay_cycles <= response_delay_cycles + 1;
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
        mem_busy        <= 1'b1;
        pending_addr    <= mem_req_addr;
        pending_write   <= mem_req_write;
        pending_wdata   <= mem_req_wdata;
        pending_wstrb   <= mem_req_wstrb;
        response_delay_q <= 2 + (accepted_count % 4);
        accepted_count  <= accepted_count + 1;
        if (mem_req_write)
          writes_accepted <= writes_accepted + 1;
      end

      if (mem_req_valid && !mem_req_ready)
        request_stall_cycles <= request_stall_cycles + 1;
    end
  end

  // Protocol assertion: after a request is stalled, VALID and all payload
  // fields must remain unchanged until the target accepts that request.
  always @(posedge clk) begin
    if (!rst_n) begin
      request_stalled_q <= 1'b0;
      stalled_addr_q    <= 64'd0;
      stalled_wdata_q   <= 64'd0;
      stalled_write_q   <= 1'b0;
      stalled_wstrb_q   <= 8'd0;
    end else begin
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
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    wait(halted == 1'b1);
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
      $fatal(1, "FAIL path reached; x31=%h", dut.regs[31]);
    if (mem[256] !== 8'd42)
      $fatal(1, "store not committed: mem[0x100]=%h", mem[256]);
    if (accepted_count != 10)
      $fatal(1, "expected 10 accepted bus requests, got %0d", accepted_count);
    if (writes_accepted != 1)
      $fatal(1, "expected one write request, got %0d", writes_accepted);
    if (request_stall_cycles < 10)
      $fatal(1, "backpressure not sufficiently exercised: %0d cycles", request_stall_cycles);
    if (response_delay_cycles < 20)
      $fatal(1, "response latency not sufficiently exercised: %0d cycles", response_delay_cycles);

    $display("PASS: request stability under backpressure; delayed responses; accepted=%0d stalls=%0d response-wait=%0d instret=%0d",
             accepted_count, request_stall_cycles, response_delay_cycles, instret);
    $finish;
  end

  initial begin
    repeat (5000) @(posedge clk);
    $fatal(1, "TIMEOUT: core did not halt; pc=%h", pc_debug);
  end
endmodule
