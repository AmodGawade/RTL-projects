// axi_lite_interconnect.sv
`timescale 1ns/1ps
// 2-master, 3-slave AXI4-Lite interconnect: fixed-priority arbitration (master 0 over master 1),
// combinational address decode, and a shared (not independently-pipelined) routing path per
// channel direction -- see docs/architecture.md for the full reasoning behind these choices.
//
// Simplifying assumption made at the arbiter (documented, not accidental): a write is granted only
// once a master presents AWVALID *and* WVALID together in the same cycle. This is a deliberately
// simpler contract than a fully general AXI interconnect (which must handle AW and W arriving with
// arbitrary skew) -- reasonable here because the downstream slaves (axi_lite_regfile.sv,
// axi_lite_to_apb_bridge.sv) already handle either-arrival-order robustly on their own, and the
// source doesn't claim independent AW/W skew tolerance at the interconnect's own arbitration level.
// Reads have no such restriction (ARVALID alone is enough to arbitrate).
//
// Real bug found and fixed by testing (see docs/verification.md): an earlier version only asserted
// AWREADY/WREADY/ARREADY while routing to a REAL slave (WR_ACTIVE/RD_ACTIVE); the DECERR grant
// cycle never acknowledged the requesting master's handshake at all, so an access to an unmapped
// address hung forever instead of erroring. Fixed by computing the grant decision (who, and
// whether the target is a real slave or DECERR) in one shared combinational block, and asserting
// the granted master's *READY in the SAME cycle for both outcomes.
import axi_lite_pkg::*;

module axi_lite_interconnect #(
  parameter int ADDR_WIDTH   = 16,
  parameter int DATA_WIDTH   = 32,
  parameter int S0_BASE      = 'h0000,
  parameter int S0_SIZE      = 'h1000,
  parameter int S1_BASE      = 'h1000,
  parameter int S1_SIZE      = 'h1000,
  parameter int S2_BASE      = 'h2000,
  parameter int S2_SIZE      = 'h1000
) (
  input  logic clk,
  input  logic aresetn,

  // ---------------- Master 0 (manager-facing slave port) ----------------
  input  logic                    m0_awvalid, output logic m0_awready, input  logic [ADDR_WIDTH-1:0] m0_awaddr,
  input  logic                    m0_wvalid,  output logic m0_wready,  input  logic [DATA_WIDTH-1:0]  m0_wdata,  input logic [DATA_WIDTH/8-1:0] m0_wstrb,
  output logic                    m0_bvalid,  input  logic m0_bready,  output logic [1:0]              m0_bresp,
  input  logic                    m0_arvalid, output logic m0_arready, input  logic [ADDR_WIDTH-1:0] m0_araddr,
  output logic                    m0_rvalid,  input  logic m0_rready,  output logic [DATA_WIDTH-1:0]  m0_rdata,  output logic [1:0] m0_rresp,

  // ---------------- Master 1 (manager-facing slave port) ----------------
  input  logic                    m1_awvalid, output logic m1_awready, input  logic [ADDR_WIDTH-1:0] m1_awaddr,
  input  logic                    m1_wvalid,  output logic m1_wready,  input  logic [DATA_WIDTH-1:0]  m1_wdata,  input logic [DATA_WIDTH/8-1:0] m1_wstrb,
  output logic                    m1_bvalid,  input  logic m1_bready,  output logic [1:0]              m1_bresp,
  input  logic                    m1_arvalid, output logic m1_arready, input  logic [ADDR_WIDTH-1:0] m1_araddr,
  output logic                    m1_rvalid,  input  logic m1_rready,  output logic [DATA_WIDTH-1:0]  m1_rdata,  output logic [1:0] m1_rresp,

  // ---------------- Slave 0 (master-facing port) ----------------
  output logic                    s0_awvalid, input  logic s0_awready, output logic [ADDR_WIDTH-1:0] s0_awaddr,
  output logic                    s0_wvalid,  input  logic s0_wready,  output logic [DATA_WIDTH-1:0]  s0_wdata,  output logic [DATA_WIDTH/8-1:0] s0_wstrb,
  input  logic                    s0_bvalid,  output logic s0_bready,  input  logic [1:0]              s0_bresp,
  output logic                    s0_arvalid, input  logic s0_arready, output logic [ADDR_WIDTH-1:0] s0_araddr,
  input  logic                    s0_rvalid,  output logic s0_rready,  input  logic [DATA_WIDTH-1:0]  s0_rdata,  input  logic [1:0] s0_rresp,

  // ---------------- Slave 1 (master-facing port) ----------------
  output logic                    s1_awvalid, input  logic s1_awready, output logic [ADDR_WIDTH-1:0] s1_awaddr,
  output logic                    s1_wvalid,  input  logic s1_wready,  output logic [DATA_WIDTH-1:0]  s1_wdata,  output logic [DATA_WIDTH/8-1:0] s1_wstrb,
  input  logic                    s1_bvalid,  output logic s1_bready,  input  logic [1:0]              s1_bresp,
  output logic                    s1_arvalid, input  logic s1_arready, output logic [ADDR_WIDTH-1:0] s1_araddr,
  input  logic                    s1_rvalid,  output logic s1_rready,  input  logic [DATA_WIDTH-1:0]  s1_rdata,  input  logic [1:0] s1_rresp,

  // ---------------- Slave 2 (master-facing port -- the AXI side of the APB bridge) ----------------
  output logic                    s2_awvalid, input  logic s2_awready, output logic [ADDR_WIDTH-1:0] s2_awaddr,
  output logic                    s2_wvalid,  input  logic s2_wready,  output logic [DATA_WIDTH-1:0]  s2_wdata,  output logic [DATA_WIDTH/8-1:0] s2_wstrb,
  input  logic                    s2_bvalid,  output logic s2_bready,  input  logic [1:0]              s2_bresp,
  output logic                    s2_arvalid, input  logic s2_arready, output logic [ADDR_WIDTH-1:0] s2_araddr,
  input  logic                    s2_rvalid,  output logic s2_rready,  input  logic [DATA_WIDTH-1:0]  s2_rdata,  input  logic [1:0] s2_rresp
);

  // 2'd0/1/2 = slave0/1/2 ; 2'd3 = no match (DECERR)
  function automatic logic [1:0] decode(input logic [ADDR_WIDTH-1:0] addr);
    if      (addr >= S0_BASE && addr < S0_BASE + S0_SIZE) decode = 2'd0;
    else if (addr >= S1_BASE && addr < S1_BASE + S1_SIZE) decode = 2'd1;
    else if (addr >= S2_BASE && addr < S2_BASE + S2_SIZE) decode = 2'd2;
    else                                                  decode = 2'd3;
  endfunction

  // =================================================================
  // WRITE PATH
  // =================================================================
  typedef enum logic [1:0] {WR_IDLE, WR_ACTIVE, WR_DECERR} wr_state_e;
  wr_state_e wr_state;
  logic       wr_owner;   // 0 = master0, 1 = master1 (valid only while wr_state != WR_IDLE)
  logic [1:0] wr_target;  // which slave (or 3 = DECERR), latched at grant time

  // ---- Combinational grant decision: who WOULD be granted this cycle, if we're in WR_IDLE and
  // someone requests. Shared by the state-transition logic AND the ready-signal logic below, so
  // the granted master's AWREADY/WREADY assert on the SAME cycle the grant is decided, whether the
  // outcome is a real slave or DECERR. ----
  logic       wr_grant_valid;
  logic       wr_grant_owner;
  logic [1:0] wr_grant_target;

  always_comb begin
    wr_grant_valid  = 1'b0;
    wr_grant_owner  = 1'b0;
    wr_grant_target = 2'd3;
    if (wr_state == WR_IDLE) begin
      if (m0_awvalid && m0_wvalid) begin
        wr_grant_valid  = 1'b1;
        wr_grant_owner  = 1'b0;
        wr_grant_target = decode(m0_awaddr);
      end else if (m1_awvalid && m1_wvalid) begin
        wr_grant_valid  = 1'b1;
        wr_grant_owner  = 1'b1;
        wr_grant_target = decode(m1_awaddr);
      end
    end
  end

  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      wr_state <= WR_IDLE;
      wr_owner <= 1'b0;
      wr_target <= 2'd0;
      m0_bvalid <= 1'b0; m0_bresp <= RESP_OKAY;
      m1_bvalid <= 1'b0; m1_bresp <= RESP_OKAY;
    end else begin
      case (wr_state)
        WR_IDLE: begin
          m0_bvalid <= 1'b0;
          m1_bvalid <= 1'b0;
          if (wr_grant_valid) begin
            wr_owner  <= wr_grant_owner;
            wr_target <= wr_grant_target;
            if (wr_grant_target == 2'd3) begin
              wr_state <= WR_DECERR;
              if (wr_grant_owner == 1'b0) begin m0_bvalid <= 1'b1; m0_bresp <= RESP_DECERR; end
              else                        begin m1_bvalid <= 1'b1; m1_bresp <= RESP_DECERR; end
            end else begin
              wr_state <= WR_ACTIVE;
            end
          end
        end

        WR_ACTIVE: begin
          // Forward the targeted slave's BVALID/BRESP to whichever master is granted.
          case (wr_target)
            2'd0: if (wr_owner == 1'b0) begin m0_bvalid <= s0_bvalid; m0_bresp <= s0_bresp; end
                  else                  begin m1_bvalid <= s0_bvalid; m1_bresp <= s0_bresp; end
            2'd1: if (wr_owner == 1'b0) begin m0_bvalid <= s1_bvalid; m0_bresp <= s1_bresp; end
                  else                  begin m1_bvalid <= s1_bvalid; m1_bresp <= s1_bresp; end
            2'd2: if (wr_owner == 1'b0) begin m0_bvalid <= s2_bvalid; m0_bresp <= s2_bresp; end
                  else                  begin m1_bvalid <= s2_bvalid; m1_bresp <= s2_bresp; end
            default: ;
          endcase
          // Completion is detected by watching the GRANTED master's own bvalid/bready.
          if (wr_owner == 1'b0 && m0_bvalid && m0_bready) begin wr_state <= WR_IDLE; m0_bvalid <= 1'b0; end
          if (wr_owner == 1'b1 && m1_bvalid && m1_bready) begin wr_state <= WR_IDLE; m1_bvalid <= 1'b0; end
        end

        WR_DECERR: begin
          if (wr_owner == 1'b0) begin
            if (m0_bvalid && m0_bready) begin m0_bvalid <= 1'b0; wr_state <= WR_IDLE; end
          end else begin
            if (m1_bvalid && m1_bready) begin m1_bvalid <= 1'b0; wr_state <= WR_IDLE; end
          end
        end
      endcase
    end
  end

  // ---- Combinational routing: AWREADY/WREADY for the granted master, and AW/W/B forwarding to
  // whichever slave is targeted. Covers BOTH the WR_ACTIVE case (forward from/to a real slave) AND
  // the DECERR grant cycle itself (wr_state still WR_IDLE this cycle, but wr_grant_valid &&
  // wr_grant_target==3) -- this second case is exactly the one an earlier version of this file
  // missed, causing a hung master (see file header).
  always_comb begin
    m0_awready = 1'b0; m0_wready = 1'b0;
    m1_awready = 1'b0; m1_wready = 1'b0;
    s0_awvalid = 1'b0; s0_awaddr = '0; s0_wvalid = 1'b0; s0_wdata = '0; s0_wstrb = '0; s0_bready = 1'b0;
    s1_awvalid = 1'b0; s1_awaddr = '0; s1_wvalid = 1'b0; s1_wdata = '0; s1_wstrb = '0; s1_bready = 1'b0;
    s2_awvalid = 1'b0; s2_awaddr = '0; s2_wvalid = 1'b0; s2_wdata = '0; s2_wstrb = '0; s2_bready = 1'b0;

    if (wr_state == WR_ACTIVE) begin
      case (wr_target)
        2'd0: begin
          if (wr_owner == 1'b0) begin
            s0_awvalid = m0_awvalid; s0_awaddr = m0_awaddr;
            s0_wvalid  = m0_wvalid;  s0_wdata  = m0_wdata;  s0_wstrb = m0_wstrb;
            m0_awready = s0_awready; m0_wready = s0_wready;
            s0_bready  = m0_bready;
          end else begin
            s0_awvalid = m1_awvalid; s0_awaddr = m1_awaddr;
            s0_wvalid  = m1_wvalid;  s0_wdata  = m1_wdata;  s0_wstrb = m1_wstrb;
            m1_awready = s0_awready; m1_wready = s0_wready;
            s0_bready  = m1_bready;
          end
        end
        2'd1: begin
          if (wr_owner == 1'b0) begin
            s1_awvalid = m0_awvalid; s1_awaddr = m0_awaddr;
            s1_wvalid  = m0_wvalid;  s1_wdata  = m0_wdata;  s1_wstrb = m0_wstrb;
            m0_awready = s1_awready; m0_wready = s1_wready;
            s1_bready  = m0_bready;
          end else begin
            s1_awvalid = m1_awvalid; s1_awaddr = m1_awaddr;
            s1_wvalid  = m1_wvalid;  s1_wdata  = m1_wdata;  s1_wstrb = m1_wstrb;
            m1_awready = s1_awready; m1_wready = s1_wready;
            s1_bready  = m1_bready;
          end
        end
        2'd2: begin
          if (wr_owner == 1'b0) begin
            s2_awvalid = m0_awvalid; s2_awaddr = m0_awaddr;
            s2_wvalid  = m0_wvalid;  s2_wdata  = m0_wdata;  s2_wstrb = m0_wstrb;
            m0_awready = s2_awready; m0_wready = s2_wready;
            s2_bready  = m0_bready;
          end else begin
            s2_awvalid = m1_awvalid; s2_awaddr = m1_awaddr;
            s2_wvalid  = m1_wvalid;  s2_wdata  = m1_wdata;  s2_wstrb = m1_wstrb;
            m1_awready = s2_awready; m1_wready = s2_wready;
            s2_bready  = m1_bready;
          end
        end
        default: ; // wr_target==3 (DECERR) has no real slave traffic
      endcase
    end else if (wr_grant_valid && wr_grant_target == 2'd3) begin
      // DECERR grant cycle: acknowledge the requesting master's AW+W right now, even though
      // wr_state itself only transitions to WR_DECERR on the next edge.
      if (wr_grant_owner == 1'b0) begin m0_awready = 1'b1; m0_wready = 1'b1; end
      else                        begin m1_awready = 1'b1; m1_wready = 1'b1; end
    end
  end

  // =================================================================
  // READ PATH (symmetric to the write path, no W-channel complexity)
  // =================================================================
  typedef enum logic [1:0] {RD_IDLE, RD_ACTIVE, RD_DECERR} rd_state_e;
  rd_state_e rd_state;
  logic       rd_owner;
  logic [1:0] rd_target;

  logic       rd_grant_valid;
  logic       rd_grant_owner;
  logic [1:0] rd_grant_target;

  always_comb begin
    rd_grant_valid  = 1'b0;
    rd_grant_owner  = 1'b0;
    rd_grant_target = 2'd3;
    if (rd_state == RD_IDLE) begin
      if (m0_arvalid) begin
        rd_grant_valid  = 1'b1;
        rd_grant_owner  = 1'b0;
        rd_grant_target = decode(m0_araddr);
      end else if (m1_arvalid) begin
        rd_grant_valid  = 1'b1;
        rd_grant_owner  = 1'b1;
        rd_grant_target = decode(m1_araddr);
      end
    end
  end

  always_ff @(posedge clk or negedge aresetn) begin
    if (!aresetn) begin
      rd_state <= RD_IDLE;
      rd_owner <= 1'b0;
      rd_target <= 2'd0;
      m0_rvalid <= 1'b0; m0_rresp <= RESP_OKAY; m0_rdata <= '0;
      m1_rvalid <= 1'b0; m1_rresp <= RESP_OKAY; m1_rdata <= '0;
    end else begin
      case (rd_state)
        RD_IDLE: begin
          m0_rvalid <= 1'b0;
          m1_rvalid <= 1'b0;
          if (rd_grant_valid) begin
            rd_owner  <= rd_grant_owner;
            rd_target <= rd_grant_target;
            if (rd_grant_target == 2'd3) begin
              rd_state <= RD_DECERR;
              if (rd_grant_owner == 1'b0) begin m0_rvalid <= 1'b1; m0_rresp <= RESP_DECERR; m0_rdata <= '0; end
              else                        begin m1_rvalid <= 1'b1; m1_rresp <= RESP_DECERR; m1_rdata <= '0; end
            end else begin
              rd_state <= RD_ACTIVE;
            end
          end
        end

        RD_ACTIVE: begin
          case (rd_target)
            2'd0: if (rd_owner == 1'b0) begin m0_rvalid <= s0_rvalid; m0_rresp <= s0_rresp; m0_rdata <= s0_rdata; end
                  else                  begin m1_rvalid <= s0_rvalid; m1_rresp <= s0_rresp; m1_rdata <= s0_rdata; end
            2'd1: if (rd_owner == 1'b0) begin m0_rvalid <= s1_rvalid; m0_rresp <= s1_rresp; m0_rdata <= s1_rdata; end
                  else                  begin m1_rvalid <= s1_rvalid; m1_rresp <= s1_rresp; m1_rdata <= s1_rdata; end
            2'd2: if (rd_owner == 1'b0) begin m0_rvalid <= s2_rvalid; m0_rresp <= s2_rresp; m0_rdata <= s2_rdata; end
                  else                  begin m1_rvalid <= s2_rvalid; m1_rresp <= s2_rresp; m1_rdata <= s2_rdata; end
            default: ;
          endcase
          if (rd_owner == 1'b0 && m0_rvalid && m0_rready) begin rd_state <= RD_IDLE; m0_rvalid <= 1'b0; end
          if (rd_owner == 1'b1 && m1_rvalid && m1_rready) begin rd_state <= RD_IDLE; m1_rvalid <= 1'b0; end
        end

        RD_DECERR: begin
          if (rd_owner == 1'b0) begin
            if (m0_rvalid && m0_rready) begin m0_rvalid <= 1'b0; rd_state <= RD_IDLE; end
          end else begin
            if (m1_rvalid && m1_rready) begin m1_rvalid <= 1'b0; rd_state <= RD_IDLE; end
          end
        end
      endcase
    end
  end

  always_comb begin
    m0_arready = 1'b0; m1_arready = 1'b0;
    s0_arvalid = 1'b0; s0_araddr = '0; s0_rready = 1'b0;
    s1_arvalid = 1'b0; s1_araddr = '0; s1_rready = 1'b0;
    s2_arvalid = 1'b0; s2_araddr = '0; s2_rready = 1'b0;

    if (rd_state == RD_ACTIVE) begin
      case (rd_target)
        2'd0: begin
          if (rd_owner == 1'b0) begin s0_arvalid = m0_arvalid; s0_araddr = m0_araddr; m0_arready = s0_arready; s0_rready = m0_rready; end
          else                  begin s0_arvalid = m1_arvalid; s0_araddr = m1_araddr; m1_arready = s0_arready; s0_rready = m1_rready; end
        end
        2'd1: begin
          if (rd_owner == 1'b0) begin s1_arvalid = m0_arvalid; s1_araddr = m0_araddr; m0_arready = s1_arready; s1_rready = m0_rready; end
          else                  begin s1_arvalid = m1_arvalid; s1_araddr = m1_araddr; m1_arready = s1_arready; s1_rready = m1_rready; end
        end
        2'd2: begin
          if (rd_owner == 1'b0) begin s2_arvalid = m0_arvalid; s2_araddr = m0_araddr; m0_arready = s2_arready; s2_rready = m0_rready; end
          else                  begin s2_arvalid = m1_arvalid; s2_araddr = m1_araddr; m1_arready = s2_arready; s2_rready = m1_rready; end
        end
        default: ;
      endcase
    end else if (rd_grant_valid && rd_grant_target == 2'd3) begin
      // DECERR grant cycle: same fix as the write side above.
      if (rd_grant_owner == 1'b0) m0_arready = 1'b1;
      else                        m1_arready = 1'b1;
    end
  end

endmodule
