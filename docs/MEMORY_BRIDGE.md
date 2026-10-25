# Cortex64/128 v0.1.2 — Memory Bridge Contract

## Interface

The CPU, local BRAM target and future DDR4 adapter share the same logical request/response contract:

- request fields: `req_valid`, `req_ready`, `req_addr[63:0]`, `req_write`, `req_wdata[63:0]`, `req_wstrb[7:0]`;
- response fields: `rsp_valid`, `rsp_ready`, `rsp_rdata[63:0]`, `rsp_error`;
- one outstanding request/response pair;
- acceptance occurs on a rising edge when `req_valid && req_ready`;
- completion occurs on a rising edge when `rsp_valid && rsp_ready`;
- response data and error must remain stable while `rsp_valid && !rsp_ready`;
- address and data lanes use little-endian byte order;
- request addresses at this interface must be aligned to 8 bytes;
- `req_wstrb[n]` controls `req_wdata[8*n +: 8]` at byte offset `n`.

## BRAM target behavior

`cortex_bram_mem` uses a synchronous, single-port memory array. It accepts a request only when no response is outstanding. After an accepted request it raises `rsp_valid`; for stores, the byte writes and successful response are associated with the same request. Out-of-range and non-64-bit-aligned requests return `rsp_error=1` and do not alter the memory.

Parameters:

- `BASE_ADDR`: lowest byte address mapped to the memory array;
- `WORDS`: number of 64-bit words;
- `INIT_FILE`: optional hex file consumed by `$readmemh`.

The memory byte capacity is `WORDS * 8`. Valid request addresses lie in `[BASE_ADDR, BASE_ADDR + WORDS*8)` and must be 8-byte aligned.

## DDR4 adapter boundary

A board-specific adapter must translate the generic transaction into the selected vendor's DDR4 application interface. It must:

1. hold requests until the controller accepts them;
2. wait for memory initialization/calibration before acknowledging usable memory;
3. preserve byte strobes and address semantics;
4. emit exactly one response per accepted request;
5. hold responses until the CPU consumes them;
6. map controller errors/timeouts to `rsp_error` where possible;
7. document any burst splitting, data-width conversion, or address remapping.

DDR4 PHY, clocking, calibration, timing constraints, pins and voltage standards are outside the portable RTL and must be supplied by the board/vendor flow.


## Optional timeout adapter (v0.1.8)

`rtl/common/cortex_mem_timeout_adapter.sv` is an optional requester-to-target bridge for a single-outstanding transaction interface. `TIMEOUT_CYCLES` bounds both (1) cycles spent asserting a request without `down_req_ready`, and (2) cycles after accepted request while waiting for `down_rsp_valid`. The default chosen by `cortex_top_timeout` is 64 cycles; board integration should tune it to the target controller's documented worst-case latency and clock domain.

On a request-accept timeout, no downstream handshake has happened, so the adapter returns `up_rsp_error=1`, `up_rsp_rdata=0` to the requester, **but it must not withdraw downstream `VALID`** under a standard ready/valid contract. The old request and its payload stay asserted/stable until the target accepts them or a coordinated reset clears both adapter and target. After the upstream error is consumed, the adapter remains in request quarantine; if the target later accepts the old request, its response is drained/discarded before new traffic is allowed. On response timeout, the target has already accepted the request: the adapter returns one error response and waits in late-response quarantine, keeping `down_rsp_ready` asserted to drain/discard the old response. If a required handshake/response never arrives, recovery requires a coordinated reset/flush of the adapter and target/controller. The interface has no transaction IDs or cancellation signal, so reusing the bus before resolving the old request could misattribute a late response.

A target response valid in the cycle at the timeout boundary wins over timeout. The target must obey the normal ready/valid response contract and hold `rsp_valid`, `rsp_rdata` and `rsp_error` stable until the adapter handshakes the response. The adapter does not cover independent clock domains; add a CDC bridge if the memory controller uses a different clock. `cortex_top_timeout.sv` is the integration wrapper that uses this adapter; `cortex_top.sv` continues to expose the direct core bus without timeout policy.


For an end-to-end scratchpad test that uses the timeout adapter in the actual CPU path, `rtl/top/cortex_timeout_bram_soc.sv` connects `cortex_top_timeout` to `cortex_bram_mem`. The directed smoke test is `sim/tb/cortex_timeout_bram_soc_tb.sv`; it checks request/response accounting on both sides of the adapter. This wrapper is a validation aid, not a substitute for a board-specific DDR4 bridge.
