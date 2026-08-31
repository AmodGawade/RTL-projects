// wptr_full.sv
`timescale 1ns/1ps
// Write-pointer management + FULL flag generation, entirely in the wr_clk domain.
//
// Pointer width is ADDR_WIDTH+1 bits on purpose: the extra MSB is what lets FULL be distinguished
// from EMPTY using pointer equality alone (see docs/cdc_notes.md for the full derivation). The
// lower ADDR_WIDTH bits address fifo_mem; the extra MSB just counts how many times the pointer has
// wrapped around the memory array.
module wptr_full #(
  parameter int ADDR_WIDTH = 4
) (
  input  logic                     wr_clk,
  input  logic                     wr_rst_n,       // already synchronized (see rst_sync.sv)
  input  logic                     wr_en,
  input  logic [ADDR_WIDTH:0]      rptr_gray_sync, // read pointer, Gray-coded, synchronized into this domain

  output logic [ADDR_WIDTH-1:0]    waddr,          // binary, drives fifo_mem's write port
  output logic [ADDR_WIDTH:0]      wptr_gray,       // this domain's Gray pointer, exported for CDC to the read domain
  output logic                     full
);

  logic [ADDR_WIDTH:0] wbin, wbin_next;
  logic [ADDR_WIDTH:0] wgray_next;

  // Binary pointer: easy to increment and to slice for the memory address.
  assign wbin_next  = wbin + (wr_en && !full);
  assign waddr      = wbin[ADDR_WIDTH-1:0];

  // Binary -> Gray conversion of the NEXT value: standard identity gray = bin ^ (bin >> 1).
  // Converting combinationally from wbin_next (rather than registering binary then converting)
  // avoids an extra cycle of latency on the exported Gray pointer.
  assign wgray_next = (wbin_next >> 1) ^ wbin_next;

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wbin      <= '0;
      wptr_gray <= '0;
    end else begin
      wbin      <= wbin_next;
      wptr_gray <= wgray_next;
    end
  end

  // FULL: classic Cummings comparison -- Gray pointers equal in the lower bits but the two MSBs
  // differ (both wrap-count bit and the next-highest bit), which is the Gray-code signature of
  // "write pointer has wrapped exactly one more time than the read pointer, and is chasing it from
  // behind." Comparing the NEXT wgray against the synchronized read pointer means FULL asserts
  // the same cycle the write that would fill the FIFO happens, not one cycle late.
  logic full_next;
  assign full_next = (wgray_next == {~rptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1],
                                       rptr_gray_sync[ADDR_WIDTH-2:0]});

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) full <= 1'b0;
    else           full <= full_next;
  end

endmodule
