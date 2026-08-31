// axi_lite_to_apb_bridge.sv
`timescale 1ns/1ps
// Converts one AXI4-Lite slave-side transaction into a real APB SETUP-then-ACCESS sequence on the
// downstream APB completer (apb_regbank.sv). APB is a single-request bus (one PSEL/PADDR/PWRITE
// set, no separate read/write channels) -- so unlike the AXI side (which has independent AW/AR
// paths), this bridge can only service ONE AXI transaction (a write, or a read) through APB at a
// time. If an AXI write and an AXI read both arrive while the bridge is idle, write is prioritized
// (matches this project's overall fixed-priority arbitration choice, documented in
// axi_lite_interconnect.sv); the other simply waits (backpressured) until the bridge returns to
// IDLE.
import axi_lite_pkg::*;

module axi_lite_to_apb_bridge #(
  parameter int ADDR_WIDTH = 16,
  parameter int DATA_WIDTH = 32
) (
  input  logic                    clk,
  input  logic                    aresetn,

  // AXI4-Lite slave-side ports (this bridge acts as the AXI slave the interconnect routes to)
  input  logic                    awvalid,
  output logic                    awready,
  input  logic [ADDR_WIDTH-1:0]   awaddr,

  input  logic                    wvalid,
  output logic                    wready,
  input  logic [DATA_WIDTH-1:0]   wdata,
  input  logic [DATA_WIDTH/8-1:0] wstrb,

  output logic                    bvalid,
  input  logic                    bready,
  output logic [1:0]              bresp,

  input  logic                    arvalid,
  output logic                    arready,
  input  logic [ADDR_WIDTH-1:0]   araddr,

  output logic                    rvalid,
  input  logic                    rready,
  output logic [DATA_WIDTH-1:0]   rdata,
  output logic [1:0]              rresp,

  // APB requester-side ports, driving apb_regbank.sv
  output logic                    psel,
  output logic                    penable,
  output logic                    pwrite,
  output logic [ADDR_WIDTH-1:0]   paddr,
  output logic [DATA_WIDTH-1:0]   pwdata,
  output logic [DATA_WIDTH/8-1:0] pstrb,
  input  logic                    pready,
  input  logic [DATA_WIDTH-1:0]   prdata,
  input  logic                    pslverr
);

  typedef enum logic [2:0] {
    B_IDLE, B_WAIT_WDATA, B_WAIT_WADDR, B_APB_SETUP, B_APB_ACCESS, B_RESP_W, B_RESP_R
  } bridge_state_e;
  bridge_state_e state;

  logic [ADDR_WIDTH-1:0]   addr_capture;
  logic [DATA_WIDTH-1:0]   wdata_capture;
  logic [DATA_WIDTH/8-1:0] wstrb_capture;
  logic                    is_write_xact; // latched: which AXI transaction is currently being serviced

  // Latched APB result -- captured exactly on the ACCESS->RESP transition (declared here, ahead
  // of use, since this simulator doesn't resolve forward references to a later always_ff's target
  // reg across module scope).
  logic                    pslverr_latched;
  logic [DATA_WIDTH-1:0]   prdata_latched;

  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      state    <= B_IDLE;
      awready  <= 1'b0;
      wready   <= 1'b0;
      arready  <= 1'b0;
      bvalid   <= 1'b0;
      rvalid   <= 1'b0;
      psel     <= 1'b0;
      penable  <= 1'b0;
      pwrite   <= 1'b0;
    end else begin
      case (state)
        // -------------------------------------------------------------
        // Accept a new AXI transaction. Write is prioritized over read if both request at once.
        // AW/W may arrive in either order, same as axi_lite_regfile.sv.
        // -------------------------------------------------------------
        B_IDLE: begin
          awready <= 1'b1;
          wready  <= 1'b1;
          arready <= 1'b1;
          bvalid  <= 1'b0;
          rvalid  <= 1'b0;

          if (awvalid && awready && wvalid && wready) begin
            addr_capture  <= awaddr;
            wdata_capture <= wdata;
            wstrb_capture <= wstrb;
            is_write_xact <= 1'b1;
            awready <= 1'b0; wready <= 1'b0; arready <= 1'b0;
            state <= B_APB_SETUP;
          end else if (awvalid && awready) begin
            addr_capture  <= awaddr;
            is_write_xact <= 1'b1;
            awready <= 1'b0; wready <= 1'b0; arready <= 1'b0;
            state <= B_WAIT_WDATA;
          end else if (wvalid && wready) begin
            wdata_capture <= wdata;
            wstrb_capture <= wstrb;
            is_write_xact <= 1'b1;
            awready <= 1'b0; wready <= 1'b0; arready <= 1'b0;
            state <= B_WAIT_WADDR;
          end else if (arvalid && arready) begin
            addr_capture  <= araddr;
            is_write_xact <= 1'b0;
            awready <= 1'b0; wready <= 1'b0; arready <= 1'b0;
            state <= B_APB_SETUP;
          end
        end

        B_WAIT_WDATA: begin
          wready <= 1'b1;
          if (wvalid && wready) begin
            wdata_capture <= wdata;
            wstrb_capture <= wstrb;
            wready <= 1'b0;
            state  <= B_APB_SETUP;
          end
        end

        B_WAIT_WADDR: begin
          awready <= 1'b1;
          if (awvalid && awready) begin
            addr_capture <= awaddr;
            awready <= 1'b0;
            state   <= B_APB_SETUP;
          end
        end

        // -------------------------------------------------------------
        // Drive the real APB SETUP-then-ACCESS sequence.
        // -------------------------------------------------------------
        B_APB_SETUP: begin
          psel    <= 1'b1;
          penable <= 1'b0;
          pwrite  <= is_write_xact;
          paddr   <= addr_capture;
          pwdata  <= wdata_capture;
          pstrb   <= wstrb_capture;
          state   <= B_APB_ACCESS;
        end

        B_APB_ACCESS: begin
          penable <= 1'b1;
          if (psel && penable && pready) begin
            psel    <= 1'b0;
            penable <= 1'b0;
            if (is_write_xact) state <= B_RESP_W;
            else               state <= B_RESP_R;
          end
        end

        // -------------------------------------------------------------
        // Complete the AXI-side response, using the APB result captured on the ACCESS->RESP edge.
        // -------------------------------------------------------------
        B_RESP_W: begin
          bvalid <= 1'b1;
          if (pslverr_latched) bresp <= RESP_SLVERR;
          else                 bresp <= RESP_OKAY;
          if (bvalid && bready) begin
            bvalid <= 1'b0;
            state  <= B_IDLE;
          end
        end

        B_RESP_R: begin
          rvalid <= 1'b1;
          rdata  <= prdata_latched;
          if (pslverr_latched) rresp <= RESP_SLVERR;
          else                 rresp <= RESP_OKAY;
          if (rvalid && rready) begin
            rvalid <= 1'b0;
            state  <= B_IDLE;
          end
        end
      endcase
    end
  end

  // Latch the APB result exactly on the ACCESS->RESP transition (pready reads combinationally off
  // apb_regbank while still in B_APB_ACCESS; must be captured before psel/penable drop, since
  // apb_regbank's own pslverr/prdata are only valid while it still sees itself selected).
  always_ff @(posedge clk) begin
    if (state == B_APB_ACCESS && psel && penable && pready) begin
      pslverr_latched <= pslverr;
      prdata_latched  <= prdata;
    end
  end

endmodule
