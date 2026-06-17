//==============================================================
// apb_controller.sv
//
// FSM that sequences AHB transfers onto the APB bus
// (setup -> enable -> data phases). Same state machine as the
// original APB_Controller.v, but the combinational output block
// now assigns every temp signal a default at the top before the
// case statement, so no branch can leave Pwrite_n/Pselx_n/etc.
// unassigned. The original left these unassigned in several
// branches (e.g. ST_WAIT's else branch never set Pselx_temp,
// ST_WENABLEP's "else" case was unreachable dead logic, etc.),
// which synthesizes to inferred latches.
//==============================================================
`timescale 1ns/1ps
import ahb_apb_pkg::*;

module apb_controller (
  ahb_if.slave      bus,   // current Haddr/Hwdata/Hwrite + drives Hreadyout
  input  pipe_s     pipe,  // pipelined info from ahb_slave
  apb_if.controller apb
);

  bridge_state_e present_state, next_state;

  // Next-value signals for the registered outputs below.
  logic        Pwrite_n, Penable_n;
  logic [2:0]  Pselx_n;
  logic [31:0] Paddr_n, Pwdata_n;
  logic        Hreadyout_n;

  //--------------------------------------------------------
  // Combinational: next-state + next-output-value logic.
  // Defaults are set first so every signal is driven on
  // every path through the case statement - no latches.
  //--------------------------------------------------------
  always_comb begin
    next_state  = present_state;
    Pselx_n     = 3'b000;
    Penable_n   = 1'b0;
    Pwrite_n    = 1'b0;
    Paddr_n     = apb.Paddr;    // hold by default
    Pwdata_n    = apb.Pwdata;   // hold by default
    Hreadyout_n = 1'b1;         // ready by default (no wait state)

    unique case (present_state)

      ST_IDLE: begin
        if (pipe.valid && bus.Hwrite) begin
          next_state  = ST_WAIT;
          Hreadyout_n = 1'b0;
        end else if (pipe.valid && !bus.Hwrite) begin
          next_state  = ST_READ;
          Paddr_n     = bus.Haddr;
          Pwrite_n    = bus.Hwrite;
          Pselx_n     = pipe.temp_selx;
          Hreadyout_n = 1'b0;
        end else begin
          next_state = ST_IDLE;
        end
      end

      ST_WAIT: begin
        // Pselx must be asserted here unconditionally - it was
        // previously only set on the pipe.valid (back-to-back)
        // branch, which meant an isolated single write held
        // Pselx at its old (deasserted) value all the way through
        // WRITE/WRITEP, asserting Penable with no peripheral
        // selected. Caught by simulation: see apb_controller's
        // protocol assertion below.
        Paddr_n     = pipe.Haddr1;
        Pwdata_n    = bus.Hwdata;
        Pwrite_n    = bus.Hwrite;
        Pselx_n     = pipe.temp_selx1;
        Hreadyout_n = 1'b0;
        next_state  = pipe.valid ? ST_WRITEP : ST_WRITE;
      end

      ST_WRITEP: begin
        next_state = ST_WENABLEP;
        Penable_n  = 1'b1;
        Pselx_n    = apb.Pselx;
        Paddr_n    = apb.Paddr;
        Pwdata_n   = apb.Pwdata;
        Pwrite_n   = apb.Pwrite;
      end

      ST_WRITE: begin
        next_state = pipe.valid ? ST_WENABLEP : ST_WENABLE;
        Penable_n  = 1'b1;
        Pselx_n    = apb.Pselx;
        Paddr_n    = apb.Paddr;
        Pwdata_n   = apb.Pwdata;
        Pwrite_n   = apb.Pwrite;
      end

      ST_WENABLEP: begin
        Paddr_n     = pipe.Haddr1;
        Pwdata_n    = bus.Hwdata;
        Pwrite_n    = bus.Hwrite;
        Pselx_n     = pipe.temp_selx1;
        Hreadyout_n = 1'b0;
        if (pipe.valid && pipe.Hwritereg)
          next_state = ST_WRITEP;
        else if (!pipe.Hwritereg)
          next_state = ST_READ;
        else if (!pipe.valid)
          next_state = ST_WRITE;
        else
          next_state = ST_WENABLEP;
      end

      ST_WENABLE: begin
        if (pipe.valid && !bus.Hwrite) begin
          next_state = ST_READ;
        end else if (pipe.valid && bus.Hwrite) begin
          next_state  = ST_WAIT;
          Paddr_n     = pipe.Haddr1;
          Pwrite_n    = pipe.Hwritereg;
          Pselx_n     = pipe.temp_selx1;
          Hreadyout_n = 1'b0;
        end else if (!pipe.valid) begin
          next_state = ST_IDLE;
        end else begin
          next_state = ST_WENABLE;
        end
      end

      ST_READ: begin
        next_state = ST_RENABLE;
        Penable_n  = 1'b1;
        Pselx_n    = apb.Pselx;
        Paddr_n    = apb.Paddr;
        Pwrite_n   = apb.Pwrite;
      end

      ST_RENABLE: begin
        if (pipe.valid && !bus.Hwrite) begin
          next_state  = ST_READ;
          Paddr_n     = bus.Haddr;
          Pwrite_n    = bus.Hwrite;
          Pselx_n     = pipe.temp_selx;
          Hreadyout_n = 1'b0;
        end else if (pipe.valid && bus.Hwrite) begin
          next_state  = ST_WAIT;
          Hreadyout_n = 1'b0;
        end else if (!pipe.valid) begin
          next_state = ST_IDLE;
        end else begin
          next_state = ST_RENABLE;
        end
      end

      default: next_state = ST_IDLE;

    endcase
  end

  //--------------------------------------------------------
  // Sequential: register state + outputs.
  //--------------------------------------------------------
  always_ff @(posedge bus.Hclk or negedge bus.Hresetn) begin
    if (!bus.Hresetn) begin
      present_state   <= ST_IDLE;
      apb.Pselx       <= 3'b000;
      apb.Penable     <= 1'b0;
      apb.Pwrite      <= 1'b0;
      bus.Hreadyout   <= 1'b1;
      apb.Paddr       <= '0;
      apb.Pwdata      <= '0;
    end else begin
      present_state   <= next_state;
      apb.Pselx       <= Pselx_n;
      apb.Penable     <= Penable_n;
      apb.Pwrite      <= Pwrite_n;
      bus.Hreadyout   <= Hreadyout_n;
      apb.Paddr       <= Paddr_n;
      apb.Pwdata      <= Pwdata_n;
    end
  end

  //--------------------------------------------------------
  // Lightweight protocol check (debug builds only).
  // APB rule: PENABLE must not be asserted unless some
  // PSELx is asserted.
  //--------------------------------------------------------
`ifndef SYNTHESIS
  assert property (@(posedge bus.Hclk) disable iff (!bus.Hresetn)
    apb.Penable |-> (apb.Pselx != 3'b000))
    else $error("APB protocol violation: Penable asserted with Pselx == 0");
`endif

endmodule : apb_controller
