# CDC Notes — Async FIFO

This is the whiteboard-level explanation: why each CDC technique in this design exists, in the
order these points are likely to be probed.

## 1. Metastability — the root problem

A flip-flop has a setup/hold window around its clock edge. If a data input transitions inside that
window, the flip-flop's output can go metastable: it hovers at an invalid voltage level for an
unbounded (though usually short) time before resolving to either a 0 or a 1 — and which one it
resolves to is not guaranteed to match what the "correct" sampled value should have been. This isn't
a corner case you can design away with faster gates; it's a fundamental consequence of sampling an
asynchronous signal with a synchronous clock. The only lever you have is **reducing the probability**
that a metastable event propagates somewhere it can do damage, and bounding how long a downstream
circuit has to wait before treating a possibly-metastable value as settled.

## 2. Why a 2-flop synchronizer, not zero or one

A single flop sampling an async signal can still be metastable when its own output is used
downstream. A **second** flop, clocked by the same clock, gives the first flop's output a full clock
period to resolve before anything reads it. This doesn't guarantee resolution (metastability is
theoretically unbounded) — it reduces the *probability* of a still-metastable value reaching the
rest of the design to an acceptably low MTBF (mean time between failures), calculable from the
flop's resolution time constant, the clock frequency, and the toggle rate of the async signal. Going
to 3+ stages trades one more cycle of latency for another large multiplicative improvement in MTBF —
worth it in safety-critical or very-high-frequency designs; 2 stages is the standard baseline
assumption when a source spec just says "synchronized" without more detail (exactly this project's
situation).

## 3. Why Gray code, not binary, for the crossing pointers

This is the question most likely to open the topic. The synchronizer chain is safe for a **single
bit** crossing domains (that's the whole point of part 2). It is NOT automatically safe for a
**multi-bit bus** crossing together, because different bits of a binary counter can change at
different times relative to the sampling clock edge in the presence of routing delay skew, and even
without skew, a binary increment can flip many bits at once (e.g. `0111 -> 1000` flips all four
bits). If the destination domain's synchronizer samples mid-transition, it can capture some bits from
the OLD value and some from the NEW value — landing on a composite value that was never a real
pointer value at all (not even briefly). For a FIFO pointer, that composite value could point at the
wrong memory location or badly miscalculate full/empty.

Gray code's defining property fixes this: only **one bit** changes between any two consecutive
values. If a synchronizer samples mid-transition, in the worst case it captures either the OLD value
or the NEW value (never a mix, since there is no "in between" bit combination for a 1-bit change) —
worst case, it's simply one Gray-code step "late," which is exactly what the full/empty logic is
already designed to tolerate (it just sees the pointer update on the next attempt instead of this
one — a stale-but-valid pointer, not a corrupt one).

## 4. Why the write pointer and read pointer both need their own synchronizer, in opposite directions

The FIFO's `full` flag is a function local to the write domain, but it needs to know how far the
*read* domain has progressed. The read pointer is generated in the read domain, so it must be
synchronized *into* the write domain before `wptr_full.sv` can use it. Symmetrically, `empty` (read
domain) needs the write pointer synchronized *into* the read domain. These are two entirely separate
synchronizer instances, each a destination-domain-owned 2-flop chain (`sync_r2r.sv`), each only ever
reading from its own destination clock/reset.

## 5. Why the extra MSB in the pointer width

Comparing only the address-width bits of the two pointers can't distinguish "FIFO is empty" (read
has caught up to write) from "FIFO is full" (write has lapped read by exactly one full pass) --
both look identical if you only look at the low bits. The extra bit above the address width tracks
*which lap* the pointer is on. Comparing the full (ADDR_WIDTH+1)-bit Gray pointers: **equal** means
empty (same lap, same offset); equal in the low bits but different in the wrap-tracking high bits
means full (write is exactly one lap ahead). See `wptr_full.sv`'s comment for the exact bit-inversion
pattern this comparison uses.

## 6. Reset synchronization

`wr_arst_n`/`rd_arst_n` are asynchronous external inputs. Asserting a reset asynchronously is safe
(you want the reset to take effect immediately, regardless of clock phase). *Deasserting* it
asynchronously is not: if it releases in the same instant a flop's clock edge arrives, the flop can
see a metastable "was I reset or not" event on its own reset input, potentially causing different
flops in the same domain to disagree about whether reset is still active. `rst_sync.sv` forces
deassertion to happen synchronously (through a 2-flop chain sampling the async reset), so every flop
in that domain releases from reset on the same clock edge, deterministically.

## 7. Full/empty can transiently disagree at small depths — a real finding, not a bug

**This was discovered by direct testing of this repo's RTL, not assumed up front.** An earlier
version of `fifo_sva_checker.sv` asserted `!(full && empty)` as a hard invariant. Sweeping `DEPTH`
down to 4 (`sim/run_sim.sh 11 4 8`) falsified it: `full` and `empty` legitimately read 1
simultaneously, hundreds of times over a long random run (confirmed: 766 occurrences in one seed),
with **zero data corruption** (the scoreboard still reports 0 mismatches on that exact run).

**Why this happens**: `full` (write domain) and `empty` (read domain) are each computed from a
*locally accurate but synchronizer-stale* view of the other domain's pointer. If a burst of writes
fills the FIFO completely within fewer cycles than the 2-flop synchronizer needs to propagate even
the *first* of those writes to the read domain, then at that instant: the write domain correctly
believes `full=1` (it really did just fill every slot, verified against its own — still all-zero —
synchronized copy of the read pointer), while the read domain correctly (from its own stale
information) still believes `empty=1` (it hasn't yet observed any of those writes arrive). Both
flags are individually *honest* about what their own domain currently knows; they simply haven't
converged yet. Convergence follows a couple of cycles later once the synchronizers catch up.

**Why DEPTH matters here**: the smaller the FIFO, the fewer consecutive writes are needed to fill
it, and the more likely a burst finishes before the ~2-cycle synchronizer latency has had a chance
to propagate anything. At `DEPTH=4` with a 2-flop synchronizer, a fast write burst can trivially
outrun that propagation; at `DEPTH=8` and `DEPTH=16` in this same test sweep, it never did (0
co-occurrences observed across the seeds tried). This gives a concrete, tested version of a general
rule of thumb worth being able to state clearly: **an async FIFO's depth needs enough margin over its
synchronizer latency (in cycles) that a full-speed burst can't outrun the propagation of pointer
updates to the other side** — otherwise the full/empty flags are still *correct* (never lie about
what their own domain currently knows, never corrupt data) but can visibly disagree with each other
for a few cycles, which is a real, if usually benign, design consideration rather than a defect.

**What this does NOT mean**: it does NOT mean data is lost, corrupted, or that a read/write
protocol violation occurred — the `a_no_write_when_full` / `a_no_read_when_empty` assertions (which
gate on each flag strictly within its OWN domain) never fired during this same run, and the
scoreboard's end-to-end data check passed. The two domains simply took a few extra cycles to agree
with each other about the FIFO's overall state, which is inherent to the CDC design, not a
consequence of anything broken.

## 8. Likely follow-up pressure points

- "What if the two clocks share a common divisor / are related?" — this design still works (Gray
  code + synchronizers don't assume unrelated clocks), but it's *more conservative than necessary*
  in that case; a same-clock or integer-ratio FIFO could use a simpler, lower-latency design.
- "What's the actual MTBF of your synchronizer?" — requires the flop's metastability resolution time
  constant (a real, measured silicon/library characteristic, not something derivable from RTL alone)
  — the honest answer here is "I'd pull that from the standard-cell library's characterization data,
  not from the RTL," which is itself the correct, defensible answer.
- "Why not use a mutex/semaphore-style handshake instead of Gray code?" — a full request/acknowledge
  handshake per transfer works but costs much more latency per transfer than a free-running pointer
  scheme; Gray-code pointers amortize the synchronization cost across a whole burst instead of paying
  a handshake round-trip per element.
