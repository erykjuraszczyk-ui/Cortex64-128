`timescale 1ns/1ps
module cortex_core_tb;
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
  integer i, k;

  assign mem_req_ready = !mem_busy && !mem_rsp_valid;

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
    for (i = 0; i < 4096; i = i + 1) mem[i] = 8'h00;
    // PASS path: x3 = 5 + 7 = 12; store/load 12; x31 = 0x5a.
    // Any failed branch jumps to the FAIL path where x31 becomes 0x33.
    put_word( 0, 32'h0050_0093); // addi x1,x0,5
    put_word( 4, 32'h0070_0113); // addi x2,x0,7
    put_word( 8, 32'h0020_81b3); // add  x3,x1,x2
    put_word(12, 32'h00c0_0213); // addi x4,x0,12
    put_word(16, 32'h0041_9e63); // bne x3,x4,+28 -> FAIL at 44
    put_word(20, 32'h1000_0313); // addi x6,x0,0x100
    put_word(24, 32'h0033_3023); // sd x3,0(x6)
    put_word(28, 32'h0003_3383); // ld x7,0(x6)
    put_word(32, 32'h0033_9663); // bne x7,x3,+12 -> FAIL at 44
    put_word(36, 32'h05a0_0f93); // addi x31,x0,0x5a (PASS)
    put_word(40, 32'h0010_0073); // ebreak
    put_word(44, 32'h0330_0f93); // addi x31,x0,0x33 (FAIL)
    put_word(48, 32'h0010_0073); // ebreak

    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
  end

  // One outstanding transaction, one-cycle response latency. This model uses
  // an aligned 64-bit little-endian data word and byte write strobes.
  always @(posedge clk) begin
    if (!rst_n) begin
      mem_busy      <= 1'b0;
      pending_write <= 1'b0;
      pending_addr  <= 64'd0;
      pending_wdata <= 64'd0;
      pending_wstrb <= 8'd0;
      mem_rsp_valid <= 1'b0;
      mem_rsp_rdata <= 64'd0;
      mem_rsp_error <= 1'b0;
    end else begin
      if (mem_rsp_valid && mem_rsp_ready)
        mem_rsp_valid <= 1'b0;

      if (mem_busy) begin
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
        mem_busy <= 1'b0;
      end

      if (mem_req_valid && mem_req_ready) begin
        pending_addr  <= mem_req_addr;
        pending_write <= mem_req_write;
        pending_wdata <= mem_req_wdata;
        pending_wstrb <= mem_req_wstrb;
        mem_busy      <= 1'b1;
      end
    end
  end

  initial begin
    wait(rst_n == 1'b1);
    wait(halted == 1'b1);
    #1;
    if (fault !== 1'b0) $fatal(1, "CPU fault code=%0d pc=%h", fault_code, pc_debug);
    if (dut.regs[1] !== 64'd5)  $fatal(1, "x1 expected 5, got %h", dut.regs[1]);
    if (dut.regs[2] !== 64'd7)  $fatal(1, "x2 expected 7, got %h", dut.regs[2]);
    if (dut.regs[3] !== 64'd12) $fatal(1, "x3 expected 12, got %h", dut.regs[3]);
    if (dut.regs[7] !== 64'd12) $fatal(1, "x7 expected 12, got %h", dut.regs[7]);
    if (dut.regs[31] !== 64'h5a) $fatal(1, "FAIL path reached; x31=%h", dut.regs[31]);
    if (mem[256] !== 8'd12) $fatal(1, "memory write failed; mem[0x100]=%h", mem[256]);
    $display("PASS: Cortex64/128 v0.1.1 basic RV64I, branch, SD/LD test; instret=%0d", instret);
    $finish;
  end

  initial begin
    repeat (5000) @(posedge clk);
    $fatal(1, "TIMEOUT: core did not halt; pc=%h", pc_debug);
  end
endmodule
