// axi_lite_regfile.sv
`timescale 1ns/1ps
// Generic AXI4-Lite slave: a small addressable register file. Used as slave0/slave1 -- the two
// plain "memory-mapped slaves" the interconnect routes to, distinct from the third (APB-bridged)
// slave. Single-outstanding-transaction slave (no pipelining of a second request while the first
// is still completing) -- standard, simple, and sufficient for what the interconnect needs to
// exercise (address decode + routing + backpressure), not a claim about a specific product's slave
// IP.
import axi_lite_pkg::*;

module axi_lite_regfile #(
  parameter int ADDR_WIDTH = 12,
  parameter int DATA_WIDTH = 32,
  parameter int NUM_REGS   = 16
) (
  input  logic                    clk,
  input  logic                    aresetn,

  // Write address channel
  input  logic                    awvalid,
  output logic                    awready,
  input  logic [ADDR_WIDTH-1:0]   awaddr,

  // Write data channel
  input  logic                    wvalid,
  output logic                    wready,
  input  logic [DATA_WIDTH-1:0]   wdata,
  input  logic [DATA_WIDTH/8-1:0] wstrb,

  // Write response channel
  output logic                    bvalid,
  input  logic                    bready,
  output logic [1:0]              bresp,

  // Read address channel
  input  logic                    arvalid,
  output logic                    arready,
  input  logic [ADDR_WIDTH-1:0]   araddr,

  // Read data channel
  output logic                    rvalid,
  input  logic                    rready,
  output logic [DATA_WIDTH-1:0]   rdata,
  output logic [1:0]              rresp
);

  localparam int WORD_ADDR_BITS = $clog2(NUM_REGS);
  localparam int BYTE_OFFSET    = $clog2(DATA_WIDTH/8);

  logic [DATA_WIDTH-1:0] regs [0:NUM_REGS-1];

  // ---------------------------------------------------------------
  // Write channel: accept AW and W independently (either can arrive first, or together), only
  // commit the write and raise BVALID once both are captured for the same transaction.
  // ---------------------------------------------------------------
  typedef enum logic [1:0] {W_IDLE, W_WAIT_DATA, W_WAIT_ADDR, W_RESP} wr_state_e;
  wr_state_e wr_state;

  logic [ADDR_WIDTH-1:0]   awaddr_capture;
  logic [DATA_WIDTH-1:0]   wdata_capture;
  logic [DATA_WIDTH/8-1:0] wstrb_capture;
  logic                    wr_addr_valid_range;
  int unsigned             wr_word_idx;

  assign wr_word_idx         = awaddr_capture[BYTE_OFFSET +: WORD_ADDR_BITS];
  assign wr_addr_valid_range = (wr_word_idx < NUM_REGS);

  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      wr_state <= W_IDLE;
      awready  <= 1'b0;
      wready   <= 1'b0;
      bvalid   <= 1'b0;
      bresp    <= RESP_OKAY;
    end else begin
      case (wr_state)
        W_IDLE: begin
          awready <= 1'b1;
          wready  <= 1'b1;
          if (awvalid && awready && wvalid && wready) begin
            // both arrive together
            awaddr_capture <= awaddr;
            wdata_capture  <= wdata;
            wstrb_capture  <= wstrb;
            awready <= 1'b0;
            wready  <= 1'b0;
            wr_state <= W_RESP;
          end else if (awvalid && awready) begin
            awaddr_capture <= awaddr;
            awready <= 1'b0;
            wr_state <= W_WAIT_DATA;
          end else if (wvalid && wready) begin
            wdata_capture <= wdata;
            wstrb_capture <= wstrb;
            wready <= 1'b0;
            wr_state <= W_WAIT_ADDR;
          end
        end

        W_WAIT_DATA: begin
          wready <= 1'b1;
          if (wvalid && wready) begin
            wdata_capture <= wdata;
            wstrb_capture <= wstrb;
            wready <= 1'b0;
            wr_state <= W_RESP;
          end
        end

        W_WAIT_ADDR: begin
          awready <= 1'b1;
          if (awvalid && awready) begin
            awaddr_capture <= awaddr;
            awready <= 1'b0;
            wr_state <= W_RESP;
          end
        end

        W_RESP: begin
          bvalid <= 1'b1;
          if (wr_addr_valid_range) bresp <= RESP_OKAY;
          else                     bresp <= RESP_SLVERR;
          if (bvalid && bready) begin
            bvalid   <= 1'b0;
            wr_state <= W_IDLE;
          end
        end
      endcase
    end
  end

  // Commit point: fires exactly on the cycle where the SECOND of {address, data} becomes
  // available (whichever arrives first was already captured into *_capture on an earlier cycle;
  // whichever arrives second is read directly off the input port this same cycle, via the
  // "_next" muxing below, since its own *_capture register won't hold it until the following
  // edge).
  logic wr_commit_pulse;
  assign wr_commit_pulse = (wr_state != W_RESP) &&
    ((wr_state == W_IDLE      && awvalid && awready && wvalid && wready) ||
     (wr_state == W_WAIT_DATA && wvalid  && wready) ||
     (wr_state == W_WAIT_ADDR && awvalid && awready));

  // "_next" values: on the commit cycle, whichever of addr/data was captured in an EARLIER cycle
  // reads from the *_capture register; whichever just arrived THIS cycle must be read directly
  // from the input port (the *_capture register won't hold it until the following edge). Declared
  // and computed here, ahead of the always_ff below that consumes them -- this simulator doesn't
  // resolve forward references to a later block's combinational outputs.
  logic [ADDR_WIDTH-1:0]   awaddr_next;
  logic [DATA_WIDTH-1:0]   wdata_next;
  logic [DATA_WIDTH/8-1:0] wstrb_next;
  int unsigned             wr_word_idx_next;
  logic                    wr_addr_valid_range_next;

  always_comb begin
    case (wr_state)
      W_WAIT_DATA: begin awaddr_next = awaddr_capture; wdata_next = wdata; wstrb_next = wstrb; end
      W_WAIT_ADDR: begin awaddr_next = awaddr;          wdata_next = wdata_capture; wstrb_next = wstrb_capture; end
      default:     begin awaddr_next = awaddr;          wdata_next = wdata; wstrb_next = wstrb; end // W_IDLE both-together case
    endcase
    wr_word_idx_next         = awaddr_next[BYTE_OFFSET +: WORD_ADDR_BITS];
    wr_addr_valid_range_next = (wr_word_idx_next < NUM_REGS);
  end

  // Real bug found by testing (docs/verification.md): this block originally had no reset branch
  // at all, so `regs[]` held X until explicitly written -- any read of a never-written register
  // returned X instead of a defined reset value, which is both bad hardware practice and doesn't
  // match what any reasonable spec ("register file", implying defined reset content) would claim.
  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      for (int r = 0; r < NUM_REGS; r++) regs[r] <= '0;
    end else if (wr_commit_pulse && wr_addr_valid_range_next) begin
      for (int b = 0; b < DATA_WIDTH/8; b++) begin
        if (wstrb_next[b]) regs[wr_word_idx_next][b*8 +: 8] <= wdata_next[b*8 +: 8];
      end
    end
  end

  // ---------------------------------------------------------------
  // Read channel: straightforward single-outstanding read.
  // ---------------------------------------------------------------
  typedef enum logic [1:0] {R_IDLE, R_RESP} rd_state_e;
  rd_state_e rd_state;

  logic [ADDR_WIDTH-1:0] araddr_capture;
  int unsigned            rd_word_idx;
  logic                   rd_addr_valid_range;

  assign rd_word_idx         = araddr_capture[BYTE_OFFSET +: WORD_ADDR_BITS];
  assign rd_addr_valid_range = (rd_word_idx < NUM_REGS);

  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      rd_state <= R_IDLE;
      arready  <= 1'b0;
      rvalid   <= 1'b0;
      rresp    <= RESP_OKAY;
      rdata    <= '0;
    end else begin
      case (rd_state)
        R_IDLE: begin
          arready <= 1'b1;
          if (arvalid && arready) begin
            araddr_capture <= araddr;
            arready  <= 1'b0;
            rd_state <= R_RESP;
          end
        end
        R_RESP: begin
          rvalid <= 1'b1;
          if (rd_addr_valid_range) begin
            rdata <= regs[rd_word_idx];
            rresp <= RESP_OKAY;
          end else begin
            rdata <= '0;
            rresp <= RESP_SLVERR;
          end
          if (rvalid && rready) begin
            rvalid   <= 1'b0;
            rd_state <= R_IDLE;
          end
        end
      endcase
    end
  end

endmodule
