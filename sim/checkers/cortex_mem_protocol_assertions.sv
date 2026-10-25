`timescale 1ns/1ps

// Simulation-only protocol assertion monitor for the Cortex single-outstanding
// memory interface. Compile into a testbench; do not add to synthesis sources.
module cortex_mem_protocol_assertions (
  input logic clk,
  input logic rst_n,

  input logic        up_req_valid,
  input logic        up_req_ready,
  input logic [63:0] up_req_addr,
  input logic        up_req_write,
  input logic [63:0] up_req_wdata,
  input logic [7:0]  up_req_wstrb,
  input logic        up_rsp_valid,
  input logic        up_rsp_ready,
  input logic [63:0] up_rsp_rdata,
  input logic        up_rsp_error,

  input logic        down_req_valid,
  input logic        down_req_ready,
  input logic [63:0] down_req_addr,
  input logic        down_req_write,
  input logic [63:0] down_req_wdata,
  input logic [7:0]  down_req_wstrb,
  input logic        down_rsp_valid,
  input logic        down_rsp_ready,
  input logic [63:0] down_rsp_rdata,
  input logic        down_rsp_error
);
  logic up_req_stalled_q, down_req_stalled_q;
  logic up_rsp_stalled_q, down_rsp_stalled_q;
  logic [136:0] up_req_payload_q, down_req_payload_q;
  logic [64:0] up_rsp_payload_q, down_rsp_payload_q;
  logic up_outstanding_q, down_outstanding_q;

  wire up_req_fire = up_req_valid && up_req_ready;
  wire up_rsp_fire = up_rsp_valid && up_rsp_ready;
  wire down_req_fire = down_req_valid && down_req_ready;
  wire down_rsp_fire = down_rsp_valid && down_rsp_ready;

  // Immediate assertions are intentionally used instead of SVA sequence syntax
  // so the checker is portable across both Verilator and Icarus Verilog.
  always @(posedge clk) begin
    if (!rst_n) begin
      up_req_stalled_q <= 1'b0;
      down_req_stalled_q <= 1'b0;
      up_rsp_stalled_q <= 1'b0;
      down_rsp_stalled_q <= 1'b0;
      up_req_payload_q <= '0;
      down_req_payload_q <= '0;
      up_rsp_payload_q <= '0;
      down_rsp_payload_q <= '0;
      // Reset starts a new transaction-accounting epoch. The design contract
      // requires reset to be coordinated with the target when a transaction is
      // still outstanding.
      up_outstanding_q <= 1'b0;
      down_outstanding_q <= 1'b0;
    end else begin
      if (up_req_stalled_q) begin
        if (up_req_valid !== 1'b1)
          $fatal(1, "PROTOCOL ASSERTION: upstream request VALID dropped before READY");
        if ({up_req_addr, up_req_write, up_req_wdata, up_req_wstrb} !== up_req_payload_q)
          $fatal(1, "PROTOCOL ASSERTION: upstream request payload changed under backpressure");
      end
      if (down_req_stalled_q) begin
        if (down_req_valid !== 1'b1)
          $fatal(1, "PROTOCOL ASSERTION: downstream request VALID dropped before READY");
        if ({down_req_addr, down_req_write, down_req_wdata, down_req_wstrb} !== down_req_payload_q)
          $fatal(1, "PROTOCOL ASSERTION: downstream request payload changed under backpressure");
      end
      if (up_rsp_stalled_q) begin
        if (up_rsp_valid !== 1'b1)
          $fatal(1, "PROTOCOL ASSERTION: upstream response VALID dropped before READY");
        if ({up_rsp_rdata, up_rsp_error} !== up_rsp_payload_q)
          $fatal(1, "PROTOCOL ASSERTION: upstream response payload changed under backpressure");
      end
      if (down_rsp_stalled_q) begin
        if (down_rsp_valid !== 1'b1)
          $fatal(1, "PROTOCOL ASSERTION: downstream response VALID dropped before READY");
        if ({down_rsp_rdata, down_rsp_error} !== down_rsp_payload_q)
          $fatal(1, "PROTOCOL ASSERTION: downstream response payload changed under backpressure");
      end

      // A single outstanding transaction is allowed on each side. A response
      // in the same cycle as a request handshake is allowed as zero-latency
      // completion. Reset is the only permitted ledger-abort mechanism.
      if (up_req_fire && up_outstanding_q && !up_rsp_fire)
        $fatal(1, "PROTOCOL ASSERTION: second upstream request accepted while one is outstanding");
      if (up_rsp_fire && !up_outstanding_q && !up_req_fire)
        $fatal(1, "PROTOCOL ASSERTION: unsolicited or duplicate upstream response");
      case ({up_req_fire, up_rsp_fire})
        2'b10: up_outstanding_q <= 1'b1;
        2'b01: up_outstanding_q <= 1'b0;
        2'b11: up_outstanding_q <= up_outstanding_q;
        default: up_outstanding_q <= up_outstanding_q;
      endcase

      if (down_req_fire && down_outstanding_q && !down_rsp_fire)
        $fatal(1, "PROTOCOL ASSERTION: second target request accepted while one is outstanding");
      if (down_rsp_fire && !down_outstanding_q && !down_req_fire)
        $fatal(1, "PROTOCOL ASSERTION: unsolicited or duplicate target response");
      case ({down_req_fire, down_rsp_fire})
        2'b10: down_outstanding_q <= 1'b1;
        2'b01: down_outstanding_q <= 1'b0;
        2'b11: down_outstanding_q <= down_outstanding_q;
        default: down_outstanding_q <= down_outstanding_q;
      endcase

      up_req_stalled_q <= up_req_valid && !up_req_ready;
      down_req_stalled_q <= down_req_valid && !down_req_ready;
      up_rsp_stalled_q <= up_rsp_valid && !up_rsp_ready;
      down_rsp_stalled_q <= down_rsp_valid && !down_rsp_ready;
      up_req_payload_q <= {up_req_addr, up_req_write, up_req_wdata, up_req_wstrb};
      down_req_payload_q <= {down_req_addr, down_req_write, down_req_wdata, down_req_wstrb};
      up_rsp_payload_q <= {up_rsp_rdata, up_rsp_error};
      down_rsp_payload_q <= {down_rsp_rdata, down_rsp_error};
    end
  end
endmodule
