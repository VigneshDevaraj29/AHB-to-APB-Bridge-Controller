//==============================================================
// bridge_top.sv
//
// Top-level interconnect. The original Bridge_Top.v wired
// AHB_Slave and APB_Controller together with two 17-signal
// positional instantiations, and got it wrong: Hwritereg /
// Hwritereg1 were passed in as if they were AHB_Slave inputs
// (they're actually its outputs, and were never even declared
// as wires), and the APB_Controller port order didn't match its
// declaration at all. None of that is possible here: bus/apb are
// single typed interface handles, and pipe is one struct, so a
// connection either matches the declared type or fails to
// compile.
//==============================================================
`timescale 1ns/1ps
import ahb_apb_pkg::*;

module bridge_top (
  ahb_if.slave      bus,
  apb_if.controller apb
);

  pipe_s pipe;

  ahb_slave u_ahb_slave (
    .bus    (bus),
    .Prdata (apb.Prdata),
    .pipe   (pipe)
  );

  apb_controller u_apb_controller (
    .bus  (bus),
    .pipe (pipe),
    .apb  (apb)
  );

endmodule : bridge_top
