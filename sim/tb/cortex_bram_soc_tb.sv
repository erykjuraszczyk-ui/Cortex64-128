`timescale 1ns/1ps
module cortex_bram_soc_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic halted, fault;
  logic [7:0] fault_code;
  logic [63:0] pc_debug, instret;

  always #5 clk = ~clk;

  cortex_bram_soc #(
    .RESET_PC(64'h0),
    .MEM_BASE_ADDR(64'h0),
    .MEM_WORDS(512),
    .INIT_FILE("sim/programs/smoke_test.hex")
  ) dut (
    .clk(clk), .rst_n(rst_n), .halted(halted), .fault(fault),
    .fault_code(fault_code), .pc_debug(pc_debug), .instret(instret)
  );

  initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    wait (halted === 1'b1);
    #1;
    if (fault !== 1'b0)
      $fatal(1, "CPU fault=%0d pc=%h", fault_code, pc_debug);
    if (dut.u_core.regs[1]  !== 64'd5) $fatal(1, "x1 mismatch: %h", dut.u_core.regs[1]);
    if (dut.u_core.regs[2]  !== 64'd7) $fatal(1, "x2 mismatch: %h", dut.u_core.regs[2]);
    if (dut.u_core.regs[3]  !== 64'd12) $fatal(1, "x3 mismatch: %h", dut.u_core.regs[3]);
    if (dut.u_core.regs[7]  !== 64'd12) $fatal(1, "LD mismatch: %h", dut.u_core.regs[7]);
    if (dut.u_core.regs[8]  !== 64'hffff_ffff_ffff_ff80) $fatal(1, "x8 mismatch: %h", dut.u_core.regs[8]);
    if (dut.u_core.regs[9]  !== 64'hffff_ffff_ffff_ff80) $fatal(1, "LB sign extension mismatch: %h", dut.u_core.regs[9]);
    if (dut.u_core.regs[10] !== 64'd128) $fatal(1, "LBU zero extension mismatch: %h", dut.u_core.regs[10]);
    if (dut.u_core.regs[11] !== 64'hffff_ffff_ffff_ff80) $fatal(1, "LH sign extension mismatch: %h", dut.u_core.regs[11]);
    if (dut.u_core.regs[12] !== 64'h0000_0000_0000_ff80) $fatal(1, "LHU zero extension mismatch: %h", dut.u_core.regs[12]);
    if (dut.u_core.regs[13] !== 64'hffff_ffff_8000_0000) $fatal(1, "LUI sign extension mismatch: %h", dut.u_core.regs[13]);
    if (dut.u_core.regs[14] !== 64'hffff_ffff_8000_0000) $fatal(1, "LW sign extension mismatch: %h", dut.u_core.regs[14]);
    if (dut.u_core.regs[15] !== 64'h0000_0000_8000_0000) $fatal(1, "LWU zero extension mismatch: %h", dut.u_core.regs[15]);
    if (dut.u_core.regs[17] !== 64'h0000_0000_0000_ff80) $fatal(1, "LHU reference mismatch: %h", dut.u_core.regs[17]);
    if (dut.u_core.regs[18] !== 64'h0000_0000_8000_0000) $fatal(1, "SLLI mismatch: %h", dut.u_core.regs[18]);
    if (dut.u_core.regs[31] !== 64'h5a) $fatal(1, "Failure path reached, x31=%h", dut.u_core.regs[31]);
    if (dut.u_mem.mem[32] !== 64'd12) $fatal(1, "SD did not update memory word 32: %h", dut.u_mem.mem[32]);

    $display("PASS: Cortex64/128 v0.1.2 CPU + BRAM integration; instret=%0d", instret);
    $finish;
  end

  initial begin
    repeat (10000) @(posedge clk);
    $fatal(1, "TIMEOUT: core did not halt; pc=%h", pc_debug);
  end
endmodule
