# Portable board adapter contract

A board integration should be added under a new directory such as `fpga/boards/<vendor>_<part>_<board>/`.

Keep the portable CPU RTL unchanged. The board-specific wrapper should provide:

- input clock and reset conditioning;
- timing and pin constraints;
- a vendor-supported DDR4 controller/PHY where fitted;
- an adapter between the core's abstract request/response memory port and the controller's application/user interface;
- controller-ready/calibration gating;
- memory capacity and clock metadata;
- a repeatable build script and hardware smoke-test instructions.

The core's external memory port is a **64-bit, 8-byte-aligned, single-outstanding request/response interface**. Requests carry byte addresses and byte write strobes. Read responses return the addressed aligned 64-bit little-endian word. A board adapter must preserve transaction order and return one response per accepted request.

No vendor-specific component or DDR4 pin assignment belongs in `rtl/cpu/`. A generic wrapper does not itself instantiate a DDR4 controller and cannot guarantee that DDR4 works on an unspecified board.
