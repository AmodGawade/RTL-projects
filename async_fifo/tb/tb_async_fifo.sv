// tb_async_fifo.sv
// Self-checking testbench for async_fifo. See docs/verification.md for the full verification
// strategy (what's tested, what would count as functional coverage, what bugs this targets).
//
// Race-avoidance discipline (no SystemVerilog clocking blocks -- Icarus Verilog does not support
// them; confirmed by direct test before writing this file): all stimulus is driven on the
// NEGEDGE of its own domain's clock, and all sampling/checking happens on the POSEDGE. Since
// negedge and posedge never coincide, a value driven at negedge is always fully settled and
// race-free by the time the following posedge samples it -- this gives the same race-free
// guarantee a clocking block would, without needing clocking-block syntax.
`timescale 1ns/1ps

module tb_async_fifo;

  // ---------------------------------------------------------------
  // Parameters -- overridden from the command line by sim/run_sim.sh for depth/width sweeps
  // ---------------------------------------------------------------
  parameter int DATA_WIDTH = 8;
  parameter int DEPTH      = 16;
  localparam int ADDR_WIDTH = $clog2(DEPTH);

  parameter int RANDOM_TRANSACTIONS = 4000; // enough to wrap a DEPTH=16 pointer 100+ times over

  // ---------------------------------------------------------------
  // DUT hookup
  // ---------------------------------------------------------------
  logic                  wr_clk, wr_arst_n, wr_en, full;
  logic [DATA_WIDTH-1:0] wdata;
  logic                  rd_clk, rd_arst_n, rd_en, empty;
  logic [DATA_WIDTH-1:0] rdata;

  async_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
    .wr_clk    (wr_clk),
    .wr_arst_n (wr_arst_n),
    .wr_en     (wr_en),
    .wdata     (wdata),
    .full      (full),
    .rd_clk    (rd_clk),
    .rd_arst_n (rd_arst_n),
    .rd_en     (rd_en),
    .rdata     (rdata),
    .empty     (empty)
  );

  // ---------------------------------------------------------------
  // Independent, randomized clocks -- this IS the thing under test (the whole design exists
  // because these two clocks have no fixed phase/frequency relationship).
  // ---------------------------------------------------------------
  real wr_period_ns = 10.0;
  real rd_period_ns = 17.0;

  initial begin
    int seed;
    if (!$value$plusargs("seed=%d", seed)) seed = 1;
    void'($urandom(seed));
    // Randomize the read period independently of the write period, bounded to a range that
    // exercises both "read domain faster" and "read domain much slower" without making the sim
    // absurdly long. Deliberately not an integer multiple of wr_period_ns in general.
    rd_period_ns = $itor($urandom_range(3, 37));
    $display("[TB] seed=%0d wr_period_ns=%0.1f rd_period_ns=%0.1f DEPTH=%0d DATA_WIDTH=%0d",
              seed, wr_period_ns, rd_period_ns, DEPTH, DATA_WIDTH);
  end

  initial begin wr_clk = 1'b0; forever #(wr_period_ns/2.0) wr_clk = ~wr_clk; end
  initial begin rd_clk = 1'b0; forever #(rd_period_ns/2.0) rd_clk = ~rd_clk; end

  // ---------------------------------------------------------------
  // Scoreboard state
  // ---------------------------------------------------------------
  bit [DATA_WIDTH-1:0] expected_q[$];
  int unsigned writes_accepted   = 0;
  int unsigned reads_checked     = 0;
  int unsigned mismatches        = 0;
  bit          scoreboard_active = 1'b0; // held low during/just after a reset pulse

  // Write-side monitor: fires every wr_clk, values are already settled (driven at the prior negedge)
  always @(posedge wr_clk) begin
    if (scoreboard_active && wr_en && !full) begin
      expected_q.push_back(wdata);
      writes_accepted++;
    end
  end

  // Read-side monitor
  bit [DATA_WIDTH-1:0] sb_exp_val; // scratch var for the popped expected value (see note below)

  always @(posedge rd_clk) begin
    if (scoreboard_active && rd_en && !empty) begin
      if (expected_q.size() == 0) begin
        $error("[SCOREBOARD] t=%0t: read accepted (rd_en&&!empty) but expected queue is empty", $time);
        mismatches++;
      end else begin
        // Deliberately a module-level scratch variable assigned with blocking `=`, NOT a
        // declared-with-initializer local inside this begin/end. An earlier version declared
        // `exp` inline here (`bit [W-1:0] exp = expected_q.pop_front();`) and it silently stuck
        // at X for the entire run under this simulator -- a real, confirmed toolchain gotcha with
        // static (non-automatic) local declarations-with-initializers inside `always` blocks, not
        // a DUT bug. See docs/verification.md's "toolchain gotchas" section.
        sb_exp_val = expected_q.pop_front();
        reads_checked++;
        if (rdata !== sb_exp_val) begin
          $error("[SCOREBOARD] t=%0t: MISMATCH expected=0x%0h actual=0x%0h", $time, sb_exp_val, rdata);
          mismatches++;
        end
      end
    end
  end

  // ---------------------------------------------------------------
  // Reset task -- asserts both domains' resets, deasserts them skewed relative to each other
  // (they can't be deasserted on "the same edge" anyway since the clocks are asynchronous; this
  // models that honestly instead of pretending a synchronized dual-domain reset is possible).
  // Only ever called while the FIFO is confirmed drained (see docs/architecture.md's documented
  // limitation: this design assumes reset happens at a quiescent point, not with data in flight --
  // resetting one side alone while the other still holds unread data desyncs the pointers/memory
  // by construction, which is a real, known limitation of this classic architecture, not a bug
  // this testbench works around).
  // ---------------------------------------------------------------
  task automatic apply_reset(int wr_cycles, int rd_cycles);
    scoreboard_active = 1'b0;
    wr_arst_n = 1'b0;
    rd_arst_n = 1'b0;
    fork
      begin
        repeat (wr_cycles) @(negedge wr_clk);
        wr_arst_n = 1'b1;
      end
      begin
        repeat (rd_cycles) @(negedge rd_clk);
        rd_arst_n = 1'b1;
      end
    join
    // Wait a few extra cycles on the slower clock for the reset synchronizers themselves to
    // release and for the pointer-synchronizer pipeline to flush to a known state. Caller checks
    // empty/full after this task returns (see Phase 6 below).
    repeat (4) @(posedge wr_clk);
    repeat (4) @(posedge rd_clk);
  endtask

  // ---------------------------------------------------------------
  // Directed driver primitives (negedge-aligned, race-free — see file header)
  // ---------------------------------------------------------------
  task automatic wr_push(bit [DATA_WIDTH-1:0] data);
    @(negedge wr_clk);
    wr_en <= 1'b1;
    wdata <= data;
    @(posedge wr_clk); // let the monitor observe this cycle
    @(negedge wr_clk);
    wr_en <= 1'b0;
  endtask

  task automatic rd_pop();
    @(negedge rd_clk);
    rd_en <= 1'b1;
    @(posedge rd_clk);
    @(negedge rd_clk);
    rd_en <= 1'b0;
  endtask

  // Free-running random traffic generators, gated by enable bits so directed tests can pause them
  bit wr_random_mode = 1'b0;
  bit rd_random_mode = 1'b0;

  always @(negedge wr_clk) begin
    if (wr_random_mode) begin
      wr_en <= $urandom_range(0, 99) < 70; // ~70% attempt rate -- keeps FIFO genuinely exercised
      wdata <= $urandom;
    end
  end

  always @(negedge rd_clk) begin
    if (rd_random_mode) begin
      rd_en <= $urandom_range(0, 99) < 70;
    end
  end

  // ---------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------
  int errors_before;
  // Scratch "before" counters for the boundary tests below. Declared here (module scope, blocking
  // assignment at point of use) rather than as declared-with-initializer locals inside a begin/end
  // -- see the scoreboard's sb_exp_val comment above for why: this simulator evaluates that form's
  // initializer at elaboration time (t=0), not at the point program flow reaches it, which silently
  // produced wrong "before" values here in an earlier version of this file.
  int wa_before, rc_before;

  initial begin
    wr_en = 1'b0; wdata = '0; wr_arst_n = 1'b0;
    rd_en = 1'b0; rd_arst_n = 1'b0;

    // ---- Phase 0: power-on reset, skewed deassertion across domains ----
    $display("[TB] Phase 0: power-on reset");
    fork
      begin repeat (3) @(negedge wr_clk); wr_arst_n = 1'b1; end
      begin repeat (7) @(negedge rd_clk); rd_arst_n = 1'b1; end // deliberately skewed vs wr side
    join
    repeat (4) @(posedge wr_clk);
    repeat (4) @(posedge rd_clk);
    scoreboard_active = 1'b1;

    if (empty !== 1'b1) begin $error("[TB] Phase 0: expected empty=1 after reset, got %0b", empty); mismatches++; end
    if (full  !== 1'b0) begin $error("[TB] Phase 0: expected full=0 after reset, got %0b", full);   mismatches++; end
    $display("[TB] Phase 0 done: empty=%0b full=%0b", empty, full);

    // ---- Phase 1: fill to FULL with rd_en held low, check FULL asserts at exactly DEPTH ----
    $display("[TB] Phase 1: fill to full (DEPTH=%0d)", DEPTH);
    for (int i = 0; i < DEPTH; i++) begin
      if (full !== 1'b0) $error("[TB] Phase 1: unexpectedly full after only %0d writes", i);
      wr_push(8'hA0 + i[7:0]);
    end
    @(posedge wr_clk);
    if (full !== 1'b1) begin $error("[TB] Phase 1: expected full=1 after %0d writes, got %0b", DEPTH, full); mismatches++; end
    $display("[TB] Phase 1 done: full=%0b after %0d accepted writes", full, writes_accepted);

    // Attempt one more write while full -- must be silently ignored (checked structurally by SVA
    // a_no_write_when_full; here we also confirm the scoreboard's writes_accepted doesn't move)
    wa_before = writes_accepted;
    wr_push(8'hFF);
    if (writes_accepted != wa_before)
      $error("[TB] Phase 1: a write was accepted while full=1 (writes_accepted moved)");

    // ---- Phase 2: drain to EMPTY, check EMPTY asserts at exactly 0, data matches scoreboard ----
    $display("[TB] Phase 2: drain to empty");
    for (int i = 0; i < DEPTH; i++) begin
      if (empty !== 1'b0) $error("[TB] Phase 2: unexpectedly empty after only %0d reads", i);
      rd_pop();
    end
    @(posedge rd_clk);
    if (empty !== 1'b1) begin $error("[TB] Phase 2: expected empty=1 after draining %0d entries, got %0b", DEPTH, empty); mismatches++; end
    $display("[TB] Phase 2 done: empty=%0b, reads_checked=%0d, mismatches=%0d", empty, reads_checked, mismatches);

    // Attempt one more read while empty -- must be silently ignored
    rc_before = reads_checked;
    rd_pop();
    if (reads_checked != rc_before)
      $error("[TB] Phase 2: a read was accepted while empty=1 (reads_checked moved)");

    // ---- Phase 3: randomized traffic, both domains free-running, enough to wrap pointers many times ----
    $display("[TB] Phase 3: randomized traffic (%0d cycles of pressure on each domain)", RANDOM_TRANSACTIONS);
    errors_before = mismatches;
    wr_random_mode = 1'b1;
    rd_random_mode = 1'b1;
    repeat (RANDOM_TRANSACTIONS) @(posedge wr_clk);
    wr_random_mode = 1'b0;
    rd_random_mode = 1'b0;
    @(negedge wr_clk); wr_en <= 1'b0;
    @(negedge rd_clk); rd_en <= 1'b0;
    $display("[TB] Phase 3 done: writes_accepted=%0d reads_checked=%0d new_mismatches=%0d",
              writes_accepted, reads_checked, mismatches - errors_before);

    // ---- Phase 4: drain whatever Phase 3 left behind, so Phase 5's reset is on a quiesced FIFO ----
    $display("[TB] Phase 4: drain remainder (expected_q.size=%0d)", expected_q.size());
    while (expected_q.size() > 0) rd_pop();
    repeat (4) @(posedge rd_clk);
    if (empty !== 1'b1) $error("[TB] Phase 4: expected empty=1 after full drain, got %0b", empty);

    // ---- Phase 5: simultaneous read+write pressure (both domains toggling every cycle) ----
    $display("[TB] Phase 5: simultaneous read+write pressure");
    errors_before = mismatches;
    fork
      begin
        for (int i = 0; i < DEPTH*4; i++) wr_push(8'hC0 + i[7:0]);
      end
      begin
        // start reading only once there's a reasonable chance of data present; the empty/full
        // interlocks make this safe to just race against Phase 5's writer directly
        repeat (2) @(posedge rd_clk);
        for (int i = 0; i < DEPTH*4; i++) rd_pop();
      end
    join
    repeat (4) @(posedge rd_clk);
    while (expected_q.size() > 0) rd_pop();
    $display("[TB] Phase 5 done: new_mismatches=%0d", mismatches - errors_before);

    // ---- Phase 6: mid-test reset, only once confirmed quiesced (see task header comment) ----
    $display("[TB] Phase 6: quiesced mid-test reset, skewed deassertion");
    if (empty !== 1'b1 || expected_q.size() != 0)
      $error("[TB] Phase 6 precondition violated: FIFO not quiesced before reset (empty=%0b, expected_q.size=%0d)", empty, expected_q.size());
    apply_reset(5, 11);
    scoreboard_active = 1'b1;
    if (empty !== 1'b1) begin $error("[TB] Phase 6: expected empty=1 after mid-test reset, got %0b", empty); mismatches++; end
    if (full  !== 1'b0) begin $error("[TB] Phase 6: expected full=0 after mid-test reset, got %0b", full);   mismatches++; end
    $display("[TB] Phase 6 done: empty=%0b full=%0b", empty, full);

    // ---- Phase 7: post-reset randomized traffic, confirm the design still works after reset ----
    $display("[TB] Phase 7: post-reset randomized traffic");
    errors_before = mismatches;
    wr_random_mode = 1'b1;
    rd_random_mode = 1'b1;
    repeat (RANDOM_TRANSACTIONS) @(posedge wr_clk);
    wr_random_mode = 1'b0;
    rd_random_mode = 1'b0;
    @(negedge wr_clk); wr_en <= 1'b0;
    @(negedge rd_clk); rd_en <= 1'b0;
    repeat (4) @(posedge rd_clk);
    while (expected_q.size() > 0) rd_pop();
    $display("[TB] Phase 7 done: new_mismatches=%0d", mismatches - errors_before);

    // ---------------------------------------------------------------
    // Final report
    // ---------------------------------------------------------------
    repeat (4) @(posedge wr_clk);
    $display("==============================================");
    $display("[TB] FINAL: writes_accepted=%0d reads_checked=%0d mismatches=%0d",
              writes_accepted, reads_checked, mismatches);
    if (mismatches == 0) $display("[TB] RESULT: PASS");
    else                 $display("[TB] RESULT: FAIL");
    $display("==============================================");
    $finish;
  end

  // Safety timeout so a hang doesn't run forever
  initial begin
    #2_000_000;
    $display("[TB] TIMEOUT -- simulation did not finish in time, treat as FAIL");
    $finish;
  end

endmodule
