//==============================================================
// ahb_master_bfm_fixed.sv
//
// HREADY-aware AHB master BFM.
// Fixes the old BFM issue where address/control/data advanced
// on fixed clock counts without waiting for Hreadyout.
//==============================================================
`timescale 1ns/1ps
import ahb_apb_pkg::*;

module ahb_master_bfm (
  ahb_if.master bus
);

  //------------------------------------------------------------
  // In this simple testbench there is only one slave, so the
  // global AHB HREADY seen by the slave is the bridge Hreadyout.
  //------------------------------------------------------------
  assign bus.Hreadyin = bus.Hreadyout;

  //------------------------------------------------------------
  // Drive a safe idle state out of reset.
  //------------------------------------------------------------
  initial begin
    bus.Htrans = HTRANS_IDLE;
    bus.Hwrite = 1'b0;
    bus.Haddr  = '0;
    bus.Hwdata = '0;
    bus.Hburst = HBURST_SINGLE;
    bus.Hsize  = 3'd0;
  end

  //------------------------------------------------------------
  // Wait until the slave accepts/completes a phase.
  // HREADY is sampled on the rising edge in AHB.
  //------------------------------------------------------------
  task automatic wait_hready();
    do begin
      @(posedge bus.Hclk);
    end while (bus.Hreadyout !== 1'b1);
  endtask : wait_hready

  //------------------------------------------------------------
  // Drive an address/control phase on the falling edge so it is
  // stable before the next rising-edge sample.
  //------------------------------------------------------------
  task automatic drive_addr_phase(
    input logic [31:0] addr,
    input logic        write,
    input htrans_e     trans,
    input hburst_e     burst
  );
    @(negedge bus.Hclk);
    bus.Haddr  <= addr;
    bus.Hwrite <= write;
    bus.Htrans <= trans;
    bus.Hsize  <= 3'd0;
    bus.Hburst <= burst;
  endtask : drive_addr_phase

  //------------------------------------------------------------
  // Single write: address phase -> write data phase -> wait for
  // completion. Signals are held stable while Hreadyout is low.
  //------------------------------------------------------------
  task automatic single_write(input logic [31:0] addr, input logic [31:0] data);
    wait_hready();
    drive_addr_phase(addr, 1'b1, HTRANS_NONSEQ, HBURST_SINGLE);

    // Address phase accepted when Hreadyout is sampled high.
    wait_hready();

    // Data phase for this write. Also drive IDLE as the next address phase.
    @(negedge bus.Hclk);
    bus.Hwdata <= data;
    bus.Htrans <= HTRANS_IDLE;
    bus.Hburst <= HBURST_SINGLE;

    // Do not return until the slave/bridge completes the write data phase.
    wait_hready();
  endtask : single_write

  //------------------------------------------------------------
  // Single read: address phase -> idle next transfer -> wait for
  // read data to be valid when Hreadyout returns high.
  //------------------------------------------------------------
  task automatic single_read(input logic [31:0] addr, output logic [31:0] rdata);
    wait_hready();
    drive_addr_phase(addr, 1'b0, HTRANS_NONSEQ, HBURST_SINGLE);

    // Address phase accepted.
    wait_hready();

    // No next transfer.
    @(negedge bus.Hclk);
    bus.Htrans <= HTRANS_IDLE;
    bus.Hburst <= HBURST_SINGLE;

    // Read data is valid when Hreadyout returns high.
    wait_hready();
    rdata = bus.Hrdata;
  endtask : single_read

  //------------------------------------------------------------
  // Incrementing burst write. Each SEQ address is held until
  // Hreadyout says the bridge accepted that beat.
  //------------------------------------------------------------
  task automatic burst_write(input logic [31:0] addr, input int beats = 4);
    int i;
    logic [31:0] cur_addr;
    logic [31:0] cur_data;

    cur_addr = addr;

    wait_hready();
    drive_addr_phase(cur_addr, 1'b1, HTRANS_NONSEQ, HBURST_INCR);

    for (i = 0; i < beats; i++) begin
      // Beat i address accepted / previous data phase completed.
      wait_hready();

      cur_data = $urandom_range(0, 255);

      @(negedge bus.Hclk);
      bus.Hwdata <= cur_data;

      if (i < beats - 1) begin
        cur_addr   = cur_addr + 1;
        bus.Haddr  <= cur_addr;
        bus.Hwrite <= 1'b1;
        bus.Htrans <= HTRANS_SEQ;
        bus.Hburst <= HBURST_INCR;
      end else begin
        bus.Hwrite <= 1'b0;
        bus.Htrans <= HTRANS_IDLE;
        bus.Hburst <= HBURST_SINGLE;
      end
    end

    // Wait for the final write data phase to complete.
    wait_hready();
  endtask : burst_write

  //------------------------------------------------------------
  // BFM protocol check: after HREADY has been low for a full
  // cycle, master-driven signals must remain stable until ready.
  //------------------------------------------------------------
`ifndef SYNTHESIS
  assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    $past(bus.Hreadyout === 1'b0) |->
      $stable({bus.Haddr, bus.Hwdata, bus.Hwrite, bus.Htrans, bus.Hburst, bus.Hsize}))
    else $error("AHB BFM protocol violation: master changed signals while Hreadyout was low");
`endif

endmodule : ahb_master_bfm
