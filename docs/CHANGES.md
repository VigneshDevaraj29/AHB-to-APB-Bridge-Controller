# AHB-to-APB Bridge — SystemVerilog Rewrite Notes

This rewrite was compiled and simulated end-to-end (Verilator 5.020, `--timing --assert`)
to confirm functional correctness, not just to check it parses. The original
Verilog project never simulated a write-then-read round trip successfully
because of the bugs below — most were masked by the fact that the original
testbench addressed `0x0000_0000`, which decodes to *no* peripheral.

## Bugs found and fixed

1. **Address mismatch (functional, was silently disabling the whole bridge).**
   `AHB_Slave`'s decode logic only recognizes `0x8000_0000–0x8BFF_FFFF`, but
   `Top_tb.v` drove `0x0000_0000`. `valid` was therefore *never* asserted and
   the FSM never left `IDLE`. Fixed by using addresses inside the decoded
   range everywhere (testbench, BFM, package constants).

2. **Bridge_Top port mis-wiring (structural).** The original positional
   instantiations passed `Hwritereg`/`Hwritereg1` into `AHB_Slave` as if they
   were inputs (they're outputs, and were never declared as wires in
   `Bridge_Top` at all), and the `APB_Controller` instantiation's port order
   didn't match its declaration. Fixed by replacing both 17-signal positional
   lists with two typed SV interfaces (`ahb_if`, `apb_if`) and one packed
   struct (`pipe_s`) — a wiring mistake here is now a compile error.

3. **Inferred latches in `APB_Controller`'s output logic (functional/synthesis
   risk).** Several states left `Pwrite_temp` / `Pselx_temp` / `Paddr_temp` /
   `Pwdata_temp` unassigned on some branches. Fixed by giving every signal an
   explicit default at the top of the combinational block before the `case`.

4. **Latched `Prdata` in `APB_Interface`/peripheral model.** `if (!Pwrite &&
   Penable) Prdata = 8'd25;` had no `else`. Also, the module was never
   actually instantiated anywhere in the original project — `Top_tb` faked
   `Prdata` with a plain `reg`. Replaced with a real one-register peripheral
   (`apb_peripheral.sv`) that's wired into the testbench, drives `Prdata` on
   every path, and returns the value that was actually written.

5. **Real protocol bug, only visible once #4 was fixed: `Pselx` never
   asserted for an isolated (non-back-to-back) write.** In `ST_WAIT`, `Pselx`
   was only set on the "another transfer is pending" branch; a single write
   reached `ST_WRITE`/`ST_WRITEP` with `Penable=1` and `Pselx=0` — a genuine
   APB protocol violation that the original stub peripheral never noticed
   because it didn't check `Pselx`. Confirmed with an SVA assertion
   (`apb_controller.sv`, fires under `--assert` on the unfixed version,
   silent after the fix). Fixed by asserting `Pselx` unconditionally in
   `ST_WAIT`, decoded from a *pipelined* address (`temp_selx1`, decoded from
   `Haddr1`) so the select always matches the address actually being driven
   on `Paddr`, even across pipeline stages.

6. **`AHB_master_Interface.v` and `APB_Interface.v` were dead code.** Neither
   was instantiated by `Bridge_Top` or `Top_tb`; the testbench reimplemented
   its own driving logic instead. Both are now real, wired-in components
   (`ahb_master_bfm`, `apb_peripheral`) of `top_tb.sv`.

7. **`Hreadyout` declared `[2:0]` but only ever driven with literal `0`/`1`.**
   Narrowed to a single bit, matching real AHB-Lite `HREADY` and removing
   dead bits that obscured the signal's meaning.

## Files

| File | Role |
|---|---|
| `ahb_apb_pkg.sv` | Shared enums, address-map constants, `pipe_s` struct |
| `ahb_apb_if.sv` | `ahb_if` / `apb_if` interfaces with `master`/`slave` and `controller`/`peripheral` modports |
| `ahb_master_bfm.sv` | AHB master BFM (`single_write`, `single_read`, `burst_write` tasks) |
| `ahb_slave.sv` | Address/data/write pipeline + peripheral decode |
| `apb_controller.sv` | Bridge FSM, drives the APB bus |
| `apb_peripheral.sv` | Minimal one-register APB slave for testbench use |
| `bridge_top.sv` | Top-level interconnect (DUT) |
| `top_tb.sv` | Testbench: master BFM + `bridge_top` + peripheral, fully wired |

## How this was verified

```bash
# Icarus Verilog could not be used: this build's iverilog (12.0) does not
# support SV interface ports in ANSI module headers at all (confirmed with
# a minimal isolated test before committing to this approach).

verilator --binary --timing -sv --assert --top-module top_tb \
  ahb_apb_pkg.sv ahb_apb_if.sv ahb_master_bfm.sv ahb_slave.sv \
  apb_controller.sv apb_peripheral.sv bridge_top.sv top_tb.sv -o sim_v

./obj_dir/sim_v
```

Result: single write of `0xDEAD_BEEF` to `0x8000_0001`, followed by a single
read of the same address, returns `0xDEADBEEF` exactly. The burst write to
`0x8400_0004` runs through `SEQ` beats without protocol errors. Zero latch
warnings, zero width-mismatch warnings, zero APB-protocol assertion failures
across the full run (`-Wall`, `--assert`).

If you want to confirm in VCS (your usual flow), the file list above compiles
top-to-bottom in dependency order; just substitute your `vcs -sverilog`
invocation for the `verilator` line.
