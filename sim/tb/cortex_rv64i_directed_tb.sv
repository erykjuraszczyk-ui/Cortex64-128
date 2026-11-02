`timescale 1ns/1ps
module cortex_rv64i_directed_tb;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  logic mem_req_valid,mem_req_ready,mem_req_write,mem_rsp_valid,mem_rsp_ready,mem_rsp_error;
  logic [63:0] mem_req_addr,mem_req_wdata,mem_rsp_rdata,pc_debug,instret;
  logic [7:0] mem_req_wstrb,fault_code;
  logic halted,fault; logic [7:0] mem[0:4095];
  logic busy,pending_write; logic [63:0] pending_addr,pending_wdata; logic [7:0] pending_wstrb;
  integer i,k;
  assign mem_req_ready=!busy&&!mem_rsp_valid;
  cortex_core dut(.clk(clk),.rst_n(rst_n),.mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),.mem_req_addr(mem_req_addr),.mem_req_write(mem_req_write),.mem_req_wdata(mem_req_wdata),.mem_req_wstrb(mem_req_wstrb),.mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),.mem_rsp_rdata(mem_rsp_rdata),.mem_rsp_error(mem_rsp_error),.halted(halted),.fault(fault),.fault_code(fault_code),.pc_debug(pc_debug),.instret(instret));
  function automatic [31:0] enc_i(input integer imm,input integer rs1,input integer f3,input integer rd,input integer opc);
    enc_i={imm[11:0],rs1[4:0],f3[2:0],rd[4:0],opc[6:0]}; endfunction
  function automatic [31:0] enc_r(input integer f7,input integer rs2,input integer rs1,input integer f3,input integer rd);
    enc_r={f7[6:0],rs2[4:0],rs1[4:0],f3[2:0],rd[4:0],7'h33}; endfunction
  task automatic put_word(input integer a,input logic [31:0] v); integer b; begin for(b=0;b<4;b=b+1) mem[a+b]=v[b*8+:8]; end endtask
  initial begin
    for(i=0;i<4096;i=i+1) mem[i]=0;
    put_word(0,enc_i(-1,0,0,1,7'h13)); put_word(4,enc_i(1,0,0,2,7'h13));
    put_word(8,enc_r(0,2,1,0,3)); put_word(12,enc_r(7'h20,2,1,0,4));
    put_word(16,enc_r(0,2,1,4,5)); put_word(20,enc_r(0,2,1,6,6));
    put_word(24,enc_r(0,2,1,7,7)); put_word(28,enc_r(0,2,1,2,8));
    put_word(32,enc_r(0,2,1,3,9)); put_word(36,enc_i(63,2,1,10,7'h13));
    put_word(40,enc_i(63,10,5,11,7'h13));
    put_word(44,{7'h20,6'd63,5'd10,3'b101,5'd12,7'h13});
    put_word(48,32'h0010_0073); repeat(4) @(posedge clk); rst_n<=1;
  end
  always @(posedge clk) begin
    if(!rst_n) begin busy<=0; pending_write<=0; pending_addr<=0; pending_wdata<=0; pending_wstrb<=0; mem_rsp_valid<=0; mem_rsp_rdata<=0; mem_rsp_error<=0; end
    else begin
      if(mem_rsp_valid&&mem_rsp_ready) mem_rsp_valid<=0;
      if(busy) begin
        if(pending_write) begin for(k=0;k<8;k=k+1) if(pending_wstrb[k]) mem[pending_addr[11:0]+k]<=pending_wdata[k*8+:8]; mem_rsp_rdata<=0; end
        else mem_rsp_rdata<={mem[pending_addr[11:0]+12'd7],mem[pending_addr[11:0]+12'd6],mem[pending_addr[11:0]+12'd5],mem[pending_addr[11:0]+12'd4],mem[pending_addr[11:0]+12'd3],mem[pending_addr[11:0]+12'd2],mem[pending_addr[11:0]+12'd1],mem[pending_addr[11:0]]};
        mem_rsp_error<=0; mem_rsp_valid<=1; busy<=0;
      end
      if(mem_req_valid&&mem_req_ready) begin pending_addr<=mem_req_addr; pending_write<=mem_req_write; pending_wdata<=mem_req_wdata; pending_wstrb<=mem_req_wstrb; busy<=1; end
    end
  end
  initial begin
    wait(rst_n); wait(halted||fault); #1;
    if(fault) $fatal(1,"unexpected trap=%0d pc=%h",fault_code,pc_debug);
    if(dut.regs[1]!==64'hffff_ffff_ffff_ffff) $fatal(1,"ADDI x1=%h",dut.regs[1]);
    if(dut.regs[2]!==1) $fatal(1,"ADDI x2=%h",dut.regs[2]);
    if(dut.regs[3]!==0) $fatal(1,"ADD x3=%h",dut.regs[3]);
    if(dut.regs[4]!==64'hffff_ffff_ffff_fffe) $fatal(1,"SUB x4=%h",dut.regs[4]);
    if(dut.regs[5]!==64'hffff_ffff_ffff_fffe) $fatal(1,"XOR x5=%h",dut.regs[5]);
    if(dut.regs[6]!==64'hffff_ffff_ffff_ffff) $fatal(1,"OR x6=%h",dut.regs[6]);
    if(dut.regs[7]!==1) $fatal(1,"AND x7=%h",dut.regs[7]);
    if(dut.regs[8]!==1) $fatal(1,"SLT x8=%h",dut.regs[8]);
    if(dut.regs[9]!==0) $fatal(1,"SLTU x9=%h",dut.regs[9]);
    if(dut.regs[10]!==64'h8000_0000_0000_0000) $fatal(1,"SLLI x10=%h",dut.regs[10]);
    if(dut.regs[11]!==1) $fatal(1,"SRLI x11=%h",dut.regs[11]);
    if(dut.regs[12]!==64'hffff_ffff_ffff_ffff) $fatal(1,"SRAI x12=%h",dut.regs[12]);
    if(instret!==64'd12) $fatal(1,"instret=%0d expected 12",instret);
    $display("PASS: directed RV64I ALU execution; instret=%0d",instret); $finish;
  end
  initial begin repeat(5000) @(posedge clk); $fatal(1,"TIMEOUT pc=%h",pc_debug); end
endmodule
