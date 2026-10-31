`timescale 1ns/1ps
module cortex_csr_trap_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk <= ~clk;

  logic mem_req_valid, mem_req_ready, mem_req_write;
  logic [63:0] mem_req_addr, mem_req_wdata;
  logic [7:0] mem_req_wstrb;
  logic mem_rsp_valid, mem_rsp_ready, mem_rsp_error;
  logic [63:0] mem_rsp_rdata;
  logic halted, fault;
  logic [7:0] fault_code;
  logic [63:0] pc_debug, instret;
  logic ecall_trap_checked = 1'b0;
  logic illegal_trap_checked = 1'b0;

  logic [7:0] mem [0:4095];
  logic mem_busy;
  logic pending_write;
  logic [63:0] pending_addr, pending_wdata;
  logic [7:0] pending_wstrb;
  integer i, k;

  assign mem_req_ready = !mem_busy && !mem_rsp_valid;

  cortex_core #(
    .RESET_PC(64'h0),
    .RESET_MTVEC(64'h100),
    .HALT_ON_EBREAK(1'b1)
  ) dut (
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

    // CSR read/write tests followed by ECALL. The first handler increments
    // mepc and returns; the resumed program then attempts a forbidden misa write.
    put_word(16'h000, 32'h0550_0093); // addi   x1,x0,0x55
    put_word(16'h004, 32'h3400_9073); // csrrw  x0,mscratch,x1
    put_word(16'h008, 32'h3400_2173); // csrrs  x2,mscratch,x0
    put_word(16'h00c, 32'h3407_d773); // csrrwi x14,mscratch,15
    put_word(16'h010, 32'h3400_b573); // csrrc  x10,mscratch,x1
    put_word(16'h014, 32'h3400_25f3); // csrrs  x11,mscratch,x0
    put_word(16'h018, 32'h0000_0073); // ecall
    put_word(16'h01c, 32'h0330_0213); // addi   x4,x0,0x33 (resume marker)
    put_word(16'h020, 32'h3010_9073); // csrrw  x0,misa,x1 -> illegal trap
    put_word(16'h024, 32'h0010_0073); // ebreak after second trap return

    // Common handler dispatches on mcause. ECALL (11) is handled at 0x10c;
    // illegal instruction (2) is handled at 0x120.
    put_word(16'h100, 32'h3420_22f3); // csrrs x5,mcause,x0
    put_word(16'h104, 32'h00b0_0493); // addi  x9,x0,11
    put_word(16'h108, 32'h0092_9c63); // bne   x5,x9,+24 -> 0x120
    put_word(16'h10c, 32'h3410_2373); // csrrs x6,mepc,x0
    put_word(16'h110, 32'h0043_0313); // addi  x6,x6,4
    put_word(16'h114, 32'h3413_1073); // csrrw x0,mepc,x6
    put_word(16'h118, 32'h3430_23f3); // csrrs x7,mtval,x0
    put_word(16'h11c, 32'h3020_0073); // mret
    put_word(16'h120, 32'h3410_2673); // csrrs x12,mepc,x0
    put_word(16'h124, 32'h3430_26f3); // csrrs x13,mtval,x0
    put_word(16'h128, 32'h0046_0613); // addi  x12,x12,4
    put_word(16'h12c, 32'h3416_1073); // csrrw x0,mepc,x12
    put_word(16'h130, 32'h3020_0073); // mret

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  end

  // One outstanding transaction with one-cycle response latency. Reads return
  // an aligned 64-bit little-endian word; writes honor individual byte strobes.
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
    wait(rst_n === 1'b1);
    wait(halted === 1'b1);
    #1;

    if (fault !== 1'b1 || fault_code !== 8'd2)
      $fatal(1, "expected final illegal-instruction diagnostic, fault=%b code=%0d", fault, fault_code);
    if (dut.regs[2] !== 64'h55) $fatal(1, "CSRRS mscratch read failed: x2=%h", dut.regs[2]);
    if (dut.regs[10] !== 64'h0f) $fatal(1, "CSRRC old-value result failed: x10=%h", dut.regs[10]);
    if (dut.regs[11] !== 64'h0a) $fatal(1, "CSRRC write result failed: x11=%h", dut.regs[11]);
    if (dut.regs[14] !== 64'h55) $fatal(1, "CSRRWI old-value result failed: x14=%h", dut.regs[14]);
    if (dut.mscratch_q !== 64'h0a) $fatal(1, "mscratch expected 0x0a after CSRRC: %h", dut.mscratch_q);
    if (dut.regs[4] !== 64'h33) $fatal(1, "program did not resume after ECALL: x4=%h", dut.regs[4]);
    if (dut.regs[6] !== 64'd28) $fatal(1, "ECALL handler mepc+4 result failed: x6=%h", dut.regs[6]);
    if (dut.regs[7] !== 64'd0) $fatal(1, "ECALL mtval should be zero: x7=%h", dut.regs[7]);
    if (dut.regs[12] !== 64'd36) $fatal(1, "illegal trap handler mepc+4 result failed: x12=%h", dut.regs[12]);
    if (dut.regs[13] !== 64'h3010_9073) $fatal(1, "illegal trap mtval capture failed: x13=%h", dut.regs[13]);
    if (dut.mepc_q !== 64'd36) $fatal(1, "MRET resume PC incorrect: mepc=%h", dut.mepc_q);
    if (dut.mcause_q !== 64'd2) $fatal(1, "mcause should retain illegal instruction code: %h", dut.mcause_q);
    if (dut.mtval_q !== 64'h3010_9073) $fatal(1, "mtval should retain illegal instruction: %h", dut.mtval_q);
    if (dut.mstatus_q !== 64'h1880) $fatal(1, "unexpected post-MRET mstatus: %h", dut.mstatus_q);
    if (!ecall_trap_checked) $fatal(1, "ECALL trap-entry monitor did not complete");
    if (!illegal_trap_checked) $fatal(1, "illegal-instruction trap-entry monitor did not complete");
    if (instret !== 64'd24) $fatal(1, "instret expected 24 retired instructions, got %0d", instret);

    $display("PASS: Cortex64/128 v0.1.4 CSR/trap path; ECALL -> handler -> MRET, illegal CSR write, instret=%0d", instret);
    $finish;
  end

  // Sample the state immediately after each trap-entry nonblocking update,
  // before the handler has a chance to rewrite mepc or return with MRET.
  initial begin
    wait(rst_n === 1'b1);
    wait((pc_debug === 64'h100) && (dut.mcause_q === 64'd11));
    #1;
    if (dut.mepc_q !== 64'd24) $fatal(1, "ECALL trap mepc mismatch: %h", dut.mepc_q);
    if (dut.mtval_q !== 64'd0) $fatal(1, "ECALL trap mtval mismatch: %h", dut.mtval_q);
    if (dut.mstatus_q !== 64'h1800) $fatal(1, "ECALL trap mstatus mismatch: %h", dut.mstatus_q);
    ecall_trap_checked = 1'b1;

    wait((pc_debug === 64'h100) && (dut.mcause_q === 64'd2));
    #1;
    if (dut.mepc_q !== 64'd32) $fatal(1, "illegal trap mepc mismatch: %h", dut.mepc_q);
    if (dut.mtval_q !== 64'h3010_9073) $fatal(1, "illegal trap mtval mismatch: %h", dut.mtval_q);
    if (dut.mstatus_q !== 64'h1800) $fatal(1, "illegal trap mstatus mismatch: %h", dut.mstatus_q);
    illegal_trap_checked = 1'b1;
  end

  initial begin
    repeat (10000) @(posedge clk);
    $fatal(1, "TIMEOUT: CSR/trap test did not halt; pc=%h", pc_debug);
  end
endmodule
