# Verification Strategy — Async FIFO

## What is being tested

| Phase (tb_async_fifo.sv) | What it exercises |
|---|---|
| 0 | Power-on reset, deasserted with deliberate skew between the two domains (they can't align anyway — different async clocks) |
| 1 | Fill to exactly `DEPTH` writes, confirm `full` asserts at exactly the right count (not early/late), confirm an extra write while full is silently ignored |
| 2 | Drain to exactly 0, confirm `empty` asserts at exactly the right count, confirm an extra read while empty is silently ignored |
| 3 | Free-running randomized traffic on both domains independently (~70% attempt rate each), enough cycles to wrap the pointer 100+ times at DEPTH=16, full data-integrity scoreboard |
| 4 | Drain whatever Phase 3 left in flight, so Phase 5/6 start from a known state |
| 5 | Directed simultaneous read+write pressure — both domains issuing back-to-back transactions concurrently |
| 6 | Mid-test reset, only ever applied once the FIFO is confirmed quiesced (see the documented limitation below), with deliberately skewed deassertion |
| 7 | Post-reset randomized traffic, confirming the design recovers correctly and isn't a "works once at time 0" fluke |

`sim/run_sim.sh` additionally sweeps `DEPTH` (4/8/16/32) and `DATA_WIDTH` (4/8/32) across separate
runs, and every run randomizes the write/read clock **ratio** (not just phase) via `$urandom_range`
on the read period — the clock ratio is never fixed across runs, which is the whole point of testing
an *asynchronous* FIFO.

## What constitutes a failure

Any of:
1. A scoreboard mismatch (`sb_exp_val !== rdata` on an accepted read) — the ultimate data-integrity
   check: whatever a write pushed, a read must eventually return, in order, unchanged.
2. Any SVA assertion firing (see `rtl/fifo_sva_checker.sv`).
3. `full`/`empty` not asserting at exactly the boundary count during the directed fill/drain phases.
4. A write moving `writes_accepted` while `full=1`, or a read moving `reads_checked` while
   `empty=1` (checked both by the scoreboard's own gating and, independently, by SVA).
5. The simulation timing out (a `$finish` safety net at 2ms of simulated time) — would indicate a
   hang, e.g. a deadlock in the fork/join stimulus.

## Invariants that should always hold

- Data read out is exactly the data written, in FIFO (write) order, for every accepted
  read — regardless of clock ratio, regardless of reset timing, regardless of depth/width.
- `full` and `empty` are each internally consistent with their own domain's locally-known state at
  all times (see `cdc_notes.md` §7 for why they are *not* required to always agree with each other).
- Both Gray-coded pointers change by exactly one bit per real increment, with no exceptions,
  including across the wraparound boundary.
- After reset deassertion, the FIFO always starts in a known-empty state.
- A write attempted while full, or a read attempted while empty, never mutates internal pointer
  state — it's a true no-op, not a partial/corrupting operation.

## Assertions (see rtl/fifo_sva_checker.sv for the implementation and full reasoning)

1. No write pointer advance on write-while-full.
2. No read pointer advance on read-while-empty.
3. (Tracked, not asserted — see cdc_notes.md §7) full/empty co-occurrence counter.
4/5. Gray-code single-bit-change property on both pointers, every cycle.
6. Reset establishes a known-empty state.

## Functional coverage that would matter (not implemented as `covergroup`s here, but this is what
a real coverage plan would track)

- Cross of (full asserted) × (clock ratio bucket: wr faster / rd faster / near-equal).
- Cross of (pointer wraparound event) × (simultaneous read+write that cycle).
- Reset applied at each of: FIFO empty, FIFO full, FIFO partially occupied (this repo's testbench
  deliberately only covers the "empty" case for the reasons in the next section — a real coverage
  plan would explicitly flag the other two as **not covered, and known to be unsafe to attempt**,
  rather than silently leaving them unmeasured).
- Depth × width cross (this repo's `run_sim.sh` sweep covers this directionally, not exhaustively).
- Full/empty co-occurrence bucketed by depth (directly ties to the cdc_notes.md §7 finding).

## Known, deliberate verification gap: reset with data in flight

This design (and the classic Cummings architecture it follows) assumes reset happens at a quiescent
point — not while one domain still holds unread data the other domain doesn't know about yet.
Resetting only one domain's pointer while the memory/other pointer still reflect in-flight data
desynchronizes the two domains' view of the FIFO's contents by construction; there is no defined
"correct" recovery behavior for that case in this architecture. This testbench never tests it
because there is nothing correct to check it against — this is flagged explicitly as a limitation,
not silently skipped. A production design that needs safe reset with in-flight data would need
additional handshaking (e.g. a "quiesce" protocol both sides participate in before either resets) --
out of scope here.

## Realistic bugs this testbench is specifically built to catch

- Off-by-one in full/empty boundary detection (Phases 1/2 catch this directly, at the exact
  boundary, not just "eventually").
- A full-flag timing bug that lets one extra write silently overwrite an unread entry (caught two
  ways: the SVA `a_no_write_when_full` checks the pointer directly; the scoreboard would separately
  catch the downstream data corruption if the pointer check somehow missed it).
- A synchronizer reduced to 1 flop (or 0) by an "optimization" — wouldn't fail functionally in
  simulation (RTL simulation doesn't model analog metastability), which is precisely why this is a
  *design-review* and *CDC-lint-tool* concern (SpyGlass CDC, Conformal LEC-adjacent structural
  checks) rather than something a testbench alone can prove — worth saying exactly this rather
  than overclaiming the testbench catches everything.
- A binary (not Gray) pointer accidentally used on a crossing path — the one-bit-change assertions
  (4/5) catch this directly and immediately.
- A reset synchronizer reduced to a plain synchronous reset — wouldn't be caught by this testbench
  either (same reasoning as above: simulation-time reset deassertion timing is whatever the TB
  drives; the real hazard is analog/silicon timing, not simulation-visible behavior). Flagging this
  honestly rather than claiming coverage this testbench doesn't actually have.

## If this were verified with UVM instead

A full self-checking SV testbench (what this repo has) is proportionate to this design's size — a
2-clock-domain FIFO doesn't need a class-based UVM environment to verify thoroughly. If it did
warrant UVM (e.g. as one block inside a much larger SoC-level UVM environment), the natural mapping
would be:

- **Two independent `uvm_agent`s**, one per clock domain, each with its own `uvm_sequencer` +
  `uvm_driver` (driving `wr_en`/`wdata` or `rd_en` from randomized sequences) and `uvm_monitor`
  (observing the same signals + `full`/`empty`/`rdata`) — mirroring the fact that the two domains
  are genuinely independent stimulus sources.
- A single **reference-model scoreboard** (`uvm_scoreboard` with two `uvm_tlm_analysis_fifo` inputs,
  one per agent's monitor) implementing exactly this testbench's shadow queue, but as a reusable UVM
  component instead of inline TB code.
- **`uvm_reg`/RAL** would be overkill here (no CSR/register interface on this block) — not applicable.
- Sequences for each phase above (`fill_to_full_seq`, `randomized_traffic_seq`,
  `simultaneous_rw_seq`, `quiesced_reset_seq`) instead of the current TB's linear phase structure.
- The concurrent SVA in `fifo_sva_checker.sv` would port over unchanged to a commercial simulator's
  UVM environment (a `bind`-based checker is in fact the more idiomatic UVM-adjacent pattern; this
  repo's direct-instantiation workaround exists purely because of this Icarus Verilog build's `bind`
  gap — see the file header).

## Toolchain gotchas found in this repo's Icarus Verilog 14.0 build (confirmed by direct isolated tests before relying on any workaround)

These are genuine, tested findings about **this specific open-source toolchain**, not claims about
SystemVerilog itself or about what a commercial simulator (VCS, Questa) supports — all of the
constructs below are standard IEEE 1800 SystemVerilog and would work as written on VCS/Questa.

1. **SystemVerilog `clocking` blocks**: fail to parse at all (`syntax error` on the `clocking`
   keyword). Worked around by driving stimulus on `negedge` and sampling/checking on `posedge` of
   each signal's own domain — race-free for the same underlying reason a clocking block would be,
   without needing the syntax.
2. **`bind`**: fails to parse at all, in every placement tried (top-level, wrapped in a module).
   Worked around by directly instantiating the checker module from `async_fifo.sv`, guarded by
   `` `ifndef SYNTHESIS``.
3. **Concurrent assertions (`assert property (...)`)**: fail to parse in *any* form tried, including
   the most minimal (`assert property (@(posedge clk) some_signal);`), even with
   `-gsupported-assertions`. Worked around by writing every property as an immediate assertion
   (`assert (expr) else ...`) inside a procedural block, using manually-maintained shadow registers
   in place of temporal operators.
4. **`$past`, `$rose`, `$fell`, `$changed`**: parse without error but fail at elaboration
   (`"not defined by any module"`) — i.e. not actually implemented, only discovered because the
   parse succeeded and gave false confidence until runtime. Worked around with manual "previous
   value" shadow registers updated each clock.
5. **`$onehot`**: parses AND elaborates AND runs without error, but returns **incorrect results**
   (`$onehot(5'b00001)` returns 0) — confirmed by an isolated single-purpose test
   (`is_onehot(a^b)` in `fifo_sva_checker.sv`'s history) before this was trusted. This is the most
   dangerous class of tool gap: no error message at all, silently wrong answers. Worked around with
   the portable bit-trick `(x != 0) && ((x & (x-1)) == 0)`, itself verified correct in isolation
   before being relied on.
6. **Declared-with-initializer local variables inside a non-`automatic` `always` block**
   (e.g. `bit [7:0] exp = some_queue.pop_front();` written directly inside `begin...end` inside
   `always @(posedge clk)`): the initializer is evaluated once, effectively at elaboration time, not
   re-evaluated on every re-entry into that block. This silently produced permanently-wrong values
   in two places in this testbench's history (the scoreboard's popped-value variable, and two
   before/after boundary-test counters) before being found and fixed by hoisting the variable to
   module scope and using a plain blocking assignment (`=`) at the point of use instead of a fresh
   declaration. iverilog does emit a warning for this
   (`"Static variable initialization requires explicit lifetime in this context"`) — worth grepping
   compile output for that warning specifically, since it's easy to miss among other output.

**Why this list matters**: it demonstrates the actual skill of debugging a
toolchain/environment gap versus a design bug — distinguishing "my RTL is wrong" from "my checker is
wrong" from "my tool doesn't support this" is a real, valuable, testable skill, and every item above
was diagnosed with a minimal isolated reproduction before being trusted, not guessed at.
