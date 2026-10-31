`timescale 1ns/1ps
module cortex_mem_fault_tb;
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

  logic [7:0] mem [0:4095];
  logic mem_busy;
  logic pending_write;
  logic [63:0] pending_addr, pending_wdata;
  logic [7:0] pending_wstrb;
  integer i, k;
  integer load_bus_errors_seen = 0;
  integer store_bus_errors_seen = 0;

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

    // Four exceptions are deliberately exercised, then resumed:
    // 1) misaligned LD at 0x101, cause 4, PC 0x004;
    // 2) bus-error LD at 0x200, cause 5, PC 0x018;
    // 3) misaligned SD at 0x201, cause 6, PC 0x02c;
    // 4) bus-error SD at 0x300, cause 7, PC 0x040.
    put_word(16'h000, 32'h1010_0093); // addi x1,x0,0x101
    put_word(16'h004, 32'h0000_b103); // ld   x2,0(x1): load address misaligned
    put_word(16'h008, 32'h0005_0a13); // addi x20,x10,0: save mcause
    put_word(16'h00c, 32'h0005_8a93); // addi x21,x11,0: save mepc
    put_word(16'h010, 32'h0006_0b13); // addi x22,x12,0: save mtval
    put_word(16'h014, 32'h2000_0093); // addi x1,x0,0x200
    put_word(16'h018, 32'h0000_b203); // ld   x4,0(x1): injected load bus error
    put_word(16'h01c, 32'h0005_0b93); // addi x23,x10,0: save mcause
    put_word(16'h020, 32'h0005_8c13); // addi x24,x11,0: save mepc
    put_word(16'h024, 32'h0006_0c93); // addi x25,x12,0: save mtval
    put_word(16'h028, 32'h2010_0093); // addi x1,x0,0x201
    put_word(16'h02c, 32'h0030_b023); // sd   x3,0(x1): store address misaligned
    put_word(16'h030, 32'h0005_0d13); // addi x26,x10,0: save mcause
    put_word(16'h034, 32'h0005_8d93); // addi x27,x11,0: save mepc
    put_word(16'h038, 32'h0006_0e13); // addi x28,x12,0: save mtval
    put_word(16'h03c, 32'h3000_0093); // addi x1,x0,0x300
    put_word(16'h040, 32'h0030_b023); // sd   x3,0(x1): injected store bus error
    put_word(16'h044, 32'h0005_0e93); // addi x29,x10,0: save mcause
    put_word(16'h048, 32'h0005_8f13); // addi x30,x11,0: save mepc
    put_word(16'h04c, 32'h0006_0993); // addi x19,x12,0: save mtval
    put_word(16'h050, 32'h05a0_0f93); // addi x31,x0,0x5a: success marker
    put_word(16'h054, 32'h0010_0073); // ebreak

    // Shared handler snapshots mcause/mepc/mtval into x10/x11/x12,
    // advances mepc by four bytes, and returns to the interrupted program.
    put_word(16'h100, 32'h3420_2573); // csrrs x10,mcause,x0
    put_word(16'h104, 32'h3410_25f3); // csrrs x11,mepc,x0
    put_word(16'h108, 32'h3430_2673); // csrrs x12,mtval,x0
    put_word(16'h10c, 32'h0045_8713); // addi x14,x11,4
    put_word(16'h110, 32'h3417_1073); // csrrw x0,mepc,x14
    put_word(16'h114, 32'h3020_0073); // mret

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  end

  // A deterministic one-outstanding memory model. Read address 0x200 and
  // write address 0x300 return rsp_error; they must not alter memory state.
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
        mem_rsp_rdata <= 64'd0;
        mem_rsp_error <= 1'b0;
        if (!pending_write && pending_addr == 64'h200) begin
          mem_rsp_error <= 1'b1;
          load_bus_errors_seen <= load_bus_errors_seen + 1;
        end else if (pending_write && pending_addr == 64'h300) begin
          mem_rsp_error <= 1'b1;
          store_bus_errors_seen <= store_bus_errors_seen + 1;
        end else if (pending_write) begin
          for (k = 0; k < 8; k = k + 1)
            if (pending_wstrb[k])
              mem[pending_addr[11:0] + k] <= pending_wdata[k*8 +: 8];
        end else begin
          mem_rsp_rdata <= {
            mem[pending_addr[11:0] + 12'd7], mem[pending_addr[11:0] + 12'd6],
            mem[pending_addr[11:0] + 12'd5], mem[pending_addr[11:0] + 12'd4],
            mem[pending_addr[11:0] + 12'd3], mem[pending_addr[11:0] + 12'd2],
            mem[pending_addr[11:0] + 12'd1], mem[pending_addr[11:0]]
          };
        end
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

    if (fault !== 1'b1 || fault_code !== 8'd7)
      $fatal(1, "expected sticky final store-access-fault diagnostic, fault=%b code=%0d", fault, fault_code);

    if (dut.regs[20] !== 64'd4 || dut.regs[21] !== 64'd4 || dut.regs[22] !== 64'h101)
      $fatal(1, "misaligned load trap mismatch: cause=%h epc=%h tval=%h", dut.regs[20], dut.regs[21], dut.regs[22]);
    if (dut.regs[23] !== 64'd5 || dut.regs[24] !== 64'h18 || dut.regs[25] !== 64'h200)
      $fatal(1, "load access fault mismatch: cause=%h epc=%h tval=%h", dut.regs[23], dut.regs[24], dut.regs[25]);
    if (dut.regs[26] !== 64'd6 || dut.regs[27] !== 64'h2c || dut.regs[28] !== 64'h201)
      $fatal(1, "misaligned store trap mismatch: cause=%h epc=%h tval=%h", dut.regs[26], dut.regs[27], dut.regs[28]);
    if (dut.regs[29] !== 64'd7 || dut.regs[30] !== 64'h40 || dut.regs[19] !== 64'h300)
      $fatal(1, "store access fault mismatch: cause=%h epc=%h tval=%h", dut.regs[29], dut.regs[30], dut.regs[19]);

    if (dut.regs[31] !== 64'h5a)
      $fatal(1, "program did not resume after all four traps; x31=%h", dut.regs[31]);
    if (dut.mcause_q !== 64'd7 || dut.mepc_q !== 64'h44 || dut.mtval_q !== 64'h300)
      $fatal(1, "final trap CSRs mismatch: mcause=%h mepc=%h mtval=%h", dut.mcause_q, dut.mepc_q, dut.mtval_q);
    if (load_bus_errors_seen != 1 || store_bus_errors_seen != 1)
      $fatal(1, "expected exactly one injected load/store bus error, saw load=%0d store=%0d", load_bus_errors_seen, store_bus_errors_seen);

    $display("PASS: Cortex64/128 v0.1.5 misaligned loads/stores and load/store access-fault recovery");
    $finish;
  end

  initial begin
    repeat (20000) @(posedge clk);
    $fatal(1, "TIMEOUT: memory-fault test did not halt; pc=%h", pc_debug);
  end
endmodule
