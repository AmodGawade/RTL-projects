# Technical Prep — Async FIFO + CDC Infrastructure

## A. 60-second explanation

"I built a parameterized dual-clock FIFO — independent write and read clocks with no fixed phase
relationship. The core challenge is safely crossing the write and read pointers between domains
without metastability or data corruption. I used the classic Cummings architecture: both pointers
are Gray-coded so only one bit changes per increment, each crosses into the other domain through a
2-flop synchronizer, and full/empty are derived by comparing an extra 'wrap' bit alongside the
address bits so equal-vs-lapped pointers can be told apart. I verified it with a self-checking
testbench — randomized independent clock ratios, boundary tests for exact full/empty timing,
simultaneous read+write pressure, and a scoreboard checking every byte in order — plus SVA
assertions on the properties that actually matter: no write-while-full, no read-while-empty, and
the Gray-code one-bit-change invariant on both pointers. I also found, by testing depth down to 4,
that full and empty can transiently disagree at very shallow depths relative to synchronizer
latency — without any data corruption — which taught me a concrete depth-vs-latency design
guideline I can defend on a whiteboard."

## B. 5-minute walkthrough

Structure it as: problem → architecture → the two subtle bugs I actually found and fixed →
verification approach → what I'd do differently at scale.

1. **Problem statement**: two clock domains need to move data through a fixed-size buffer with no
   assumed frequency/phase relationship. Naive approach (just read/write a shared RAM with shared
   pointers) breaks immediately — pointers are multi-bit values, and sampling a multi-bit binary
   value mid-transition across a clock boundary can capture a composite value that was never real.
2. **Architecture**: walk the block diagram in `docs/architecture.md` — write-domain pointer/full
   logic, read-domain pointer/empty logic, the memory with one port per domain, and the two
   synchronizers, one per direction. Emphasize: the ONLY signals crossing domains are the two
   Gray-coded pointers.
3. **The full/empty comparison trick**: explain the extra MSB and why simple equality isn't enough
   (empty vs. full look the same in the low bits alone).
4. **What I found by testing, not just designing**: the full/empty co-occurrence at DEPTH=4 (see
   `docs/cdc_notes.md` §7) — this is the strongest part of the story because it shows you verify
   your own assumptions rather than trusting them. Also worth mentioning: I originally wrote an SVA
   assertion asserting full/empty were mutually exclusive, and my own testbench proved that
   assertion WRONG at small depth — a real example of "the checker had a bug in its understanding of
   the spec," which is itself a useful thing to be able to say happened to you.
5. **Verification approach**: self-checking SV testbench (not full UVM — right-sized for this
   block), scoreboard, directed boundary phases + randomized phases, SVA for structural invariants.
6. **What I'd do at scale**: if this were one block in a larger SoC UVM environment, split it into a
   per-domain agent pair with a shared scoreboard (see `docs/verification.md`'s UVM sketch), and
   push the CDC-specific checks (synchronizer stage count, no-combinational-logic-between-flops)
   into a dedicated CDC lint tool (SpyGlass CDC or equivalent) rather than trying to prove them from
   RTL simulation alone, since simulation can't model analog metastability.

## C. Likely technical questions (15+, categorized)

### Fundamentals
1. What is metastability, physically?
2. Why can't you just use a single flip-flop to synchronize a signal across clock domains?
3. What does MTBF mean in this context, and what factors influence it?

### Architecture
4. Walk me through your top-level block diagram.
5. Why does the memory need two separate ports instead of one shared port?
6. What's the difference between this design's read port and a synchronous FIFO's read port?

### RTL
7. Why is the pointer `ADDR_WIDTH+1` bits instead of `ADDR_WIDTH` bits?
8. Walk me through the exact full/empty comparison logic, bit by bit.
9. Why do you compute `full_next` from `wgray_next` instead of registering `full` a cycle later?

### Verification
10. How did you check that data written is exactly the data read, in order?
11. What's the difference between an assertion and a scoreboard check, and when do you need both?
12. Why do you drive stimulus on `negedge` and check on `posedge` in your testbench?

### Debugging
13. Walk me through a bug you actually found while testing this design.
14. Your $onehot check silently returned wrong answers in one toolchain — how did you find that,
    and what does that teach you about trusting a simulator?

### Timing
15. Why does `set_clock_groups -asynchronous` matter for this design's SDC?
16. What's a false path vs. a max-delay/datapath-only constraint, and which did you use where?

### CDC
17. Why Gray code instead of binary for the crossing pointers?
18. Why 2 synchronizer flops and not 1, or not 4?
19. What happens if you synchronize a *binary* counter with a 2-flop synchronizer instead of Gray?

### Design tradeoffs
20. What would you change if this needed to support burst-of-N atomic writes?
21. What's the cost of going from a 2-flop to a 3-flop synchronizer?

### "Why did you do it this way?"
22. Why did you choose fixed-priority-style full/empty detection over a counter-based approach
    (tracking fill level with a synchronized counter instead of comparing pointers)?
23. Why does reset in this design only support quiescent-state reset, not mid-transfer reset?

## D. Follow-ups (2–4 increasingly difficult, for a sample of the above)

**Q17: Why use Gray-coded pointers in an async FIFO?**
- Follow-up 1: Why is Gray code safer for CDC specifically (not just "it's standard")?
- Follow-up 2: Why does only one bit change per increment — prove it for the reflected binary Gray
  code construction (`g = b ^ (b >> 1)`).
- Follow-up 3: How do you generate full/empty from Gray-coded pointers, given you can't just do
  arithmetic subtraction on them?
- Follow-up 4: What happens if a synchronizer flop goes metastable anyway, despite Gray coding —
  what's the worst case now, versus the worst case with binary pointers?

**Q9: Why compute `full_next` from `wgray_next` instead of registering `full` a cycle later?**
- Follow-up 1: What would break if you used the CURRENT `wgray` (not `wgray_next`) to compute full?
- Follow-up 2: Does this same look-ahead technique need to apply to `empty` too, symmetrically? Why?
- Follow-up 3: Is there a scenario where this look-ahead itself becomes a timing bottleneck at very
  high clock frequencies (i.e., does computing `wgray_next` combinationally from `wbin_next` put
  more logic in the critical path than a simpler, later-but-safer scheme would)?

**Q13: Walk me through a bug you actually found while testing this design.**
- Follow-up 1: How did you distinguish "this is a real RTL bug" from "this is a testbench bug"?
- Follow-up 2 (they'll probe the full/empty co-occurrence specifically): why didn't you just widen
  the assertion's disable condition instead of removing it — what made you conclude it was actually
  wrong rather than needing a smarter guard?
- Follow-up 3: How would a design-time (not test-time) reviewer have caught this before it ever got
  to simulation?

**Q19: What happens if you synchronize a binary counter with a 2-flop synchronizer instead of Gray?**
- Follow-up 1: Give a concrete bit-pattern example where this produces a value that was never a real
  counter value.
- Follow-up 2: Would this show up reliably in simulation, or is it a "works in sim, fails in
  silicon" class of bug — and why?
- Follow-up 3: What tool would actually catch this at design-review time, before tape-out?

## E. Whiteboard problems (solve without looking at the implementation)

1. Design a synchronous FIFO (single clock domain) — full/empty logic, pointer width.
2. Design an asynchronous FIFO from scratch, narrating the Gray-code/synchronizer reasoning as you go.
3. Design a 2-flop synchronizer for a single-bit signal; explain why 2, not 1.
4. Given a Gray-code counter's current value, derive the next value on a whiteboard (binary-to-Gray
   and back), for a 4-bit example.
5. Design a reset synchronizer (async assert, sync deassert) and explain why deassertion needs the
   sync treatment but assertion doesn't.
6. Design a pulse synchronizer (single-cycle pulse in domain A needs to produce a single-cycle pulse
   in domain B, where B may be faster or slower than A).
7. Given DEPTH and a 2-flop synchronizer's 2-cycle latency, derive (informally, no need for a closed
   form) why very small DEPTH values make full/empty more likely to transiently disagree.
8. Design a valid/ready handshake between two blocks in the SAME clock domain, and explain what
   changes if they're in different domains.
9. A colleague proposes replacing your Gray-code pointer scheme with "just synchronize the binary
   pointer with 3 flops instead of 2, that's even safer." Explain why this doesn't fix the actual
   problem, no matter how many synchronizer stages are used.
