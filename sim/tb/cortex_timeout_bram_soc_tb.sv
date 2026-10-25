`timescale 1ns/1ps
module cortex_timeout_bram_soc_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic halted, fault;
  logic [7:0] fault_code;
  logic [63:0] pc_debug, instret;
  integer target_accept_count = 0;
  integer target_response_count = 0;
  integer cpu_request_count = 0;
  integer cpu_response_count = 0;

  always #5 clk = ~clk;

  cortex_timeout_bram_soc #(
    .RESET_PC(64'h0),
    .MEM_BASE_ADDR(64'h0),
    .MEM_WORDS(512),
    .INIT_FILE("sim/programs/smoke_test.hex"),
    .TIMEOUT_CYCLES(64)
  ) dut (
    .clk(clk), .rst_n(rst_n), .halted(halted), .fault(fault),
    .fault_code(fault_code), .pc_debug(pc_debug), .instret(instret)
  );

  // Independent transaction ledgers catch lost or duplicate bus completions.
  always @(posedge clk) begin
    if (rst_n) begin
      if (dut.mem_req_valid && dut.mem_req_ready)
        target_accept_count <= target_accept_count + 1;
      if (dut.mem_rsp_valid && dut.mem_rsp_ready)
        target_response_count <= target_response_count + 1;
      if (dut.u_top.cpu_req_valid && dut.u_top.cpu_req_ready)
        cpu_request_count <= cpu_request_count + 1;
      if (dut.u_top.cpu_rsp_valid && dut.u_top.cpu_rsp_ready)
        cpu_response_count <= cpu_response_count + 1;
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    wait ((halted === 1'b1) || (fault === 1'b1));
    #1;
    if (fault !== 1'b0)
      $fatal(1, "CPU fault=%0d pc=%h", fault_code, pc_debug);
    if (halted !== 1'b1)
      $fatal(1, "CPU failed to halt cleanly");

    if (dut.u_top.u_core.regs[1] !== 64'd5)
      $fatal(1, "x1 mismatch: %h", dut.u_top.u_core.regs[1]);
    if (dut.u_top.u_core.regs[2] !== 64'd7)
      $fatal(1, "x2 mismatch: %h", dut.u_top.u_core.regs[2]);
    if (dut.u_top.u_core.regs[3] !== 64'd12)
      $fatal(1, "x3 mismatch: %h", dut.u_top.u_core.regs[3]);
    if (dut.u_top.u_core.regs[7] !== 64'd12)
      $fatal(1, "LD mismatch: %h", dut.u_top.u_core.regs[7]);
    if (dut.u_top.u_core.regs[31] !== 64'h5a)
      $fatal(1, "Smoke test failure path reached, x31=%h", dut.u_top.u_core.regs[31]);
    if (dut.u_mem.mem[32] !== 64'd12)
      $fatal(1, "SD did not update memory word 32: %h", dut.u_mem.mem[32]);

    if (target_accept_count == 0 || target_accept_count != target_response_count)
      $fatal(1, "target transaction ledger mismatch: accepts=%0d responses=%0d",
             target_accept_count, target_response_count);
    if (cpu_request_count == 0 || cpu_request_count != cpu_response_count)
      $fatal(1, "CPU transaction ledger mismatch: requests=%0d responses=%0d",
             cpu_request_count, cpu_response_count);

    $display("PASS: Cortex64/128 timeout-adapter + BRAM integration; instret=%0d target=%0d/%0d cpu=%0d/%0d",
             instret, target_accept_count, target_response_count,
             cpu_request_count, cpu_response_count);
    $finish;
  end

  initial begin
    repeat (20000) @(posedge clk);
    $fatal(1, "TIMEOUT: timeout-adapter + BRAM integration did not halt; pc=%h", pc_debug);
  end
endmodule
