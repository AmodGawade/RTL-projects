// sync_r2r.sv
`timescale 1ns/1ps
// Generic N-bit 2-flop (register-to-register) synchronizer for a Gray-coded bus crossing clock
// domains. "r2r" = the source is already a register in the source domain; this only adds the
// destination-side synchronizer flops, it does not touch the source register.
//
// This is only safe to use on a bus where AT MOST ONE BIT changes per source-clock update — which
// is exactly what Gray coding guarantees for the FIFO pointers. Do not reuse this module to
// synchronize an arbitrary multi-bit binary bus; that would reintroduce the multi-bit CDC bug this
// whole design exists to avoid (see docs/cdc_notes.md).
module sync_r2r #(
  parameter int WIDTH = 4
) (
  input  logic             dest_clk,
  input  logic             dest_rst_n,   // synchronized reset, already in the dest_clk domain
  input  logic [WIDTH-1:0] async_in,     // Gray-coded pointer, registered in the SOURCE domain
  output logic [WIDTH-1:0] sync_out      // same value, safe to use in the DEST domain
);

  (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] meta_stage;
  (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_stage;

  always_ff @(posedge dest_clk or negedge dest_rst_n) begin
    if (!dest_rst_n) begin
      meta_stage <= '0;
      sync_stage <= '0;
    end else begin
      meta_stage <= async_in;
      sync_stage <= meta_stage;
    end
  end

  assign sync_out = sync_stage;

endmodule
