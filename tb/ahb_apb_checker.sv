//==============================================================
// ahb_apb_checker.sv
//
// Assertion + functional coverage module for the AHB-to-APB
// bridge verification environment.
//==============================================================
`timescale 1ns/1ps
import ahb_apb_pkg::*;

module ahb_apb_checker (
  ahb_if bus,
  apb_if apb
);

`ifndef SYNTHESIS

  //------------------------------------------------------------
  // Helper: decode current AHB address into address regions.
  //------------------------------------------------------------
  function automatic int unsigned addr_region(input logic [31:0] addr);
    if (addr >= PERIPH0_BASE && addr < PERIPH0_BASE + PERIPH_WINDOW)
      addr_region = 1;
    else if (addr >= PERIPH1_BASE && addr < PERIPH1_BASE + PERIPH_WINDOW)
      addr_region = 2;
    else if (addr >= PERIPH2_BASE && addr < PERIPH2_BASE + PERIPH_WINDOW)
      addr_region = 3;
    else
      addr_region = 0;
  endfunction : addr_region

  //------------------------------------------------------------
  // AHB protocol assertions
  //------------------------------------------------------------

  // When HREADYOUT was low in the previous accepted cycle, the
  // AHB master must not advance/change address, control, or write data.
  A_AHB_HOLD_WHEN_NOT_READY: assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    $past(bus.Hreadyout === 1'b0) |->
      $stable({bus.Haddr, bus.Hwdata, bus.Hwrite, bus.Htrans, bus.Hburst, bus.Hsize}))
    else $error("AHB protocol violation: master changed signals while HREADYOUT was low");

  // This bridge currently models only OKAY response.
  A_AHB_RESP_OKAY: assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    bus.Hresp == 2'b00)
    else $error("AHB response error: HRESP is not OKAY");

  // Do not drive unknowns on key AHB bus signals after reset.
  A_AHB_NO_X: assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    !$isunknown({bus.Haddr, bus.Hwrite, bus.Htrans, bus.Hburst, bus.Hsize, bus.Hreadyout, bus.Hresp}))
    else $error("AHB bus has X/Z on key signals");

  //------------------------------------------------------------
  // APB protocol assertions
  //------------------------------------------------------------

  // PSEL must be one-hot-or-zero: only one APB peripheral selected at a time.
  A_APB_PSEL_ONEHOT0: assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    $onehot0(apb.Pselx))
    else $error("APB protocol violation: PSELx is not one-hot-or-zero");

  // APB enable phase must never happen without a selected peripheral.
  A_APB_ENABLE_REQUIRES_SELECT: assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    apb.Penable |-> (apb.Pselx != 3'b000))
    else $error("APB protocol violation: PENABLE asserted with PSELx == 0");

  // APB enable phase should be preceded by setup phase:
  // previous cycle PSEL active and PENABLE low.
  A_APB_SETUP_BEFORE_ENABLE: assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    apb.Penable |-> ($past(apb.Pselx) == apb.Pselx &&
                     $past(apb.Pselx) != 3'b000 &&
                     $past(apb.Penable) == 1'b0))
    else $error("APB protocol violation: missing setup phase before enable phase");

  // Address, select, and write control should be stable from setup to enable.
  A_APB_STABLE_DURING_ENABLE: assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    apb.Penable |-> $stable({apb.Pselx, apb.Paddr, apb.Pwrite}))
    else $error("APB protocol violation: control changed during enable phase");

  // Do not drive unknowns on key APB bus signals after reset.
  A_APB_NO_X: assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    !$isunknown({apb.Pselx, apb.Penable, apb.Pwrite, apb.Paddr, apb.Pwdata, apb.Prdata}))
    else $error("APB bus has X/Z on key signals");

  //------------------------------------------------------------
  // Functional coverage
  //------------------------------------------------------------
  covergroup ahb_apb_cg @(posedge bus.Hclk);
    option.per_instance = 1;
    option.name = "ahb_apb_functional_cg";

    cp_ahb_transfer: coverpoint bus.Htrans iff (bus.Hresetn) {
      bins idle   = {HTRANS_IDLE};
      bins nonseq = {HTRANS_NONSEQ};
      bins seq    = {HTRANS_SEQ};
    }

    cp_ahb_operation: coverpoint bus.Hwrite iff (bus.Hresetn &&
                                                bus.Hreadyout &&
                                                (bus.Htrans inside {HTRANS_NONSEQ, HTRANS_SEQ})) {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    cp_ahb_burst: coverpoint bus.Hburst iff (bus.Hresetn &&
                                            (bus.Htrans inside {HTRANS_NONSEQ, HTRANS_SEQ})) {
      bins single = {HBURST_SINGLE};
      bins incr   = {HBURST_INCR};
    }

    cp_addr_region: coverpoint addr_region(bus.Haddr) iff (bus.Hresetn &&
                                                          (bus.Htrans inside {HTRANS_NONSEQ, HTRANS_SEQ})) {
      bins invalid = {0};
      bins periph0 = {1};
      bins periph1 = {2};
      bins periph2 = {3};
    }

    cp_apb_select: coverpoint apb.Pselx iff (bus.Hresetn) {
      bins no_select = {3'b000};
      bins psel0     = {3'b001};
      bins psel1     = {3'b010};
      bins psel2     = {3'b100};
    }

    cp_apb_phase: coverpoint {apb.Pwrite, apb.Penable} iff (bus.Hresetn && apb.Pselx != 3'b000) {
      bins read_setup   = {2'b00};
      bins read_enable  = {2'b01};
      bins write_setup  = {2'b10};
      bins write_enable = {2'b11};
    }

    cp_hreadyout: coverpoint bus.Hreadyout iff (bus.Hresetn) {
      bins ready = {1'b1};
      bins wait_state = {1'b0};
    }

    // Useful cross: make sure both AHB read and write traffic are seen
    // across valid decoded peripheral regions. Invalid address is excluded
    // because the bridge intentionally does not generate an APB transfer.
    x_op_addr: cross cp_ahb_operation, cp_addr_region {
      ignore_bins invalid_access = binsof(cp_addr_region.invalid);
    }

  endgroup : ahb_apb_cg

  ahb_apb_cg cg = new();

  final begin
    $display("[COV] AHB-APB functional coverage = %0.2f%%", cg.get_coverage());
  end

`endif

endmodule : ahb_apb_checker
