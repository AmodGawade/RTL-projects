// tb_axi_lite_apb_interconnect.sv
// Self-checking testbench for the full system: 2 AXI4-Lite masters -> axi_lite_interconnect ->
// {axi_lite_regfile, axi_lite_regfile, axi_lite_to_apb_bridge -> apb_regbank}.
`timescale 1ns/1ps

module tb_axi_lite_apb_interconnect;

  localparam int ADDR_WIDTH = 16;
  localparam int DATA_WIDTH = 32;
  localparam int S0_BASE = 'h0000, S0_SIZE = 'h1000;
  localparam int S1_BASE = 'h1000, S1_SIZE = 'h1000;
  localparam int S2_BASE = 'h2000, S2_SIZE = 'h1000;

  logic clk = 0, aresetn = 0;
  always #5 clk = ~clk;

  // ---------------- Master 0 / Master 1 signals ----------------
  logic m0_awvalid=0, m0_awready, m0_wvalid=0, m0_wready, m0_bvalid, m0_bready=0;
  logic [ADDR_WIDTH-1:0] m0_awaddr=0; logic [DATA_WIDTH-1:0] m0_wdata=0; logic [DATA_WIDTH/8-1:0] m0_wstrb=0; logic [1:0] m0_bresp;
  logic m0_arvalid=0, m0_arready, m0_rvalid, m0_rready=0; logic [ADDR_WIDTH-1:0] m0_araddr=0;
  logic [DATA_WIDTH-1:0] m0_rdata; logic [1:0] m0_rresp;

  logic m1_awvalid=0, m1_awready, m1_wvalid=0, m1_wready, m1_bvalid, m1_bready=0;
  logic [ADDR_WIDTH-1:0] m1_awaddr=0; logic [DATA_WIDTH-1:0] m1_wdata=0; logic [DATA_WIDTH/8-1:0] m1_wstrb=0; logic [1:0] m1_bresp;
  logic m1_arvalid=0, m1_arready, m1_rvalid, m1_rready=0; logic [ADDR_WIDTH-1:0] m1_araddr=0;
  logic [DATA_WIDTH-1:0] m1_rdata; logic [1:0] m1_rresp;

  // ---------------- Slave-facing signals (interconnect <-> downstream slaves) ----------------
  logic s0_awvalid, s0_awready, s0_wvalid, s0_wready, s0_bvalid, s0_bready;
  logic [ADDR_WIDTH-1:0] s0_awaddr; logic [DATA_WIDTH-1:0] s0_wdata; logic [DATA_WIDTH/8-1:0] s0_wstrb; logic [1:0] s0_bresp;
  logic s0_arvalid, s0_arready, s0_rvalid, s0_rready; logic [ADDR_WIDTH-1:0] s0_araddr;
  logic [DATA_WIDTH-1:0] s0_rdata; logic [1:0] s0_rresp;

  logic s1_awvalid, s1_awready, s1_wvalid, s1_wready, s1_bvalid, s1_bready;
  logic [ADDR_WIDTH-1:0] s1_awaddr; logic [DATA_WIDTH-1:0] s1_wdata; logic [DATA_WIDTH/8-1:0] s1_wstrb; logic [1:0] s1_bresp;
  logic s1_arvalid, s1_arready, s1_rvalid, s1_rready; logic [ADDR_WIDTH-1:0] s1_araddr;
  logic [DATA_WIDTH-1:0] s1_rdata; logic [1:0] s1_rresp;

  logic s2_awvalid, s2_awready, s2_wvalid, s2_wready, s2_bvalid, s2_bready;
  logic [ADDR_WIDTH-1:0] s2_awaddr; logic [DATA_WIDTH-1:0] s2_wdata; logic [DATA_WIDTH/8-1:0] s2_wstrb; logic [1:0] s2_bresp;
  logic s2_arvalid, s2_arready, s2_rvalid, s2_rready; logic [ADDR_WIDTH-1:0] s2_araddr;
  logic [DATA_WIDTH-1:0] s2_rdata; logic [1:0] s2_rresp;

  // ---------------- APB bridge <-> apb_regbank ----------------
  logic psel, penable, pwrite; logic [ADDR_WIDTH-1:0] paddr; logic [DATA_WIDTH-1:0] pwdata; logic [DATA_WIDTH/8-1:0] pstrb;
  logic pready, pslverr; logic [DATA_WIDTH-1:0] prdata;

  axi_lite_interconnect #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
    .S0_BASE(S0_BASE), .S0_SIZE(S0_SIZE), .S1_BASE(S1_BASE), .S1_SIZE(S1_SIZE),
    .S2_BASE(S2_BASE), .S2_SIZE(S2_SIZE)
  ) dut_interconnect (.*);

  axi_lite_regfile #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .NUM_REGS(16)) dut_slave0 (
    .clk(clk), .aresetn(aresetn),
    .awvalid(s0_awvalid), .awready(s0_awready), .awaddr(s0_awaddr),
    .wvalid(s0_wvalid), .wready(s0_wready), .wdata(s0_wdata), .wstrb(s0_wstrb),
    .bvalid(s0_bvalid), .bready(s0_bready), .bresp(s0_bresp),
    .arvalid(s0_arvalid), .arready(s0_arready), .araddr(s0_araddr),
    .rvalid(s0_rvalid), .rready(s0_rready), .rdata(s0_rdata), .rresp(s0_rresp)
  );

  axi_lite_regfile #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .NUM_REGS(16)) dut_slave1 (
    .clk(clk), .aresetn(aresetn),
    .awvalid(s1_awvalid), .awready(s1_awready), .awaddr(s1_awaddr),
    .wvalid(s1_wvalid), .wready(s1_wready), .wdata(s1_wdata), .wstrb(s1_wstrb),
    .bvalid(s1_bvalid), .bready(s1_bready), .bresp(s1_bresp),
    .arvalid(s1_arvalid), .arready(s1_arready), .araddr(s1_araddr),
    .rvalid(s1_rvalid), .rready(s1_rready), .rdata(s1_rdata), .rresp(s1_rresp)
  );

  axi_lite_to_apb_bridge #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) dut_bridge (
    .clk(clk), .aresetn(aresetn),
    .awvalid(s2_awvalid), .awready(s2_awready), .awaddr(s2_awaddr),
    .wvalid(s2_wvalid), .wready(s2_wready), .wdata(s2_wdata), .wstrb(s2_wstrb),
    .bvalid(s2_bvalid), .bready(s2_bready), .bresp(s2_bresp),
    .arvalid(s2_arvalid), .arready(s2_arready), .araddr(s2_araddr),
    .rvalid(s2_rvalid), .rready(s2_rready), .rdata(s2_rdata), .rresp(s2_rresp),
    .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata), .pstrb(pstrb),
    .pready(pready), .prdata(prdata), .pslverr(pslverr)
  );

  apb_regbank #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                .BASE_ADDR(S2_BASE), .APERTURE_SIZE(S2_SIZE), .NUM_REGS(8), .WAIT_CYCLES(1)) dut_apb (
    .pclk(clk), .presetn(aresetn),
    .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata), .pstrb(pstrb),
    .pready(pready), .prdata(prdata), .pslverr(pslverr)
  );

  // =================================================================
  // Shadow model: what SHOULD be in each of the 3 address regions. Independent of the RTL, built
  // purely from what this testbench itself writes -- the actual scoreboard.
  // =================================================================
  logic [DATA_WIDTH-1:0] shadow_s0 [0:15];
  logic [DATA_WIDTH-1:0] shadow_s1 [0:15];
  logic [DATA_WIDTH-1:0] shadow_s2 [0:7];
  int unsigned checks_done = 0;
  int unsigned mismatches  = 0;

  // =================================================================
  // Master driver tasks (one set per master, parameterized by which signal bundle to drive).
  // Following the async_fifo project's proven race-avoidance discipline: drive on negedge, the
  // DUT (and our own checks) sample on posedge.
  // =================================================================

  // ---- Master 0 write/read ----
  task automatic m0_write(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data, output logic [1:0] resp);
    @(negedge clk);
    m0_awvalid <= 1; m0_awaddr <= addr;
    m0_wvalid  <= 1; m0_wdata  <= data; m0_wstrb <= '1;
    @(posedge clk);
    while (!(m0_awvalid && m0_awready)) @(posedge clk);
    @(negedge clk);
    m0_awvalid <= 0; m0_wvalid <= 0;
    m0_bready <= 1;
    @(posedge clk);
    while (!m0_bvalid) @(posedge clk);
    resp = m0_bresp;
    @(negedge clk);
    m0_bready <= 0;
  endtask

  task automatic m0_read(input logic [ADDR_WIDTH-1:0] addr, output logic [DATA_WIDTH-1:0] data, output logic [1:0] resp);
    @(negedge clk);
    m0_arvalid <= 1; m0_araddr <= addr;
    @(posedge clk);
    while (!(m0_arvalid && m0_arready)) @(posedge clk);
    @(negedge clk);
    m0_arvalid <= 0;
    m0_rready <= 1;
    @(posedge clk);
    while (!m0_rvalid) @(posedge clk);
    data = m0_rdata; resp = m0_rresp;
    @(negedge clk);
    m0_rready <= 0;
  endtask

  // ---- Master 1 write/read (identical structure, separate signals -- genuinely independent) ----
  task automatic m1_write(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data, output logic [1:0] resp);
    @(negedge clk);
    m1_awvalid <= 1; m1_awaddr <= addr;
    m1_wvalid  <= 1; m1_wdata  <= data; m1_wstrb <= '1;
    @(posedge clk);
    while (!(m1_awvalid && m1_awready)) @(posedge clk);
    @(negedge clk);
    m1_awvalid <= 0; m1_wvalid <= 0;
    m1_bready <= 1;
    @(posedge clk);
    while (!m1_bvalid) @(posedge clk);
    resp = m1_bresp;
    @(negedge clk);
    m1_bready <= 0;
  endtask

  task automatic m1_read(input logic [ADDR_WIDTH-1:0] addr, output logic [DATA_WIDTH-1:0] data, output logic [1:0] resp);
    @(negedge clk);
    m1_arvalid <= 1; m1_araddr <= addr;
    @(posedge clk);
    while (!(m1_arvalid && m1_arready)) @(posedge clk);
    @(negedge clk);
    m1_arvalid <= 0;
    m1_rready <= 1;
    @(posedge clk);
    while (!m1_rvalid) @(posedge clk);
    data = m1_rdata; resp = m1_rresp;
    @(negedge clk);
    m1_rready <= 0;
  endtask

  // =================================================================
  // Checked write/read wrappers: drive the transaction, update/compare against the shadow model.
  // region: 0/1/2 selects which shadow array; word_idx is the register index within that region.
  // =================================================================
  logic [1:0] sb_resp;
  logic [DATA_WIDTH-1:0] sb_rdata;

  // Phase 5 randomized-traffic scratch vars (module scope, blocking-assigned in the loop -- see
  // that phase's comment for why they're not declared-with-initializer locals inside the loop).
  int rnd_region, rnd_max_idx, rnd_idx, rnd_master;
  logic [DATA_WIDTH-1:0] rnd_data;

  task automatic check_write(input int master, input int region, input int word_idx, input logic [DATA_WIDTH-1:0] data, input bit expect_error);
    logic [ADDR_WIDTH-1:0] addr;
    case (region)
      0: addr = S0_BASE + (word_idx << 2);
      1: addr = S1_BASE + (word_idx << 2);
      2: addr = S2_BASE + (word_idx << 2);
      default: addr = '1; // deliberately unmapped
    endcase
    if (master == 0) m0_write(addr, data, sb_resp);
    else              m1_write(addr, data, sb_resp);
    checks_done++;
    if (expect_error) begin
      if (sb_resp == 2'b00) begin
        $error("[SB] write to region=%0d idx=%0d expected an error response, got OKAY", region, word_idx);
        mismatches++;
      end
    end else begin
      if (sb_resp != 2'b00) begin
        $error("[SB] write to region=%0d idx=%0d expected OKAY, got resp=%0d", region, word_idx, sb_resp);
        mismatches++;
      end else begin
        case (region)
          0: shadow_s0[word_idx] = data;
          1: shadow_s1[word_idx] = data;
          2: shadow_s2[word_idx] = data;
          default: ;
        endcase
      end
    end
  endtask

  task automatic check_read(input int master, input int region, input int word_idx, input bit expect_error);
    logic [ADDR_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0] expected;
    case (region)
      0: begin addr = S0_BASE + (word_idx << 2); expected = shadow_s0[word_idx]; end
      1: begin addr = S1_BASE + (word_idx << 2); expected = shadow_s1[word_idx]; end
      2: begin addr = S2_BASE + (word_idx << 2); expected = shadow_s2[word_idx]; end
      default: begin addr = '1; expected = '0; end
    endcase
    if (master == 0) m0_read(addr, sb_rdata, sb_resp);
    else              m1_read(addr, sb_rdata, sb_resp);
    checks_done++;
    if (expect_error) begin
      if (sb_resp == 2'b00) begin
        $error("[SB] read from region=%0d idx=%0d expected an error response, got OKAY", region, word_idx);
        mismatches++;
      end
    end else begin
      if (sb_resp != 2'b00) begin
        $error("[SB] read from region=%0d idx=%0d expected OKAY, got resp=%0d", region, word_idx, sb_resp);
        mismatches++;
      end else if (sb_rdata !== expected) begin
        $error("[SB] read from region=%0d idx=%0d MISMATCH expected=0x%0h actual=0x%0h", region, word_idx, expected, sb_rdata);
        mismatches++;
      end
    end
  endtask

  // =================================================================
  // Test sequence
  // =================================================================
  initial begin
    int seed;
    if (!$value$plusargs("seed=%d", seed)) seed = 1;
    void'($urandom(seed));
    $display("[TB] seed=%0d", seed);

    for (int i = 0; i < 16; i++) begin shadow_s0[i] = '0; shadow_s1[i] = '0; end
    for (int i = 0; i < 8; i++)  shadow_s2[i] = '0;

    aresetn = 0;
    repeat (5) @(negedge clk);
    aresetn = 1;
    repeat (2) @(posedge clk);

    // ---- Phase 1: directed single-master traffic to each of the 3 regions ----
    $display("[TB] Phase 1: directed single-master access to all 3 regions");
    check_write(0, 0, 3,  32'hAAAA_0001, 0);
    check_read (0, 0, 3,  0);
    check_write(0, 1, 5,  32'hBBBB_0002, 0);
    check_read (0, 1, 5,  0);
    check_write(0, 2, 2,  32'hCCCC_0003, 0); // routes through the APB bridge
    check_read (0, 2, 2,  0);

    // ---- Phase 2: error handling -- unmapped address, and past-aperture APB address ----
    $display("[TB] Phase 2: error handling");
    check_read(0, 3, 0, 1);              // region 3 = deliberately unmapped -> DECERR
    check_write(0, 3, 0, 32'hDEAD_DEAD, 1);
    // APB region word 100 is within S2's 4KB aperture but beyond apb_regbank's own NUM_REGS=8 ->
    // apb_regbank returns PSLVERR, bridge maps it to SLVERR (distinct from DECERR above).
    check_read(0, 2, 100, 1);

    // ---- Phase 3: both masters contend for the SAME region concurrently ----
    $display("[TB] Phase 3: concurrent contention, both masters -> region 0");
    fork
      check_write(0, 0, 1, 32'h1111_1111, 0);
      check_write(1, 0, 6, 32'h2222_2222, 0);
    join
    check_read(0, 0, 1, 0);
    check_read(1, 0, 6, 0);

    // ---- Phase 4: both masters contend for DIFFERENT regions concurrently ----
    $display("[TB] Phase 4: concurrent access, different regions (m0->region1, m1->region2/APB)");
    fork
      check_write(0, 1, 9, 32'h3333_3333, 0);
      check_write(1, 2, 4, 32'h4444_4444, 0);
    join
    check_read(0, 1, 9, 0);
    check_read(1, 2, 4, 0);

    // ---- Phase 5: randomized traffic across both masters, all 3 regions ----
    // Loop-local scratch vars hoisted above the loop with blocking assignment at point of use --
    // NOT declared-with-initializer inside the loop body. See async_fifo's docs/verification.md
    // "toolchain gotchas" #6: that pattern's initializer only evaluates once (effectively at
    // elaboration time) under this simulator, not fresh on every loop iteration.
    $display("[TB] Phase 5: randomized traffic");
    for (int i = 0; i < 60; i++) begin
      rnd_region  = $urandom_range(0, 2);
      rnd_max_idx = (rnd_region == 2) ? 7 : 15;
      rnd_idx     = $urandom_range(0, rnd_max_idx);
      rnd_data    = $urandom;
      rnd_master  = $urandom_range(0, 1);
      if ($urandom_range(0, 1)) check_write(rnd_master, rnd_region, rnd_idx, rnd_data, 0);
      else                      check_read(rnd_master, rnd_region, rnd_idx, 0);
    end

    $display("==============================================");
    $display("[TB] FINAL: checks_done=%0d mismatches=%0d", checks_done, mismatches);
    if (mismatches == 0) $display("[TB] RESULT: PASS");
    else                 $display("[TB] RESULT: FAIL");
    $display("==============================================");
    $finish;
  end

  initial begin
    #500000;
    $display("[TB] TIMEOUT");
    $finish;
  end

endmodule
