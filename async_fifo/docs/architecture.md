# Async FIFO + CDC Infrastructure — Architecture

Design goals this covers:
- Parameterized async FIFO, independent read/write clocks
- Gray-coded pointers, synchronized CDC control signals
- Robust reset + full/empty handling across clock domains
- Verified with randomized clock ratios, reset sequences, boundary conditions

This follows the classic **Cummings dual-clock FIFO architecture** ("Simulation and Synthesis
Techniques for Asynchronous FIFO Design", SNUG 2002) — the standard, textbook structure for this
problem, and the one you're most likely expected to derive on a whiteboard. Nothing here is
employer-specific; this is generic, public-domain FIFO design.

## Top-level architecture

```
                    wr_clk domain                    |                    rd_clk domain
                                                       |
   wdata,wr_en --> +----------------+                  |
                    |  wptr_full     |--wptr(bin)--+     |
   wr_rst_n   --> |  (write ptr +  |             |     |
                    |   full logic)  |<--rq2_wptr--+--(sync)--+     |
                    +----------------+             |          |     |
                            |  waddr (bin, lower N bits)        |     |
                            v                                    |     |
                    +----------------+                            |     |
                    |   fifo_mem     |  dual-port RAM              |     |
                    |  (wr_clk write,|  1 write port / 1 read port |     |
                    |   rd_clk read) |                              |     |
                    +----------------+                            |     |
                            ^                                    |     |
                            |  raddr (bin, lower N bits)        |     |
                    +----------------+             |          |     |
                    |  rptr_empty    |<--wq2_rptr--+--(sync)--+     |
   rd_rst_n   --> |  (read ptr +   |             |     |
                    |   empty logic) |--rptr(bin)--+     |
   rd_en,rdata <-- +----------------+                  |
                                                       |
   full  <---------- wptr_full                        |
   empty <-------------------------------------- rptr_empty
```

Two Gray-code synchronizer instances cross the clock boundary (`sync_r2r`), one per direction:
`rq2_wptr` (write pointer, Gray-coded, synchronized into the read domain to generate `empty`) and
`wq2_rptr` (read pointer, Gray-coded, synchronized into the write domain to generate `full`). These
are the **only** signals that cross domains. Everything else (`wdata`, `rdata`, `wr_en`, `rd_en`,
`full`, `empty`) is local to its own clock domain.

## Major modules

| Module | Domain | Responsibility |
|---|---|---|
| `rst_sync` | either (instantiated once per domain) | Asynchronous-assert, synchronous-deassert reset synchronizer |
| `sync_r2r` | destination domain | Generic N-bit 2-flop synchronizer for a Gray-coded bus |
| `wptr_full` | `wr_clk` | Write-pointer increment, binary→Gray conversion, full-flag generation |
| `rptr_empty` | `rd_clk` | Read-pointer increment, binary→Gray conversion, empty-flag generation |
| `fifo_mem` | both (dual-port) | Storage array, one write port clocked by `wr_clk`, one read port clocked by `rd_clk` |
| `async_fifo` | top | Wires the above together, exposes the external interface |

## Interfaces

```
async_fifo #(.DATA_WIDTH(8), .DEPTH(16)) u_fifo (
  .wr_clk   (wr_clk),   .wr_rst_n (wr_rst_n),
  .wr_en    (wr_en),    .wdata    (wdata),   .full  (full),
  .rd_clk   (rd_clk),   .rd_rst_n (rd_rst_n),
  .rd_en    (rd_en),    .rdata    (rdata),   .empty (empty)
);
```

`DEPTH` must be a power of 2 (checked with an elaboration-time assertion) — this is what makes the
extra-MSB Gray-code wrap-detection trick in the full/empty comparison valid; a non-power-of-2 depth
needs a different (uglier) full/empty scheme and is out of scope here since the source doesn't claim
it.

## Clock/reset domains

- **`wr_clk` domain**: `wr_rst_n` (external), `wr_en`, `wdata`, `full`, the write pointer, and the
  synchronized *read* pointer copy used to compute `full`.
- **`rd_clk` domain**: `rd_rst_n` (external), `rd_en`, `rdata`, `empty`, the read pointer, and the
  synchronized *write* pointer copy used to compute `empty`.
- The two domains are assumed **fully asynchronous** (no fixed phase/frequency relationship) — this
  is the whole reason Gray coding and synchronizers are needed at all. If the clocks were related
  (e.g. same clock, or one an integer multiple of the other), a much simpler synchronous FIFO would
  suffice and this design would be over-engineered for that case.
- Each domain resets independently. A reset in one domain does **not** by itself reset the other
  domain's pointer — but `wptr_full`/`rptr_empty` treat "my synchronized copy of the other pointer
  reads as all-zero after the other side resets" as the mechanism that re-establishes a consistent
  full/empty state, which is why both `rst_sync` instances matter even though they're not literally
  wired to each other.

## Data / control flow (one write, cycle by cycle)

1. Producer asserts `wr_en=1` with `wdata` valid, provided `full=0`.
2. On the next `wr_clk` edge, `fifo_mem` latches `wdata` at address `waddr` (binary write pointer's
   lower `ADDR_WIDTH` bits), and `wptr_full` increments the write pointer (binary and Gray copies
   both advance).
3. The new Gray write pointer ripples into the read domain through `sync_r2r` — **2 `rd_clk` cycles
   later** it's visible to `rptr_empty`, which drops `empty` once it sees the write pointer differs
   from the read pointer.
4. Consumer, seeing `empty=0`, asserts `rd_en=1`; on the next `rd_clk` edge `fifo_mem`'s read port
   presents the data at `raddr`, and `rptr_empty` increments the read pointer.
5. The new Gray read pointer ripples back into the write domain the same way, 2 `wr_clk` cycles
   later, and `wptr_full` re-evaluates `full`.

The 2-cycle (per direction) synchronizer latency is **why** `full`/`empty` are always pessimistic —
by design, the FIFO can look "not full" for a couple of cycles after it has actually become full
from the other side's perspective, and vice versa. That's expected and safe: the flags only ever
lag toward the *safe* side (never say not-full when it's actually full, only the reverse-direction
information is what's briefly stale).

## Key state machines

There isn't a classical multi-state FSM here — `wptr_full`/`rptr_empty` are best understood as
**counters with combinational flag logic**, not FSMs. If asked to draw an FSM for
this design, the honest answer is: full/empty are Moore-style outputs of the pointer-comparison
logic, not states of an explicit state register. Worth saying this explicitly rather than inventing
a state diagram that doesn't exist in the RTL.

## Key design decisions

- **Gray code over binary for the crossing pointers** — guarantees only one bit changes per
  increment, so a synchronizer sampling mid-transition captures either the old or the new value,
  never a bit-combination that was never a real pointer value. Binary pointers don't have this
  property (e.g. `0111`→`1000` changes every bit at once).
- **Extra MSB on both pointers** (`ADDR_WIDTH+1` bits wide) — lets full/empty be distinguished by
  comparing the *whole* pointer (including that extra bit) rather than needing a separate counter:
  `empty` when pointers are fully equal, `full` when they're equal in the lower bits but differ in
  the extra MSB (meaning the write pointer has wrapped exactly one more time than the read pointer).
- **2-flop synchronizers, not more** — the minimum needed to reduce metastability probability to
  acceptable MTBF for an educational/typical design; documented in `docs/cdc_notes.md` including
  when 3+ stages would actually be justified.
- **Dual-port RAM inferred, not built from flops** — write port fully owned by `wr_clk`, read port
  fully owned by `rd_clk`; no synchronization needed on the memory array itself because pointers
  (not data) are what cross domains, and each side only ever touches its own port.

## Parameterization

- `DATA_WIDTH` — width of stored words, no constraint.
- `DEPTH` — must be a power of 2; `ADDR_WIDTH = $clog2(DEPTH)` derived internally.

## Corner cases handled

- **Simultaneous full write-attempt and read** — `wr_en` while `full=1` is a no-op (write ignored,
  no pointer increment); the design does not silently corrupt memory on a "write while full".
- **Simultaneous empty read-attempt and write** — `rd_en` while `empty=1` is a no-op.
- **Pointer wraparound** — the extra MSB is exactly the mechanism that makes wraparound safe; tested
  explicitly in the testbench by running enough traffic to wrap the pointer multiple times.
- **Back-to-back reset** — `rst_sync` handles asynchronous assertion (immediate) with synchronous
  deassertion (no reset-removal race into the first post-reset clock edge).
- **Simultaneous read and write to a not-full, not-empty FIFO** — fully supported; the two ports are
  independent every cycle (this is exactly what "dual-port, dual-clock" means).
