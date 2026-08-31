# Technical Prep — AXI4-Lite Interconnect + APB Subsystem

## A. 60-second explanation

"I built a 2-master, 3-slave AXI4-Lite interconnect with fixed-priority arbitration, address
decoding, and backpressure, plus an AXI4-Lite-to-APB bridge feeding a small APB register bank as
the third slave. The interconnect arbitrates writes and reads independently — whichever master's
AW+W (or AR) arrives first, subject to fixed priority, gets exclusive use of that channel's routing
path until its response completes, then it re-arbitrates. Unmapped addresses get a DECERR generated
by the interconnect itself, not a hang; addresses that reach a real slave but are illegal within
that slave get SLVERR instead — the AXI-correct distinction between the two. The APB bridge
implements the actual SETUP-then-ACCESS two-phase sequence, not a same-cycle passthrough. I verified
it with directed tests per region, error-injection tests for both response codes, directed
concurrent-contention tests with both masters hitting the same and different regions at once, and
randomized traffic — and found two real bugs doing it: an early version of the DECERR path never
acknowledged the requesting master's handshake at all, so an unmapped access just hung forever
instead of erroring; and the register storage in both slave types was never reset, so any read of a
never-written register returned X instead of a defined value. Both were found by the testbench
actually failing, not guessed at."

## B. 5-minute walkthrough

1. **Problem statement**: 2 independent AXI4-Lite managers need to reach 3 different memory-mapped
   targets through one shared fabric, with correct backpressure and error semantics.
2. **Architecture**: walk `docs/architecture.md`'s diagram — arbiter, address decode, 3 downstream
   targets (2 generic register-file slaves, 1 through an APB bridge).
3. **The arbitration model, and why it's deliberately simple**: whole-transaction granularity, fixed
   priority, write and read arbitrated independently — explain why this is the right amount of
   complexity for a 2-master design versus a full independent-per-master crossbar.
4. **Error handling, and the DECERR-vs-SLVERR distinction**: explain why these need to be different
   codes (address-decode failure vs. a real slave rejecting the access) and how the interconnect
   generates DECERR itself without ever touching a slave.
5. **The two bugs I actually found**: the DECERR hang (a protocol-completeness bug — every request
   must eventually get a response) and the unreset register array (a state-initialization bug that
   only randomized testing surfaced, since directed tests happened to always write before reading).
   This is the strongest part of the story — both are real, logged, and fixed, not hypothetical.
6. **APB bridge internals**: the real SETUP/ACCESS sequence, and how the bridge serializes AXI reads
   and writes onto APB's single request interface (write prioritized if both pending).
7. **What I'd add at scale**: independent per-master outstanding transactions (today it's
   single-outstanding per channel direction), a round-robin arbiter option for fairness under
   sustained dual-master load, and `uvm_reg`/RAL for the APB register model instead of hand-written
   shadow arrays (see `docs/verification.md`'s UVM sketch).

## C. Likely technical questions (15+, categorized)

### Fundamentals
1. What's the difference between AXI4, AXI4-Lite, and APB, in terms of what each protocol assumes?
2. Why does AXI4-Lite have no burst support, and what does that simplify at the interconnect level?
3. What's the difference between DECERR and SLVERR, and who is responsible for generating each?

### Architecture
4. Walk me through what happens when both masters assert AWVALID in the same cycle.
5. Why are the write and read paths arbitrated independently instead of as one combined resource?
6. Why does this design grant on `AWVALID && WVALID` together instead of AWVALID alone?

### RTL
7. Walk me through the exact cycle where a DECERR response is generated.
8. How does `axi_lite_regfile.sv` handle AW and W arriving in different cycles?
9. Why does `axi_lite_to_apb_bridge.sv` need to prioritize write over read when both are pending?

### Verification
10. How did your scoreboard distinguish a real data-integrity bug from a routing bug?
11. Walk me through the concurrent-contention test phases — what specifically do they prove that a
    fully sequential test wouldn't?
12. Why does the testbench check both DECERR and SLVERR separately, rather than just "any error"?

### Debugging
13. Walk me through the DECERR hang bug you found — how did you localize it to the ready-signal
    logic specifically, rather than the state machine or the arbitration priority?
14. The register-reset bug only showed up in Phase 5, not Phases 1–4 — why, and what does that teach
    you about directed vs. randomized testing?

### Timing
15. What would `set_clock_groups`/`set_false_path` need to say for this design, given it's fully
    synchronous (unlike the async FIFO)? Is there anything CDC-like here at all?
16. Where's the likely critical path in this design — the address decode, the arbitration mux, or
    the APB bridge's SETUP/ACCESS logic?

### CDC
17. This design is single-clock — why doesn't it need any of the async FIFO's CDC machinery?
18. If master 0 and master 1 were actually in different clock domains, what would have to change?

### Design tradeoffs
19. What's the cost of the "grant on AWVALID && WVALID together" simplification versus a fully
    general AW/W-independent design?
20. Why fixed-priority arbitration instead of round-robin, and when would that choice matter?

### "Why did you do it this way?"
21. Why does the APB bridge implement a real 2-phase SETUP/ACCESS sequence instead of just directly
    wiring AXI signals to APB signals?
22. Why generate DECERR inside the interconnect itself instead of routing unmapped addresses to a
    dedicated "error slave" module?

## D. Follow-ups (2–4 increasingly difficult)

**Q4: Walk me through what happens when both masters assert AWVALID in the same cycle.**
- Follow-up 1: What if master 1 also has WVALID asserted but master 0 doesn't yet — does master 0
  still win arbitration?
- Follow-up 2: What signal explicitly tells you which master won, and where is it registered?
- Follow-up 3: What happens to master 1's AWVALID during the cycles master 0 is being serviced?
- Follow-up 4: Is there a starvation risk for master 1 under sustained master-0-only traffic, given
  fixed priority? How would you detect and fix that?

**Q13: Walk me through the DECERR hang bug — how did you localize it?**
- Follow-up 1: What made you suspect the ready-signal logic specifically, rather than the state
  machine's transition logic?
- Follow-up 2: Why did the full system testbench's Phase 2 not immediately point at the fix — what
  did the isolated directed test (`debug_decerr.sv`) give you that the full testbench's failure
  message didn't?
- Follow-up 3: How would a static tool (lint, or a "no dangling VALID without READY" check) have
  caught this before simulation?

**Q19: What's the cost of the "grant on AWVALID && WVALID together" simplification?**
- Follow-up 1: Give a concrete master behavior that this design would handle correctly but a
  stricter interconnect wouldn't need to.
- Follow-up 2: Give a concrete master behavior (AW arriving several cycles before W) that this
  design's ARBITER can't currently handle, even though the downstream SLAVES could.
- Follow-up 3: What would you have to add to support that case — where does the complexity go?

## E. Whiteboard problems

1. Design a round-robin arbiter for N requesters.
2. Design a fixed-priority arbiter for N requesters, and discuss starvation.
3. Design an address decoder for M regions given base+size pairs, handling the "no match" case.
4. Design a valid/ready handshake between a manager and a completer from scratch.
5. Design an AXI-Lite-to-APB bridge's state machine on a whiteboard (SETUP/ACCESS/RESP).
6. Given 2 masters and 1 slave, design the minimum logic needed to arbitrate and route correctly.
7. Explain, without RTL, why AXI response codes need to distinguish "no such address" from "address
   exists but this specific access is illegal."
8. A colleague says "let's just OR both masters' AWVALID together and always pick master 0 if it's
   ever asserted" — explain what's wrong with treating this as a complete arbiter.
9. Design a simple APB completer (SETUP/ACCESS, PREADY, PSLVERR) for a single register, from scratch.
