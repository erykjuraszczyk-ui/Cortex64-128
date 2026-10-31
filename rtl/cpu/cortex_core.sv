// Cortex64/128 v0.1.5 portable single-hart RV64 execution subset.
// Machine CSRs, synchronous traps and MRET are included; DDR4 remains external.
module cortex_core #(
  parameter logic [63:0] RESET_PC = 64'h0000_0000_0000_0000,
  parameter logic [63:0] RESET_MTVEC = 64'h0000_0000_0000_0100,
  parameter bit HALT_ON_EBREAK = 1'b1
) (
  input  logic        clk,
  input  logic        rst_n,

  output logic        mem_req_valid,
  input  logic        mem_req_ready,
  output logic [63:0] mem_req_addr,
  output logic        mem_req_write,
  output logic [63:0] mem_req_wdata,
  output logic [7:0]  mem_req_wstrb,

  input  logic        mem_rsp_valid,
  output logic        mem_rsp_ready,
  input  logic [63:0] mem_rsp_rdata,
  input  logic        mem_rsp_error,

  output logic        halted,
  output logic        fault,
  output logic [7:0]  fault_code,
  output logic [63:0] pc_debug,
  output logic [63:0] instret
);
  typedef enum logic [2:0] {
    S_FETCH_REQ,
    S_FETCH_WAIT,
    S_EXEC,
    S_MEM_REQ,
    S_MEM_WAIT,
    S_HALTED
  } state_t;

  state_t state;
  logic [63:0] pc;
  logic [31:0] instr_q;
  logic [63:0] regs [0:31];

  logic [63:0] rs1_val, rs2_val;
  logic [4:0] rs1_idx, rs2_idx, rd_idx;
  logic [6:0] opcode, funct7;
  logic [2:0] funct3;
  logic [63:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  logic [63:0] effective_addr, branch_target, jump_target, jalr_target;
  logic [63:0] exec_result;
  logic [31:0] word_result;
  logic branch_taken, exec_illegal;

  logic [63:0] mem_addr_q, mem_wdata_q, mem_next_pc_q;
  logic [7:0] mem_wstrb_q;
  logic mem_write_q, mem_is_load_q;
  logic [2:0] mem_funct3_q, mem_offset_q;
  logic [4:0] mem_rd_q;
  logic [63:0] load_shifted;
  logic [63:0] mem_fault_addr_q;

  // Machine-mode control/status state. This release implements M-mode only.
  logic [63:0] mstatus_q, mtvec_q, mscratch_q, mepc_q, mcause_q, mtval_q;
  logic [63:0] mcycle_q;
  logic [11:0] csr_addr;
  logic [63:0] csr_rdata, csr_operand, csr_wdata;
  logic csr_exists, csr_write_intent, csr_illegal;

  integer i;

  assign rs1_idx = instr_q[19:15];
  assign rs2_idx = instr_q[24:20];
  assign rd_idx  = instr_q[11:7];
  assign opcode  = instr_q[6:0];
  assign funct3  = instr_q[14:12];
  assign funct7  = instr_q[31:25];
  assign rs1_val = (rs1_idx == 5'd0) ? 64'd0 : regs[rs1_idx];
  assign rs2_val = (rs2_idx == 5'd0) ? 64'd0 : regs[rs2_idx];

  assign imm_i = {{52{instr_q[31]}}, instr_q[31:20]};
  assign imm_s = {{52{instr_q[31]}}, instr_q[31:25], instr_q[11:7]};
  assign imm_b = {{51{instr_q[31]}}, instr_q[31], instr_q[7],
                  instr_q[30:25], instr_q[11:8], 1'b0};
  assign imm_u = {{32{instr_q[31]}}, instr_q[31:12], 12'b0};
  assign imm_j = {{43{instr_q[31]}}, instr_q[31], instr_q[19:12],
                  instr_q[20], instr_q[30:21], 1'b0};

  assign effective_addr = rs1_val + ((opcode == 7'b0100011) ? imm_s : imm_i);
  assign branch_target  = pc + imm_b;
  assign jump_target    = pc + imm_j;
  assign jalr_target    = (rs1_val + imm_i) & 64'hffff_ffff_ffff_fffe;
  assign load_shifted   = mem_rsp_rdata >> {mem_offset_q, 3'b000};
  assign pc_debug       = pc;
  assign csr_addr       = instr_q[31:20];
  assign csr_operand    = funct3[2] ? {59'd0, rs1_idx} : rs1_val;

  // CSR write intent follows the Zicsr rules: CSRRS/CSRRC do not write when
  // the register/immediate source is zero. Unsupported CSRs trap as illegal.
  always_comb begin
    csr_exists       = 1'b1;
    csr_write_intent = 1'b0;
    csr_rdata        = 64'd0;
    csr_wdata        = 64'd0;
    csr_illegal      = 1'b0;

    case (funct3)
      3'b001, 3'b101: csr_write_intent = 1'b1; // CSRRW[I]
      3'b010, 3'b011: csr_write_intent = (rs1_idx != 5'd0); // CSRRS/RC
      3'b110, 3'b111: csr_write_intent = (rs1_idx != 5'd0); // CSRRSI/RCI
      default: csr_write_intent = 1'b0;
    endcase

    case (csr_addr)
      12'h300: csr_rdata = mstatus_q;
      12'h301: csr_rdata = 64'h8000_0000_0000_0100; // RV64 + I
      12'h305: csr_rdata = mtvec_q;
      12'h340: csr_rdata = mscratch_q;
      12'h341: csr_rdata = mepc_q;
      12'h342: csr_rdata = mcause_q;
      12'h343: csr_rdata = mtval_q;
      12'hB00: csr_rdata = mcycle_q;
      12'hB02: csr_rdata = instret;
      12'hC00: csr_rdata = mcycle_q;
      12'hC02: csr_rdata = instret;
      default: begin csr_exists = 1'b0; csr_rdata = 64'd0; end
    endcase

    case (funct3)
      3'b001, 3'b101: csr_wdata = csr_operand;
      3'b010, 3'b110: csr_wdata = csr_rdata | csr_operand;
      3'b011, 3'b111: csr_wdata = csr_rdata & ~csr_operand;
      default: csr_wdata = 64'd0;
    endcase

    // misa and the user-visible cycle/instret aliases are read-only.
    if (!csr_exists) csr_illegal = 1'b1;
    if (csr_write_intent && (csr_addr == 12'h301 ||
                             csr_addr == 12'hC00 ||
                             csr_addr == 12'hC02))
      csr_illegal = 1'b1;
  end

  // Trap entry is deliberately synchronous: save the faulting PC and cause,
  // update MIE/MPIE/MPP, then branch to the direct-mode mtvec base.
  task automatic take_trap(
    input logic [63:0] epc_value,
    input logic [63:0] cause_value,
    input logic [63:0] tval_value
  );
    begin
      mepc_q       <= epc_value & 64'hffff_ffff_ffff_fffc;
      mcause_q     <= cause_value;
      mtval_q      <= tval_value;
      mstatus_q[7] <= mstatus_q[3];
      mstatus_q[3] <= 1'b0;
      mstatus_q[12:11] <= 2'b11; // only M-mode is implemented
      pc           <= {mtvec_q[63:2], 2'b00};
      state        <= S_FETCH_REQ;
      fault        <= 1'b1;
      fault_code   <= cause_value[7:0];
    end
  endtask

  // Decoder and arithmetic result. Unsupported encodings trap into a sticky
  // diagnostic halt; this release does not claim full RV64I compliance.
  always_comb begin
    exec_result  = 64'd0;
    word_result  = 32'd0;
    exec_illegal = 1'b0;
    branch_taken = 1'b0;

    case (opcode)
      7'h37: exec_result = imm_u;                 // LUI
      7'h17: exec_result = pc + imm_u;             // AUIPC
      7'h13: begin                                // OP-IMM
        case (funct3)
          3'b000: exec_result = rs1_val + imm_i;   // ADDI
          3'b010: exec_result = ($signed(rs1_val) < $signed(imm_i)) ? 64'd1 : 64'd0;
          3'b011: exec_result = (rs1_val < imm_i) ? 64'd1 : 64'd0;
          3'b100: exec_result = rs1_val ^ imm_i;
          3'b110: exec_result = rs1_val | imm_i;
          3'b111: exec_result = rs1_val & imm_i;
          3'b001: begin
            if (instr_q[31:26] == 6'b000000) exec_result = rs1_val << instr_q[25:20];
            else exec_illegal = 1'b1;
          end
          3'b101: begin
            if (instr_q[31:26] == 6'b000000) exec_result = rs1_val >> instr_q[25:20];
            else if (instr_q[31:26] == 6'b010000) exec_result = $signed(rs1_val) >>> instr_q[25:20];
            else exec_illegal = 1'b1;
          end
          default: exec_illegal = 1'b1;
        endcase
      end
      7'h33: begin                                // OP
        case (funct3)
          3'b000: begin
            if (funct7 == 7'h00) exec_result = rs1_val + rs2_val;
            else if (funct7 == 7'h20) exec_result = rs1_val - rs2_val;
            else exec_illegal = 1'b1;
          end
          3'b001: begin if (funct7 == 7'h00) exec_result = rs1_val << rs2_val[5:0]; else exec_illegal = 1'b1; end
          3'b010: begin if (funct7 == 7'h00) exec_result = ($signed(rs1_val) < $signed(rs2_val)) ? 64'd1 : 64'd0; else exec_illegal = 1'b1; end
          3'b011: begin if (funct7 == 7'h00) exec_result = (rs1_val < rs2_val) ? 64'd1 : 64'd0; else exec_illegal = 1'b1; end
          3'b100: begin if (funct7 == 7'h00) exec_result = rs1_val ^ rs2_val; else exec_illegal = 1'b1; end
          3'b101: begin
            if (funct7 == 7'h00) exec_result = rs1_val >> rs2_val[5:0];
            else if (funct7 == 7'h20) exec_result = $signed(rs1_val) >>> rs2_val[5:0];
            else exec_illegal = 1'b1;
          end
          3'b110: begin if (funct7 == 7'h00) exec_result = rs1_val | rs2_val; else exec_illegal = 1'b1; end
          3'b111: begin if (funct7 == 7'h00) exec_result = rs1_val & rs2_val; else exec_illegal = 1'b1; end
          default: exec_illegal = 1'b1;
        endcase
      end
      7'h1b: begin                                // OP-IMM-32
        case (funct3)
          3'b000: word_result = rs1_val[31:0] + imm_i[31:0];
          3'b001: begin if (instr_q[31:25] == 7'h00) word_result = rs1_val[31:0] << instr_q[24:20]; else exec_illegal = 1'b1; end
          3'b101: begin
            if (instr_q[31:25] == 7'h00) word_result = rs1_val[31:0] >> instr_q[24:20];
            else if (instr_q[31:25] == 7'h20) word_result = $signed(rs1_val[31:0]) >>> instr_q[24:20];
            else exec_illegal = 1'b1;
          end
          default: exec_illegal = 1'b1;
        endcase
        exec_result = {{32{word_result[31]}}, word_result};
      end
      7'h3b: begin                                // OP-32
        case (funct3)
          3'b000: begin
            if (funct7 == 7'h00) word_result = rs1_val[31:0] + rs2_val[31:0];
            else if (funct7 == 7'h20) word_result = rs1_val[31:0] - rs2_val[31:0];
            else exec_illegal = 1'b1;
          end
          3'b001: begin if (funct7 == 7'h00) word_result = rs1_val[31:0] << rs2_val[4:0]; else exec_illegal = 1'b1; end
          3'b101: begin
            if (funct7 == 7'h00) word_result = rs1_val[31:0] >> rs2_val[4:0];
            else if (funct7 == 7'h20) word_result = $signed(rs1_val[31:0]) >>> rs2_val[4:0];
            else exec_illegal = 1'b1;
          end
          default: exec_illegal = 1'b1;
        endcase
        exec_result = {{32{word_result[31]}}, word_result};
      end
      7'h63: begin                                // BRANCH
        case (funct3)
          3'b000: branch_taken = (rs1_val == rs2_val); 
          3'b001: branch_taken = (rs1_val != rs2_val);
          3'b100: branch_taken = ($signed(rs1_val) < $signed(rs2_val));
          3'b101: branch_taken = ($signed(rs1_val) >= $signed(rs2_val));
          3'b110: branch_taken = (rs1_val < rs2_val);
          3'b111: branch_taken = (rs1_val >= rs2_val);
          default: exec_illegal = 1'b1;
        endcase
      end
      7'h03: begin                                // LOAD
        if (!(funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010 || funct3 == 3'b011 || funct3 == 3'b100 || funct3 == 3'b101 || funct3 == 3'b110)) exec_illegal = 1'b1;
      end
      7'h23: begin                                // STORE
        if (!(funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b010 || funct3 == 3'b011)) exec_illegal = 1'b1;
      end
      7'h6f: exec_result = pc + 64'd4;            // JAL link
      7'h67: begin                                // JALR
        if (funct3 != 3'b000) exec_illegal = 1'b1;
        exec_result = pc + 64'd4;
      end
      7'h0f: begin                                // FENCE / FENCE.I on uncached serialized bus
        if (!(funct3 == 3'b000 || funct3 == 3'b001)) exec_illegal = 1'b1;
      end
      7'h73: begin                                // Zicsr + ECALL/EBREAK/MRET
        if (funct3 == 3'b000) begin
          if (!(instr_q == 32'h0000_0073 || // ECALL
                instr_q == 32'h0010_0073 || // EBREAK
                instr_q == 32'h3020_0073))  // MRET
            exec_illegal = 1'b1;
        end else if (csr_illegal) begin
          exec_illegal = 1'b1;
        end
      end
      default: exec_illegal = 1'b1;
    endcase
  end

  // One outstanding request. All bus addresses are 8-byte aligned; read data
  // is returned with the addressed 64-bit word in little-endian lane order.
  always_comb begin
    mem_req_valid = 1'b0;
    mem_req_addr  = {pc[63:3], 3'b000};
    mem_req_write = 1'b0;
    mem_req_wdata = 64'd0;
    mem_req_wstrb = 8'd0;
    mem_rsp_ready = 1'b0;

    case (state)
      S_FETCH_REQ: begin
        mem_req_valid = (pc[1:0] == 2'b00);
        mem_req_addr  = {pc[63:3], 3'b000};
      end
      S_FETCH_WAIT: begin
        mem_rsp_ready = 1'b1;
      end
      S_MEM_REQ: begin
        mem_req_valid = 1'b1;
        mem_req_addr  = mem_addr_q;
        mem_req_write = mem_write_q;
        mem_req_wdata = mem_wdata_q;
        mem_req_wstrb = mem_wstrb_q;
      end
      S_MEM_WAIT: begin
        mem_rsp_ready = 1'b1;
      end
      default: begin end
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state         <= S_FETCH_REQ;
      pc            <= RESET_PC;
      instr_q       <= 32'h0000_0013;
      halted        <= 1'b0;
      fault         <= 1'b0;
      fault_code    <= 8'd0;
      instret       <= 64'd0;
      mem_addr_q    <= 64'd0;
      mem_wdata_q   <= 64'd0;
      mem_wstrb_q   <= 8'd0;
      mem_next_pc_q <= 64'd0;
      mem_write_q   <= 1'b0;
      mem_is_load_q <= 1'b0;
      mem_funct3_q  <= 3'd0;
      mem_offset_q  <= 3'd0;
      mem_rd_q      <= 5'd0;
      mem_fault_addr_q <= 64'd0;
      mstatus_q     <= 64'h0000_0000_0000_1800; // MPP=M
      mtvec_q       <= {RESET_MTVEC[63:2], 2'b00};
      mscratch_q    <= 64'd0;
      mepc_q        <= 64'd0;
      mcause_q      <= 64'd0;
      mtval_q       <= 64'd0;
      mcycle_q      <= 64'd0;
      for (i = 0; i < 32; i = i + 1) regs[i] <= 64'd0;
    end else begin
      mcycle_q <= mcycle_q + 64'd1;
      regs[0] <= 64'd0;
      case (state)
        S_FETCH_REQ: begin
          if (pc[1:0] != 2'b00) begin
            take_trap(pc, 64'd0, pc); // instruction-address-misaligned
          end else if (mem_req_ready) begin
            state <= S_FETCH_WAIT;
          end
        end

        S_FETCH_WAIT: begin
          if (mem_rsp_valid && mem_rsp_ready) begin
            if (mem_rsp_error) begin
              take_trap(pc, 64'd1, pc); // instruction access fault
            end else begin
              instr_q <= pc[2] ? mem_rsp_rdata[63:32] : mem_rsp_rdata[31:0];
              state   <= S_EXEC;
            end
          end
        end

        S_EXEC: begin
          if (exec_illegal) begin
            take_trap(pc, 64'd2, {32'd0, instr_q}); // illegal instruction
          end else begin
            case (opcode)
              7'h37, 7'h17, 7'h13, 7'h33, 7'h1b, 7'h3b: begin
                if (rd_idx != 5'd0) regs[rd_idx] <= exec_result;
                pc      <= pc + 64'd4;
                instret <= instret + 64'd1;
                state   <= S_FETCH_REQ;
              end

              7'h6f: begin // JAL
                if (jump_target[1:0] != 2'b00) begin
                  take_trap(pc, 64'd0, jump_target);
                end else begin
                  if (rd_idx != 5'd0) regs[rd_idx] <= exec_result;
                  pc <= jump_target; instret <= instret + 64'd1; state <= S_FETCH_REQ;
                end
              end

              7'h67: begin // JALR
                if (jalr_target[1:0] != 2'b00) begin
                  take_trap(pc, 64'd0, jalr_target);
                end else begin
                  if (rd_idx != 5'd0) regs[rd_idx] <= exec_result;
                  pc <= jalr_target; instret <= instret + 64'd1; state <= S_FETCH_REQ;
                end
              end

              7'h63: begin
                if (branch_taken) begin
                  if (branch_target[1:0] != 2'b00) begin
                    take_trap(pc, 64'd0, branch_target);
                  end else begin
                    pc <= branch_target; instret <= instret + 64'd1; state <= S_FETCH_REQ;
                  end
                end else begin
                  pc <= pc + 64'd4; instret <= instret + 64'd1; state <= S_FETCH_REQ;
                end
              end

              7'h03: begin // LOAD
                if (((funct3 == 3'b001 || funct3 == 3'b101) && effective_addr[0]) ||
                    ((funct3 == 3'b010 || funct3 == 3'b110) && (effective_addr[1:0] != 2'b00)) ||
                    (funct3 == 3'b011 && (effective_addr[2:0] != 3'b000))) begin
                  take_trap(pc, 64'd4, effective_addr); // load address misaligned
                end else begin
                  mem_fault_addr_q <= effective_addr;
                  mem_addr_q    <= {effective_addr[63:3], 3'b000};
                  mem_next_pc_q <= pc + 64'd4;
                  mem_write_q   <= 1'b0;
                  mem_is_load_q <= 1'b1;
                  mem_funct3_q  <= funct3;
                  mem_offset_q  <= effective_addr[2:0];
                  mem_rd_q      <= rd_idx;
                  mem_wdata_q   <= 64'd0;
                  mem_wstrb_q   <= 8'd0;
                  state         <= S_MEM_REQ;
                end
              end

              7'h23: begin // STORE
                if (((funct3 == 3'b001) && effective_addr[0]) ||
                    ((funct3 == 3'b010) && (effective_addr[1:0] != 2'b00)) ||
                    ((funct3 == 3'b011) && (effective_addr[2:0] != 3'b000))) begin
                  take_trap(pc, 64'd6, effective_addr); // store address misaligned
                end else begin
                  mem_fault_addr_q <= effective_addr;
                  mem_addr_q    <= {effective_addr[63:3], 3'b000};
                  mem_next_pc_q <= pc + 64'd4;
                  mem_write_q   <= 1'b1;
                  mem_is_load_q <= 1'b0;
                  mem_funct3_q  <= funct3;
                  mem_offset_q  <= effective_addr[2:0];
                  mem_rd_q      <= 5'd0;
                  mem_wdata_q   <= rs2_val << {effective_addr[2:0], 3'b000};
                  case (funct3)
                    3'b000: mem_wstrb_q <= 8'h01 << effective_addr[2:0];
                    3'b001: mem_wstrb_q <= 8'h03 << effective_addr[2:0];
                    3'b010: mem_wstrb_q <= 8'h0f << effective_addr[2:0];
                    default: mem_wstrb_q <= 8'hff;
                  endcase
                  state <= S_MEM_REQ;
                end
              end

              7'h0f: begin // serialized, uncached baseline: FENCE/FENCE.I no-op
                pc <= pc + 64'd4; instret <= instret + 64'd1; state <= S_FETCH_REQ;
              end

              7'h73: begin
                if (funct3 == 3'b000) begin
                  case (instr_q)
                    32'h0000_0073: begin // ECALL from M-mode: cause 11
                      take_trap(pc, 64'd11, 64'd0);
                    end
                    32'h0010_0073: begin // EBREAK: configurable simulation stop
                      if (HALT_ON_EBREAK) begin
                        halted <= 1'b1;
                        // Preserve the most recent trap record for diagnostics.
                        instret <= instret + 64'd1;
                        state <= S_HALTED;
                      end else begin
                        take_trap(pc, 64'd3, pc);
                      end
                    end
                    32'h3020_0073: begin // MRET (M-mode only)
                      mstatus_q[3] <= mstatus_q[7];
                      mstatus_q[7] <= 1'b1;
                      mstatus_q[12:11] <= 2'b11;
                      pc <= mepc_q;
                      instret <= instret + 64'd1;
                      state <= S_FETCH_REQ;
                    end
                    default: take_trap(pc, 64'd2, {32'd0, instr_q});
                  endcase
                end else begin
                  if (rd_idx != 5'd0) regs[rd_idx] <= csr_rdata;
                  if (csr_write_intent) begin
                    case (csr_addr)
                      12'h300: mstatus_q <= (csr_wdata & 64'h0000_0000_0000_0088) | 64'h0000_0000_0000_1800;
                      12'h305: mtvec_q <= {csr_wdata[63:2], 2'b00}; // direct mode only
                      12'h340: mscratch_q <= csr_wdata;
                      12'h341: mepc_q <= {csr_wdata[63:2], 2'b00};
                      12'h342: mcause_q <= csr_wdata;
                      12'h343: mtval_q <= csr_wdata;
                      12'hB00: mcycle_q <= csr_wdata;
                      12'hB02: instret <= csr_wdata;
                      default: begin end
                    endcase
                  end
                  pc <= pc + 64'd4;
                  if (!(csr_write_intent && (csr_addr == 12'hB02)))
                    instret <= instret + 64'd1;
                  state <= S_FETCH_REQ;
                end
              end

              default: begin
                halted <= 1'b1; fault <= 1'b1; fault_code <= 8'd2; state <= S_HALTED;
              end
            endcase
          end
        end

        S_MEM_REQ: begin
          if (mem_req_ready) state <= S_MEM_WAIT;
        end

        S_MEM_WAIT: begin
          if (mem_rsp_valid && mem_rsp_ready) begin
            if (mem_rsp_error) begin
              if (mem_write_q) take_trap(pc, 64'd7, mem_fault_addr_q); // store access fault
              else take_trap(pc, 64'd5, mem_fault_addr_q); // load access fault
            end else begin
              if (mem_is_load_q && (mem_rd_q != 5'd0)) begin
                case (mem_funct3_q)
                  3'b000: regs[mem_rd_q] <= {{56{load_shifted[7]}}, load_shifted[7:0]};
                  3'b001: regs[mem_rd_q] <= {{48{load_shifted[15]}}, load_shifted[15:0]};
                  3'b010: regs[mem_rd_q] <= {{32{load_shifted[31]}}, load_shifted[31:0]};
                  3'b011: regs[mem_rd_q] <= load_shifted;
                  3'b100: regs[mem_rd_q] <= {56'd0, load_shifted[7:0]};
                  3'b101: regs[mem_rd_q] <= {48'd0, load_shifted[15:0]};
                  3'b110: regs[mem_rd_q] <= {32'd0, load_shifted[31:0]};
                  default: begin halted <= 1'b1; fault <= 1'b1; fault_code <= 8'd2; end
                endcase
              end
              pc <= mem_next_pc_q;
              instret <= instret + 64'd1;
              state <= S_FETCH_REQ;
            end
          end
        end

        S_HALTED: begin
          halted <= 1'b1;
        end

        default: begin
          halted <= 1'b1; fault <= 1'b1; fault_code <= 8'hff; state <= S_HALTED;
        end
      endcase
    end
  end
endmodule
