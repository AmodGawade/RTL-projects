// fifo_sva_checker.sv
`timescale 1ns/1ps
// Instantiated directly from async_fifo.sv, guarded by `ifndef SYNTHESIS` there, so it never
// reaches a synthesis tool but still gets elaborated for simulation.
//
// Implementation note (portability): these properties are written as IMMEDIATE assertions over
// manually-maintained "previous value" shadow registers, not as SystemVerilog CONCURRENT
// assertions (`assert property (...) $past(...)/$rose(...)/$changed(...)`). Direct testing against
// this repo's Icarus Verilog 14.0 toolchain showed concurrent `assert property` fails to parse at
// all, and `$past`/`$rose`/`$changed` parse but are "not defined by any module" at elaboration --
// not actually implemented. The shadow-register form below is functionally identical to what the
// concurrent-assertion version would check; it's written this way for portability, not because
// it's the preferred style. A commercial simulator (VCS, Questa) would support the concurrent form
// directly -- see docs/verification.md for both forms side by side so you can discuss either one.
//
// A second, more surprising portability finding: this build's `$onehot` is itself broken --
// `$onehot(5'b00001)` returns 0, confirmed by direct isolated test (see docs/verification.md's
// "toolchain gotchas" section). Replaced below with the standard portable bit trick
// `(x != 0) && ((x & (x-1)) == 0)`, which was verified correct against this same toolchain before
// being relied on here.
//
// Each assertion below protects against a SPECIFIC realistic bug class -- see the comment above
// each one. These are not "assertions for coverage's sake."
module fifo_sva_checker #(
  parameter int ADDR_WIDTH = 4
) (
  input logic                 wr_clk, wr_rst_n, wr_en, full,
  input logic                 rd_clk, rd_rst_n, rd_en, empty,
  input logic [ADDR_WIDTH:0]  wptr_gray, rptr_gray
);

  // Portable replacement for $onehot (see file header) -- true iff exactly one bit of x is set.
  function automatic bit is_onehot(input logic [ADDR_WIDTH:0] x);
    return (x != '0) && ((x & (x - 1'b1)) == '0);
  endfunction

  // ---------------------------------------------------------------
  // 1. Never actually accept a write while full.
  // Protects against: a full-flag timing bug that lets the write pointer advance one entry past
  // capacity, silently overwriting an unread entry.
  // Equivalent concurrent form: assert property (@(posedge wr_clk) disable iff(!wr_rst_n)
  //   (wr_en && full) |=> $stable(wptr_gray));
  // ---------------------------------------------------------------
  logic                 prev_wr_en_full;
  logic [ADDR_WIDTH:0]  prev_wptr_gray;

  always @(posedge wr_clk) begin
    if (!wr_rst_n) begin
      prev_wr_en_full <= 1'b0;
      prev_wptr_gray  <= '0;
    end else begin
      if (prev_wr_en_full) begin
        assert (wptr_gray == prev_wptr_gray)
          else $error("[SVA] t=%0t: write pointer advanced while full=1 -- write-while-full was not ignored", $time);
      end
      prev_wr_en_full <= (wr_en && full);
      prev_wptr_gray  <= wptr_gray;
    end
  end

  // ---------------------------------------------------------------
  // 2. Never actually pop while empty.
  // Protects against: an empty-flag timing bug that lets the read pointer run ahead of the write
  // pointer, reading stale/garbage entries.
  // ---------------------------------------------------------------
  logic                 prev_rd_en_empty;
  logic [ADDR_WIDTH:0]  prev_rptr_gray;

  always @(posedge rd_clk) begin
    if (!rd_rst_n) begin
      prev_rd_en_empty <= 1'b0;
      prev_rptr_gray   <= '0;
    end else begin
      if (prev_rd_en_empty) begin
        assert (rptr_gray == prev_rptr_gray)
          else $error("[SVA] t=%0t: read pointer advanced while empty=1 -- read-while-empty was not ignored", $time);
      end
      prev_rd_en_empty <= (rd_en && empty);
      prev_rptr_gray   <= rptr_gray;
    end
  end

  // ---------------------------------------------------------------
  // 3. full && empty co-occurrence -- TRACKED, not asserted as illegal.
  //
  // An earlier version of this checker asserted `!(full && empty)` as a hard invariant. Sweeping
  // DEPTH down to 4 (sim/run_sim.sh seed=11 depth=4 width=8) falsified that assumption: full and
  // empty legitimately disagree for a few cycles whenever a write burst fills the FIFO faster than
  // the OTHER domain's 2-flop synchronizer has had time to observe it. Concretely: the write domain
  // computes `full` from its OWN write pointer vs. its synchronized (and therefore up to
  // 2-cycle-stale) copy of the read pointer; the read domain computes `empty` symmetrically. Each
  // flag is a locally-correct, pessimistic view -- but the two domains' views are NOT required to
  // agree at every instant, only to eventually converge once the synchronizers catch up. At
  // DEPTH=4 with a 2-flop synchronizer, filling the FIFO in 4 back-to-back writes is often faster
  // than that convergence, so BOTH flags can read 1 at once: full because the write side really
  // did just fill all 4 slots against a still-stale (zero) synchronized read pointer; empty because
  // the read side hasn't yet observed ANY of those writes. Verified this does NOT corrupt data --
  // the scoreboard in tb_async_fifo.sv still reports 0 mismatches on the exact run that trips this
  // condition repeatedly. See docs/cdc_notes.md's "full/empty can transiently disagree" section for
  // the full writeup and the practical depth-vs-synchronizer-latency guideline this implies.
  //
  // What's tracked instead: a simple occurrence counter, useful as a coverage-style signal for
  // "how often did this depth get close enough to the synchronizer latency to matter" across a
  // depth sweep -- not a pass/fail check.
  // ---------------------------------------------------------------
  int unsigned full_empty_cooccurrence_count = 0;

  always @(full or empty) begin
    if (full && empty) full_empty_cooccurrence_count++;
  end

  final begin
    $display("[SVA] full/empty co-occurrence count this run: %0d (depth-dependent, see file header; 0 is expected at typical depths, nonzero at very shallow depths)",
              full_empty_cooccurrence_count);
  end

  // ---------------------------------------------------------------
  // 4/5. Gray-code single-bit-change property, checked directly on both exported pointers.
  // Protects against: someone "optimizing" the binary->Gray conversion and breaking the
  // one-bit-change property that CDC safety depends on (see docs/cdc_notes.md).
  // ---------------------------------------------------------------
  logic [ADDR_WIDTH:0] wptr_gray_prev_step, rptr_gray_prev_step;

  always @(posedge wr_clk) begin
    if (!wr_rst_n) begin
      wptr_gray_prev_step <= '0;
    end else begin
      if (wptr_gray !== wptr_gray_prev_step) begin
        assert (is_onehot(wptr_gray ^ wptr_gray_prev_step))
          else $error("[SVA] t=%0t: wptr_gray changed by more than one bit in a single step (0x%0h -> 0x%0h)",
                      $time, wptr_gray_prev_step, wptr_gray);
      end
      wptr_gray_prev_step <= wptr_gray;
    end
  end

  always @(posedge rd_clk) begin
    if (!rd_rst_n) begin
      rptr_gray_prev_step <= '0;
    end else begin
      if (rptr_gray !== rptr_gray_prev_step) begin
        assert (is_onehot(rptr_gray ^ rptr_gray_prev_step))
          else $error("[SVA] t=%0t: rptr_gray changed by more than one bit in a single step (0x%0h -> 0x%0h)",
                      $time, rptr_gray_prev_step, rptr_gray);
      end
      rptr_gray_prev_step <= rptr_gray;
    end
  end

  // ---------------------------------------------------------------
  // 6. Reset must establish a known-empty state.
  // Protects against: a reset-value bug in rptr_empty.sv (e.g. someone changes the reset value of
  // `empty` while refactoring and forgets the FIFO must start empty, not full or "don't care").
  // ---------------------------------------------------------------
  logic rd_rst_n_prev = 1'b0;

  always @(posedge rd_clk) begin
    if (rd_rst_n && !rd_rst_n_prev) begin // rose(rd_rst_n)
      assert (empty)
        else $error("[SVA] t=%0t: empty was not asserted immediately after reset deasserted", $time);
    end
    rd_rst_n_prev <= rd_rst_n;
  end

endmodule
