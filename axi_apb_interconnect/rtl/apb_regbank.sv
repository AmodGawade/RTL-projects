// apb_regbank.sv
`timescale 1ns/1ps
// APB4 completer: a small addressable register bank, reached through axi_lite_to_apb_bridge.sv.
// Implements the real APB SETUP/ACCESS two-phase sequence (not a same-cycle passthrough) and
// returns PSLVERR for any access outside its configured aperture -- this is the "APB peripheral
// register bank with configurable address mapping and error handling" the source claims.
module apb_regbank #(
  parameter int ADDR_WIDTH    = 12,
  parameter int DATA_WIDTH    = 32,
  parameter int BASE_ADDR     = 'h2000,  // this peripheral's assigned base within the SoC map
  parameter int APERTURE_SIZE = 'h100,   // bytes of address space claimed, valid or not
  parameter int NUM_REGS      = 8,       // actual number of real (non-error) word registers
  parameter int WAIT_CYCLES   = 0        // extra PREADY-low cycles per access, for testing backpressure
) (
  input  logic                    pclk,
  input  logic                    presetn,

  input  logic                    psel,
  input  logic                    penable,
  input  logic                    pwrite,
  input  logic [ADDR_WIDTH-1:0]   paddr,
  input  logic [DATA_WIDTH-1:0]   pwdata,
  input  logic [DATA_WIDTH/8-1:0] pstrb,

  output logic                    pready,
  output logic [DATA_WIDTH-1:0]   prdata,
  output logic                    pslverr
);

  localparam int BYTE_OFFSET = $clog2(DATA_WIDTH/8);

  logic [DATA_WIDTH-1:0] regs [0:NUM_REGS-1];

  logic in_aperture, addr_is_real_reg;
  int unsigned word_idx;

  assign in_aperture      = (paddr >= BASE_ADDR) && (paddr < (BASE_ADDR + APERTURE_SIZE));
  assign word_idx         = (paddr - BASE_ADDR) >> BYTE_OFFSET;
  assign addr_is_real_reg = in_aperture && (word_idx < NUM_REGS);

  // ---------------------------------------------------------------
  // APB SETUP/ACCESS state machine (APB4, Requester/Completer roles -- this module is the
  // Completer). psel asserts with penable LOW for exactly one cycle (SETUP), then penable goes
  // HIGH (ACCESS) and stays there until this Completer raises PREADY.
  // ---------------------------------------------------------------
  typedef enum logic [1:0] {P_IDLE, P_ACCESS} p_state_e;
  p_state_e p_state;

  int unsigned wait_ctr;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      p_state  <= P_IDLE;
      pready   <= 1'b0;
      prdata   <= '0;
      pslverr  <= 1'b0;
      wait_ctr <= '0;
      // Same class of bug found and fixed in axi_lite_regfile.sv (see docs/verification.md):
      // regs[] must reset to a defined value, not retain X until first written.
      for (int r = 0; r < NUM_REGS; r++) regs[r] <= '0;
    end else begin
      case (p_state)
        P_IDLE: begin
          pready  <= 1'b0;
          pslverr <= 1'b0;
          if (psel && !penable) begin
            // SETUP cycle observed; ACCESS begins next cycle per APB timing.
            p_state  <= P_ACCESS;
            wait_ctr <= WAIT_CYCLES;
          end
        end

        P_ACCESS: begin
          if (!pready) begin
            // Still waiting out WAIT_CYCLES -- PADDR/PWRITE/PWDATA/PSTRB must stay stable
            // through here (the Requester's job, per APB spec); this Completer just counts down.
            if (wait_ctr != 0) begin
              wait_ctr <= wait_ctr - 1;
            end else begin
              pready  <= 1'b1;
              pslverr <= !addr_is_real_reg;
              if (pwrite && addr_is_real_reg) begin
                for (int b = 0; b < DATA_WIDTH/8; b++) begin
                  if (pstrb[b]) regs[word_idx][b*8 +: 8] <= pwdata[b*8 +: 8];
                end
              end else if (!pwrite) begin
                prdata <= addr_is_real_reg ? regs[word_idx] : '0;
              end
            end
          end else begin
            // PREADY was already asserted as of last cycle -- externally, this is the cycle the
            // Requester observes PSEL&&PENABLE&&PREADY all together and completes the transfer.
            // Drop back to IDLE so a new SETUP can be accepted next.
            p_state <= P_IDLE;
            pready  <= 1'b0;
          end
        end
      endcase
    end
  end

endmodule
