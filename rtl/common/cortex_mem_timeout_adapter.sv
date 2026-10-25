// Cortex64/128 v0.1.12 — one-outstanding transaction timeout adapter.
// A downstream request is never withdrawn before handshake. If request-ready
// times out, an upstream error is returned while the request remains asserted;
// after the requester consumes the error, the adapter waits in quarantine for
// downstream acceptance and drains that request's eventual response. A response
// timeout after acceptance similarly drains the late response or requires a
// coordinated reset of adapter and target.
module cortex_mem_timeout_adapter #(
  parameter integer TIMEOUT_CYCLES = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  // CPU/requester side
  input  logic        up_req_valid,
  output logic        up_req_ready,
  input  logic [63:0] up_req_addr,
  input  logic        up_req_write,
  input  logic [63:0] up_req_wdata,
  input  logic [7:0]  up_req_wstrb,
  output logic        up_rsp_valid,
  input  logic        up_rsp_ready,
  output logic [63:0] up_rsp_rdata,
  output logic        up_rsp_error,

  // Memory/controller side
  output logic        down_req_valid,
  input  logic        down_req_ready,
  output logic [63:0] down_req_addr,
  output logic        down_req_write,
  output logic [63:0] down_req_wdata,
  output logic [7:0]  down_req_wstrb,
  input  logic        down_rsp_valid,
  output logic        down_rsp_ready,
  input  logic [63:0] down_rsp_rdata,
  input  logic        down_rsp_error
);
  localparam integer TIMER_W = (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES + 1);

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_SEND,
    ST_WAIT_RSP,
    ST_UP_RSP,
    ST_UP_RSP_SEND,
    ST_QUARANTINE_SEND,
    ST_QUARANTINE
  } state_t;

  state_t state_q;
  logic [TIMER_W-1:0] timer_q;
  logic [63:0] req_addr_q, req_wdata_q;
  logic req_write_q;
  logic [7:0] req_wstrb_q;
  logic [63:0] rsp_rdata_q;
  logic rsp_error_q;
  logic quarantine_after_rsp_q;
  logic stale_pending_q;

  wire downstream_req_fire = down_req_valid && down_req_ready;
  wire downstream_rsp_fire = down_rsp_valid && down_rsp_ready;
  wire upstream_rsp_fire = up_rsp_valid && up_rsp_ready;

  always_comb begin
    up_req_ready = (state_q == ST_IDLE);

    // Ready/valid rule: VALID and its payload remain asserted/stable until
    // READY is observed. Request-accept timeout cannot retract the request;
    // it instead delivers an error upstream and quarantines the old request.
    down_req_valid = (state_q == ST_SEND) ||
                     (state_q == ST_UP_RSP_SEND) ||
                     (state_q == ST_QUARANTINE_SEND);
    down_req_addr = req_addr_q;
    down_req_write = req_write_q;
    down_req_wdata = req_wdata_q;
    down_req_wstrb = req_wstrb_q;

    up_rsp_valid = (state_q == ST_UP_RSP) || (state_q == ST_UP_RSP_SEND);
    up_rsp_rdata = rsp_rdata_q;
    up_rsp_error = rsp_error_q;

    // Normal response, known late response, quarantine drain, or a legal
    // same-cycle zero-latency response to a request being accepted late.
    down_rsp_ready = (state_q == ST_WAIT_RSP) ||
                     ((state_q == ST_UP_RSP) && stale_pending_q) ||
                     (state_q == ST_QUARANTINE) ||
                     (((state_q == ST_UP_RSP_SEND) ||
                       (state_q == ST_QUARANTINE_SEND)) && down_req_ready);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      timer_q <= '0;
      req_addr_q <= 64'd0;
      req_write_q <= 1'b0;
      req_wdata_q <= 64'd0;
      req_wstrb_q <= 8'd0;
      rsp_rdata_q <= 64'd0;
      rsp_error_q <= 1'b0;
      quarantine_after_rsp_q <= 1'b0;
      stale_pending_q <= 1'b0;
    end else begin
      case (state_q)
        ST_IDLE: begin
          timer_q <= '0;
          stale_pending_q <= 1'b0;
          quarantine_after_rsp_q <= 1'b0;
          if (up_req_valid && up_req_ready) begin
            req_addr_q <= up_req_addr;
            req_write_q <= up_req_write;
            req_wdata_q <= up_req_wdata;
            req_wstrb_q <= up_req_wstrb;
            state_q <= ST_SEND;
          end
        end

        ST_SEND: begin
          if (downstream_req_fire) begin
            // A same-cycle acceptance wins over request timeout.
            timer_q <= '0;
            state_q <= ST_WAIT_RSP;
          end else if (timer_q >= (TIMEOUT_CYCLES - 1)) begin
            // The target has not accepted yet. Return the timeout upstream,
            // but KEEP downstream VALID/payload until handshake or coordinated
            // reset; otherwise a standard ready/valid target could miss or
            // accept a retracted request ambiguously.
            rsp_rdata_q <= 64'd0;
            rsp_error_q <= 1'b1;
            quarantine_after_rsp_q <= 1'b1;
            stale_pending_q <= 1'b0;
            timer_q <= '0;
            state_q <= ST_UP_RSP_SEND;
          end else begin
            timer_q <= timer_q + 1'b1;
          end
        end

        ST_WAIT_RSP: begin
          if (downstream_rsp_fire) begin
            rsp_rdata_q <= down_rsp_rdata;
            rsp_error_q <= down_rsp_error;
            quarantine_after_rsp_q <= 1'b0;
            stale_pending_q <= 1'b0;
            timer_q <= '0;
            state_q <= ST_UP_RSP;
          end else if (timer_q >= (TIMEOUT_CYCLES - 1)) begin
            // The target accepted this request, so its response may still be
            // in flight. Report timeout upstream but drain the late response.
            rsp_rdata_q <= 64'd0;
            rsp_error_q <= 1'b1;
            quarantine_after_rsp_q <= 1'b1;
            stale_pending_q <= 1'b1;
            timer_q <= '0;
            state_q <= ST_UP_RSP;
          end else begin
            timer_q <= timer_q + 1'b1;
          end
        end

        ST_UP_RSP_SEND: begin
          // Both the upstream timeout response and the original downstream
          // request are valid concurrently. The downstream request must remain
          // unchanged until accepted, even if the requester consumes its error.
          timer_q <= '0;
          if (downstream_req_fire) begin
            if (downstream_rsp_fire) begin
              // Zero-latency acceptance+response: the stale transaction is
              // completely drained in this cycle.
              stale_pending_q <= 1'b0;
              quarantine_after_rsp_q <= 1'b0;
              if (upstream_rsp_fire)
                state_q <= ST_IDLE;
              else
                state_q <= ST_UP_RSP;
            end else begin
              stale_pending_q <= 1'b1;
              if (upstream_rsp_fire) begin
                quarantine_after_rsp_q <= 1'b0;
                state_q <= ST_QUARANTINE;
              end else begin
                quarantine_after_rsp_q <= 1'b1;
                state_q <= ST_UP_RSP;
              end
            end
          end else if (upstream_rsp_fire) begin
            // Upstream has been told about the timeout, but the not-yet-accepted
            // downstream request is still held. New requests stay blocked.
            quarantine_after_rsp_q <= 1'b0;
            stale_pending_q <= 1'b0;
            state_q <= ST_QUARANTINE_SEND;
          end
        end

        ST_UP_RSP: begin
          // If a late response arrives before the requester consumes its
          // timeout response, drain it concurrently and avoid quarantine.
          if (stale_pending_q && downstream_rsp_fire)
            stale_pending_q <= 1'b0;

          if (upstream_rsp_fire) begin
            timer_q <= '0;
            if (quarantine_after_rsp_q) begin
              if (stale_pending_q && !down_rsp_valid)
                state_q <= ST_QUARANTINE;
              else
                state_q <= ST_IDLE;
              quarantine_after_rsp_q <= 1'b0;
            end else begin
              state_q <= ST_IDLE;
            end
          end
        end

        ST_QUARANTINE_SEND: begin
          // Timeout response has already been consumed, but the original
          // downstream request must stay valid until acceptance or reset.
          timer_q <= '0;
          if (downstream_req_fire) begin
            if (downstream_rsp_fire) begin
              stale_pending_q <= 1'b0;
              state_q <= ST_IDLE;
            end else begin
              stale_pending_q <= 1'b1;
              state_q <= ST_QUARANTINE;
            end
          end
        end

        ST_QUARANTINE: begin
          // No upstream request can be accepted in this state. A stale response
          // is consumed and discarded before the port is reused.
          if (downstream_rsp_fire) begin
            stale_pending_q <= 1'b0;
            timer_q <= '0;
            state_q <= ST_IDLE;
          end
        end

        default: begin
          state_q <= ST_IDLE;
          timer_q <= '0;
          stale_pending_q <= 1'b0;
          quarantine_after_rsp_q <= 1'b0;
          rsp_rdata_q <= 64'd0;
          rsp_error_q <= 1'b1;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (TIMEOUT_CYCLES < 1)
      $error("TIMEOUT_CYCLES must be >= 1");
  end
`endif
endmodule
