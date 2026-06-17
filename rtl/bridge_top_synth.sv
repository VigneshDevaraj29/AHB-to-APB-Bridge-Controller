`timescale 1ns/1ps
import ahb_apb_pkg::*;

module bridge_top_synth (
  input  logic        Hclk,
  input  logic        Hresetn,

  input  logic [31:0] Haddr,
  input  logic [31:0] Hwdata,
  input  logic        Hwrite,
  input  logic        Hreadyin,
  input  htrans_e     Htrans,
  input  hburst_e     Hburst,
  input  logic [2:0]  Hsize,

  output logic [31:0] Hrdata,
  output logic [1:0]  Hresp,
  output logic        Hreadyout,

  output logic        Pwrite,
  output logic        Penable,
  output logic [2:0]  Pselx,
  output logic [31:0] Paddr,
  output logic [31:0] Pwdata,
  input  logic [31:0] Prdata
);

  ahb_if bus (
    .Hclk    (Hclk),
    .Hresetn (Hresetn)
  );

  apb_if apb();

  assign bus.Haddr    = Haddr;
  assign bus.Hwdata   = Hwdata;
  assign bus.Hwrite   = Hwrite;
  assign bus.Hreadyin = Hreadyin;
  assign bus.Htrans   = Htrans;
  assign bus.Hburst   = Hburst;
  assign bus.Hsize    = Hsize;

  assign Hrdata    = bus.Hrdata;
  assign Hresp     = bus.Hresp;
  assign Hreadyout = bus.Hreadyout;

  assign Pwrite  = apb.Pwrite;
  assign Penable = apb.Penable;
  assign Pselx   = apb.Pselx;
  assign Paddr   = apb.Paddr;
  assign Pwdata  = apb.Pwdata;

  assign apb.Prdata = Prdata;

  bridge_top u_bridge_top (
    .bus (bus),
    .apb (apb)
  );

endmodule