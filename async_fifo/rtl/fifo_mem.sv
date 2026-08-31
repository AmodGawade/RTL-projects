// fifo_mem.sv
`timescale 1ns/1ps
// Storage array with one clocked write port (wr_clk) and one combinational read port. No
// synchronization logic lives in this module at all -- that's deliberate. The only things that
// ever cross domains in this design are the Gray-coded pointers (see sync_r2r.sv); this memory
// just needs a write port and a read port that never interfere with each other.
module fifo_mem #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH      = 16,
  parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
  input  logic                   wr_clk,
  input  logic                   wr_en,       // qualified by "not full" outside this module
  input  logic [ADDR_WIDTH-1:0]  waddr,
  input  logic [DATA_WIDTH-1:0]  wdata,

  input  logic [ADDR_WIDTH-1:0]  raddr,       // registered read pointer, owned by rd_clk domain
  output logic [DATA_WIDTH-1:0]  rdata
);

  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge wr_clk) begin
    if (wr_en) mem[waddr] <= wdata;
  end

  // Read port is combinational (asynchronous read): raddr is the CURRENT read pointer (the entry
  // that will be popped next), so rdata is valid the same cycle empty=0 is checked -- no extra
  // pipeline delay between "not empty" and "data present". rd_en (in rptr_empty.sv) then just
  // advances raddr to the next entry. This matches the classic Cummings async-FIFO reference
  // model and keeps the empty-check / data-valid relationship simple to reason about and verify.
  // No rd_clk port here: this port is genuinely combinational, so there is nothing for it to do.
  assign rdata = mem[raddr];

endmodule
