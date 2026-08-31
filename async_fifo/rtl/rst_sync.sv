// rst_sync.sv
`timescale 1ns/1ps
// Asynchronous-assert, synchronous-deassert reset synchronizer.
//
// Why this exists: an external async reset can deassert at any point relative to `clk`'s edges.
// If it fed flops directly, deassertion could violate recovery time on some flops and not others,
// letting different parts of the domain come out of reset on different edges. This module forces
// every flop in the domain to see reset drop on the same clk edge, driven through a 2-flop chain
// so the deassertion edge itself is metastability-safe.
module rst_sync (
  input  logic clk,
  input  logic arst_n,     // asynchronous, active-low external reset
  output logic rst_n_sync  // synchronized, active-low, safe to fan out within this domain
);

  logic meta_stage;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      meta_stage  <= 1'b0;
      rst_n_sync  <= 1'b0;
    end else begin
      meta_stage  <= 1'b1;
      rst_n_sync  <= meta_stage;
    end
  end

endmodule
