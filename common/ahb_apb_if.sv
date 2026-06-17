//==============================================================
// ahb_apb_if.sv
//
// SystemVerilog interfaces for the AHB and APB sides of the
// bridge. Replacing the long, error-prone port lists from the
// original Verilog with typed interfaces + modports means a
// wiring mistake (like the swapped ports in the original
// Bridge_Top) becomes a compile error instead of a silent bug.
//==============================================================
`timescale 1ns/1ps
import ahb_apb_pkg::*;

interface ahb_if (
  input logic Hclk,
  input logic Hresetn
);

  logic [31:0] Haddr;
  logic [31:0] Hwdata;
  logic [31:0] Hrdata;
  logic        Hwrite;
  logic        Hreadyin;
  htrans_e     Htrans;
  hburst_e     Hburst;
  logic [2:0]  Hsize;
  logic [1:0]  Hresp;
  logic        Hreadyout;   // 1 bit, matches real AHB-Lite HREADY.
                             // (original RTL declared this [2:0] but
                             // only ever drove it with the literal
                             // values 0/1, so the extra width did
                             // nothing but obscure the signal's
                             // actual meaning.)

  modport master (
    input  Hclk, Hresetn, Hrdata, Hresp, Hreadyout,
    output Haddr, Hwdata, Hwrite, Hreadyin, Htrans, Hburst, Hsize
  );

  modport slave (
    input  Hclk, Hresetn, Haddr, Hwdata, Hwrite, Hreadyin, Htrans, Hburst, Hsize,
    output Hrdata, Hresp, Hreadyout
  );

endinterface : ahb_if

interface apb_if;

  logic        Pwrite;
  logic        Penable;
  logic [2:0]  Pselx;
  logic [31:0] Paddr;
  logic [31:0] Pwdata;
  logic [31:0] Prdata;

  modport controller (
    output Pwrite, Penable, Pselx, Paddr, Pwdata,
    input  Prdata
  );

  modport peripheral (
    input  Pwrite, Penable, Pselx, Paddr, Pwdata,
    output Prdata
  );

endinterface : apb_if
