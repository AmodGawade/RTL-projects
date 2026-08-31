// rptr_empty.sv
`timescale 1ns/1ps
// Read-pointer management + EMPTY flag generation, entirely in the rd_clk domain.
// Mirror image of wptr_full.sv -- see that file's header for why the pointer is ADDR_WIDTH+1 bits.
module rptr_empty #(
  parameter int ADDR_WIDTH = 4
) (
  input  logic                     rd_clk,
  input  logic                     rd_rst_n,       // already synchronized (see rst_sync.sv)
  input  logic                     rd_en,
  input  logic [ADDR_WIDTH:0]      wptr_gray_sync, // write pointer, Gray-coded, synchronized into this domain

  output logic [ADDR_WIDTH-1:0]    raddr,          // binary, drives fifo_mem's read port
  output logic [ADDR_WIDTH:0]      rptr_gray,       // this domain's Gray pointer, exported for CDC to the write domain
  output logic                     empty
);

  logic [ADDR_WIDTH:0] rbin, rbin_next;
  logic [ADDR_WIDTH:0] rgray_next;

  assign rbin_next  = rbin + (rd_en && !empty);
  assign raddr      = rbin[ADDR_WIDTH-1:0];

  assign rgray_next = (rbin_next >> 1) ^ rbin_next;

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rbin      <= '0;
      rptr_gray <= '0;
    end else begin
      rbin      <= rbin_next;
      rptr_gray <= rgray_next;
    end
  end

  // EMPTY: simple equality is sufficient here (unlike FULL) -- Gray pointers equal means both
  // pointers have made the same number of wraps AND sit at the same offset, i.e. read has caught
  // up to write completely. No MSB inversion needed because "caught up" and "one full lap behind"
  // are distinguished by equality vs. the specific FULL pattern, not two different equality tests.
  logic empty_next;
  assign empty_next = (rgray_next == wptr_gray_sync);

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) empty <= 1'b1;   // FIFO starts empty out of reset
    else           empty <= empty_next;
  end

endmodule
