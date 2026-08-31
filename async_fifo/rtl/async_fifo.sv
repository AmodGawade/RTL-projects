// async_fifo.sv
`timescale 1ns/1ps
// Top-level parameterized asynchronous (dual-clock) FIFO.
// Architecture, design decisions, and corner cases are documented in docs/architecture.md;
// CDC-specific reasoning (why Gray code, why 2-flop, metastability) is in docs/cdc_notes.md.
//
// Source claims this satisfies (docs/claims.md #1):
//   - parameterized, independent read/write clock domains
//   - Gray-coded pointers, synchronized CDC control signals
//   - robust reset + full/empty handling across domains
module async_fifo #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH      = 16,
  parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
  // Write domain
  input  logic                   wr_clk,
  input  logic                   wr_arst_n,   // external, asynchronous, active-low
  input  logic                   wr_en,
  input  logic [DATA_WIDTH-1:0]  wdata,
  output logic                   full,

  // Read domain
  input  logic                   rd_clk,
  input  logic                   rd_arst_n,   // external, asynchronous, active-low
  input  logic                   rd_en,
  output logic [DATA_WIDTH-1:0]  rdata,
  output logic                   empty
);

  // DEPTH must be a power of 2 -- required for the Gray-code full/empty comparison scheme used
  // below (see docs/architecture.md). Caught at elaboration time, not silently ignored.
  initial begin
    if ((DEPTH & (DEPTH - 1)) != 0) begin
      $fatal(1, "async_fifo: DEPTH=%0d is not a power of 2", DEPTH);
    end
  end

  // ---------------------------------------------------------------
  // Reset synchronizers: one per domain. Each domain only ever sees its OWN synchronized reset;
  // there is deliberately no cross-domain reset wiring here (see docs/architecture.md, "Clock/reset
  // domains" -- consistency after a one-sided reset is re-established via the pointer
  // synchronizers, not via a shared reset).
  // ---------------------------------------------------------------
  logic wr_rst_n, rd_rst_n;

  rst_sync u_rst_sync_wr (
    .clk        (wr_clk),
    .arst_n     (wr_arst_n),
    .rst_n_sync (wr_rst_n)
  );

  rst_sync u_rst_sync_rd (
    .clk        (rd_clk),
    .arst_n     (rd_arst_n),
    .rst_n_sync (rd_rst_n)
  );

  // ---------------------------------------------------------------
  // Pointer domains
  // ---------------------------------------------------------------
  logic [ADDR_WIDTH:0] wptr_gray, rptr_gray;
  logic [ADDR_WIDTH:0] wptr_gray_sync_in_rd;  // write pointer, after crossing into rd_clk domain
  logic [ADDR_WIDTH:0] rptr_gray_sync_in_wr;  // read pointer, after crossing into wr_clk domain
  logic [ADDR_WIDTH-1:0] waddr, raddr;

  wptr_full #(.ADDR_WIDTH(ADDR_WIDTH)) u_wptr_full (
    .wr_clk         (wr_clk),
    .wr_rst_n       (wr_rst_n),
    .wr_en          (wr_en),
    .rptr_gray_sync (rptr_gray_sync_in_wr),
    .waddr          (waddr),
    .wptr_gray      (wptr_gray),
    .full           (full)
  );

  rptr_empty #(.ADDR_WIDTH(ADDR_WIDTH)) u_rptr_empty (
    .rd_clk         (rd_clk),
    .rd_rst_n       (rd_rst_n),
    .rd_en          (rd_en),
    .wptr_gray_sync (wptr_gray_sync_in_rd),
    .raddr          (raddr),
    .rptr_gray      (rptr_gray),
    .empty          (empty)
  );

  // ---------------------------------------------------------------
  // The only two signals in this entire design that cross clock domains: both Gray-coded
  // pointers, each through its own 2-flop synchronizer, into the OTHER domain.
  // ---------------------------------------------------------------
  sync_r2r #(.WIDTH(ADDR_WIDTH+1)) u_sync_wptr_to_rd (
    .dest_clk   (rd_clk),
    .dest_rst_n (rd_rst_n),
    .async_in   (wptr_gray),
    .sync_out   (wptr_gray_sync_in_rd)
  );

  sync_r2r #(.WIDTH(ADDR_WIDTH+1)) u_sync_rptr_to_wr (
    .dest_clk   (wr_clk),
    .dest_rst_n (wr_rst_n),
    .async_in   (rptr_gray),
    .sync_out   (rptr_gray_sync_in_wr)
  );

  // ---------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------
  fifo_mem #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH), .ADDR_WIDTH(ADDR_WIDTH)) u_fifo_mem (
    .wr_clk (wr_clk),
    .wr_en  (wr_en && !full),
    .waddr  (waddr),
    .wdata  (wdata),
    .raddr  (raddr),
    .rdata  (rdata)
  );

  // ---------------------------------------------------------------
  // Simulation-only property checking (docs/cdc_notes.md has the full reasoning for each
  // assertion). `ifndef SYNTHESIS` keeps this out of any synthesis tool's view entirely; it exists
  // purely so the testbench's `iverilog` compile picks it up without needing SystemVerilog `bind`,
  // which this repo's simulator does not support (see fifo_sva_checker.sv's header for why).
  // ---------------------------------------------------------------
`ifndef SYNTHESIS
  fifo_sva_checker #(.ADDR_WIDTH(ADDR_WIDTH)) u_fifo_sva_checker (
    .wr_clk    (wr_clk),
    .wr_rst_n  (wr_rst_n),
    .wr_en     (wr_en),
    .full      (full),
    .rd_clk    (rd_clk),
    .rd_rst_n  (rd_rst_n),
    .rd_en     (rd_en),
    .empty     (empty),
    .wptr_gray (wptr_gray),
    .rptr_gray (rptr_gray)
  );
`endif

endmodule
