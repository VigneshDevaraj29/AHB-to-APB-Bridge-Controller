//==============================================================
// top_tb.sv
//
// Testbench with self-checking directed tests, protocol assertions,
// and functional coverage for the AHB-to-APB bridge.
//==============================================================
`timescale 1ns/1ps
import ahb_apb_pkg::*;

module top_tb;

  logic Hclk = 1'b0;
  logic Hresetn;

  always #10 Hclk = ~Hclk;   // 50 MHz

  //----------------------------------------------------------
  // Bus instances
  //----------------------------------------------------------
  ahb_if ahb_bus (.Hclk(Hclk), .Hresetn(Hresetn));
  apb_if apb_bus ();

  //----------------------------------------------------------
  // DUT
  //----------------------------------------------------------
  bridge_top dut (
    .bus (ahb_bus.slave),
    .apb (apb_bus.controller)
  );

  //----------------------------------------------------------
  // AHB master BFM
  //----------------------------------------------------------
  ahb_master_bfm master (
    .bus (ahb_bus.master)
  );

  //----------------------------------------------------------
  // APB peripheral model
  //----------------------------------------------------------
  apb_peripheral peripheral (
    .apb     (apb_bus.peripheral),
    .Hclk    (Hclk),
    .Hresetn (Hresetn)
  );

  //----------------------------------------------------------
  // Assertions + coverage checker
  //----------------------------------------------------------
  ahb_apb_checker checker (
    .bus (ahb_bus),
    .apb (apb_bus)
  );

  //----------------------------------------------------------
  // Reset task
  //----------------------------------------------------------
  task automatic reset();
    int k;
    Hresetn = 1'b0;
    for (k = 0; k < 4; k++) @(negedge Hclk);
    Hresetn = 1'b1;
    @(negedge Hclk);
  endtask : reset

  //----------------------------------------------------------
  // Self-check helper
  //----------------------------------------------------------
  task automatic check_equal(
    input string name,
    input logic [31:0] actual,
    input logic [31:0] expected
  );
    if (actual !== expected) begin
      $error("[FAIL] %s actual=0x%08h expected=0x%08h @ %0t", name, actual, expected, $time);
      $fatal;
    end else begin
      $display("[PASS] %s actual=0x%08h expected=0x%08h @ %0t", name, actual, expected, $time);
    end
  endtask : check_equal

  //----------------------------------------------------------
  // Waves
  //----------------------------------------------------------
  initial begin
    $dumpfile("bridge_top_tb.vcd");
    $dumpvars(0, top_tb);
  end

  //----------------------------------------------------------
  // Console monitor
  //----------------------------------------------------------
  initial begin
    $display(" time | Hresetn Hreadyout Hwrite Htrans | PSEL PEN PWRITE | Haddr        Pwdata        Prdata");
    forever begin
      @(posedge Hclk);
      $display("%5t |   %0b      %0b      %0b     %0d   |  %03b   %0b    %0b   | %08h  %08h  %08h",
        $time, Hresetn, ahb_bus.Hreadyout, ahb_bus.Hwrite, ahb_bus.Htrans,
        apb_bus.Pselx, apb_bus.Penable, apb_bus.Pwrite,
        ahb_bus.Haddr, apb_bus.Pwdata, apb_bus.Prdata);
    end
  end

  //----------------------------------------------------------
  // Stimulus: 6 directed scenarios
  //----------------------------------------------------------
  logic [31:0] rd;

  initial begin
    // Scenario 1: reset + idle behavior
    reset();
    repeat (3) @(negedge Hclk);
    $display("[PASS] Scenario 1: reset/idle completed @ %0t", $time);

    // Scenario 2: single write to APB peripheral 0
    master.single_write(32'h8000_0001, 32'hDEAD_BEEF);
    repeat (6) @(negedge Hclk);
    $display("[PASS] Scenario 2: single write to peripheral 0 completed @ %0t", $time);

    // Scenario 3: single read/readback from APB peripheral 0
    master.single_read(32'h8000_0001, rd);
    $display("[TB] Readback HRDATA = 0x%08h @ %0t", rd, $time);
    check_equal("peripheral0 write-read", rd, 32'hDEAD_BEEF);
    repeat (4) @(negedge Hclk);

    // Scenario 4: invalid address should not select any APB peripheral
    master.single_write(32'h0000_0010, 32'h1234_5678);
    repeat (4) @(negedge Hclk);
    if (apb_bus.Pselx !== 3'b000) begin
      $error("[FAIL] invalid address selected APB peripheral: PSELx=%03b @ %0t", apb_bus.Pselx, $time);
      $fatal;
    end else begin
      $display("[PASS] Scenario 4: invalid address produced no APB select @ %0t", $time);
    end

    // Scenario 5: single write/read to APB peripheral 2
    master.single_write(32'h8800_0008, 32'hCAFE_BABE);
    repeat (6) @(negedge Hclk);
    master.single_read(32'h8800_0008, rd);
    check_equal("peripheral2 write-read", rd, 32'hCAFE_BABE);
    repeat (4) @(negedge Hclk);

    // Scenario 6: incrementing burst write into APB peripheral 1
    master.burst_write(32'h8400_0004, 4);
    repeat (10) @(negedge Hclk);
    $display("[PASS] Scenario 6: burst write to peripheral 1 completed @ %0t", $time);

    $display("\n[TB] PASS: all directed scenarios completed @ %0t\n", $time);
    $finish;
  end

endmodule : top_tb
