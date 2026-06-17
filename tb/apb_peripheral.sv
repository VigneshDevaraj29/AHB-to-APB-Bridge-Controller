//==============================================================
// apb_peripheral.sv
//
// Stub APB peripheral. The original APB_Interface.v had:
//   always @(*) if (!Pwrite && Penable) Prdata = 8'd25;
// with no else branch, which infers a latch on Prdata, and it
// always returned the same constant 25 on every read regardless
// of what was written - so a write-then-read test could never
// actually catch a data-corruption bug.
//
// This version adds one real storage register so a write
// followed by a read returns the value that was written, and
// drives Prdata in every case (no latch).
//
// NOTE: this module was never even instantiated in the original
// project (Bridge_Top only hooked up AHB_Slave + APB_Controller,
// and Top_tb faked Prdata with a plain reg). It's wired into
// top_tb.sv here as the actual APB-side DUT boundary.
//==============================================================
`timescale 1ns/1ps

module apb_peripheral (
  apb_if.peripheral apb,
  input  logic       Hclk,
  input  logic       Hresetn
);

  logic [31:0] mem_q;

  always_ff @(posedge Hclk or negedge Hresetn) begin
    if (!Hresetn)
      mem_q <= 32'h0;
    else if (apb.Pwrite && apb.Penable && (apb.Pselx != 3'b000))
      mem_q <= apb.Pwdata;
  end

  always_comb begin
    if (!apb.Pwrite && apb.Penable && (apb.Pselx != 3'b000))
      apb.Prdata = mem_q;
    else
      apb.Prdata = 32'h0;
  end

endmodule : apb_peripheral
