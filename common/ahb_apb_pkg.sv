//==============================================================
// ahb_apb_pkg.sv
//
// Shared types and parameters for the AHB-to-APB bridge.
// Centralizing these removes the "magic number" 2'd2 / 3'b010
// style literals that made the original RTL hard to audit.
//==============================================================
`timescale 1ns/1ps

package ahb_apb_pkg;

  //----------------------------------------------------------
  // AHB transfer type encoding (HTRANS)
  //----------------------------------------------------------
  typedef enum logic [1:0] {
    HTRANS_IDLE   = 2'b00,
    HTRANS_BUSY   = 2'b01,
    HTRANS_NONSEQ = 2'b10,
    HTRANS_SEQ    = 2'b11
  } htrans_e;

  //----------------------------------------------------------
  // AHB burst type encoding (HBURST) - subset actually used
  //----------------------------------------------------------
  typedef enum logic [2:0] {
    HBURST_SINGLE = 3'b000,
    HBURST_INCR   = 3'b001
  } hburst_e;

  //----------------------------------------------------------
  // Bridge FSM states (was: localparam ST_IDLE = 3'b000, ...)
  //----------------------------------------------------------
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_WAIT,
    ST_WRITE,
    ST_WRITEP,
    ST_WENABLEP,
    ST_WENABLE,
    ST_READ,
    ST_RENABLE
  } bridge_state_e;

  //----------------------------------------------------------
  // Peripheral address map: three 64MB windows starting at
  // 0x8000_0000. NOTE: the original testbench drove address
  // 0x0000_0000, which falls OUTSIDE this map -> "valid" was
  // never asserted and no transfer ever completed. Fixed here
  // by having the testbench/BFM use addresses inside the map.
  //----------------------------------------------------------
  localparam logic [31:0] PERIPH_WINDOW = 32'h0400_0000;
  localparam logic [31:0] PERIPH0_BASE  = 32'h8000_0000;
  localparam logic [31:0] PERIPH1_BASE  = 32'h8400_0000;
  localparam logic [31:0] PERIPH2_BASE  = 32'h8800_0000;

  //----------------------------------------------------------
  // Pipelined / decoded signals handed from ahb_slave to
  // apb_controller. Bundling these into one struct is what
  // replaces the original 17-signal positional port list in
  // Bridge_Top, which had two signals connected to the wrong
  // ports (Hwritereg/Hwritereg1 were never even declared, and
  // Hreadyout/Pselx landed on the wrong positions).
  //----------------------------------------------------------
  typedef struct packed {
    logic [31:0] Haddr1;
    logic [31:0] Haddr2;
    logic [31:0] Hwdata1;
    logic [31:0] Hwdata2;
    logic        Hwritereg;
    logic        Hwritereg1;
    logic        valid;
    logic [2:0]  temp_selx;    // decode of the CURRENT Haddr (address phase)
    logic [2:0]  temp_selx1;   // decode of Haddr1 - must travel with Haddr1
                                // wherever the controller drives Paddr from
                                // Haddr1, or the select can desync from the
                                // address actually being driven.
  } pipe_s;

endpackage : ahb_apb_pkg
