//==============================================================
// ahb_slave.sv
//
// AHB-side pipeline registers + peripheral address decode.
// Functionally the same staging as the original AHB_Slave.v;
// the fix here is structural: all the signals that used to be
// loose output ports (and got mis-wired in Bridge_Top) are now
// a single pipe_s struct, so there's no positional-order hazard
// at the instantiation site.
//==============================================================
`timescale 1ns/1ps
import ahb_apb_pkg::*;

module ahb_slave (
  ahb_if.slave        bus,
  input  logic [31:0] Prdata,   // from the APB peripheral, passed through to Hrdata
  output pipe_s        pipe
);

  logic [31:0] haddr1_q,  haddr2_q;
  logic [31:0] hwdata1_q, hwdata2_q;
  logic        hwritereg_q, hwritereg1_q;

  //--------------------------------------------
  // Address pipeline
  //--------------------------------------------
  always_ff @(posedge bus.Hclk or negedge bus.Hresetn) begin
    if (!bus.Hresetn) begin
      haddr1_q <= '0;
      haddr2_q <= '0;
    end else begin
      haddr1_q <= bus.Haddr;
      haddr2_q <= haddr1_q;
    end
  end

  //--------------------------------------------
  // Data pipeline
  //--------------------------------------------
  always_ff @(posedge bus.Hclk or negedge bus.Hresetn) begin
    if (!bus.Hresetn) begin
      hwdata1_q <= '0;
      hwdata2_q <= '0;
    end else begin
      hwdata1_q <= bus.Hwdata;
      hwdata2_q <= hwdata1_q;
    end
  end

  //--------------------------------------------
  // Write-signal pipeline
  //--------------------------------------------
  always_ff @(posedge bus.Hclk or negedge bus.Hresetn) begin
    if (!bus.Hresetn) begin
      hwritereg_q  <= 1'b0;
      hwritereg1_q <= 1'b0;
    end else begin
      hwritereg_q  <= bus.Hwrite;
      hwritereg1_q <= hwritereg_q;
    end
  end

  //--------------------------------------------
  // Peripheral select decode (combinational)
  // Two stages: one for the current address phase (Haddr),
  // one pipelined alongside Haddr1 for states that drive
  // Paddr from the pipelined address - keeping select and
  // address in lockstep through the pipeline.
  //--------------------------------------------
  function automatic logic [2:0] decode_selx(logic [31:0] addr);
    unique case (1'b1)
      (addr >= PERIPH0_BASE && addr < PERIPH0_BASE + PERIPH_WINDOW): decode_selx = 3'b001;
      (addr >= PERIPH1_BASE && addr < PERIPH1_BASE + PERIPH_WINDOW): decode_selx = 3'b010;
      (addr >= PERIPH2_BASE && addr < PERIPH2_BASE + PERIPH_WINDOW): decode_selx = 3'b100;
      default: decode_selx = 3'b000;
    endcase
  endfunction : decode_selx

  logic [2:0] temp_selx_c, temp_selx1_c;
  always_comb temp_selx_c  = decode_selx(bus.Haddr);
  always_comb temp_selx1_c = decode_selx(haddr1_q);

  //--------------------------------------------
  // Valid-transfer indication (combinational)
  //--------------------------------------------
  logic valid_c;
  always_comb begin
    valid_c = (temp_selx_c != 3'b000) &&
              bus.Hreadyin &&
              (bus.Htrans == HTRANS_NONSEQ || bus.Htrans == HTRANS_SEQ);
  end

  assign bus.Hresp  = 2'd0;      // OKAY always; no error path modeled
  assign bus.Hrdata = Prdata;    // straight pass-through from the APB peripheral

  // Pack everything the controller needs into one struct.
  assign pipe.Haddr1     = haddr1_q;
  assign pipe.Haddr2     = haddr2_q;
  assign pipe.Hwdata1    = hwdata1_q;
  assign pipe.Hwdata2    = hwdata2_q;
  assign pipe.Hwritereg  = hwritereg_q;
  assign pipe.Hwritereg1 = hwritereg1_q;
  assign pipe.valid      = valid_c;
  assign pipe.temp_selx  = temp_selx_c;
  assign pipe.temp_selx1 = temp_selx1_c;

endmodule : ahb_slave
