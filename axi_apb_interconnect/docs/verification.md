# Verification Strategy — AXI4-Lite Interconnect + APB Subsystem

## What is being tested (tb_axi_lite_apb_interconnect.sv)

| Phase | What it exercises |
|---|---|
| 1 | Directed single-master write+read to each of the 3 regions (regfile0, regfile1, APB bridge) |
| 2 | Error handling: unmapped address (DECERR), and an APB address in-aperture but past `apb_regbank`'s real register range (SLVERR) |
| 3 | Both masters contend for the SAME region concurrently (arbitration under real contention) |
| 4 | Both masters access DIFFERENT regions concurrently (should proceed independently, not serialize unnecessarily) |
| 5 | 60 rounds of randomized master/region/read-or-write/data traffic |

A shadow model (plain arrays, one per region) tracks what SHOULD be in each register, built purely
from what the testbench itself writes — independent of the RTL, the actual scoreboard.

## What constitutes a failure

1. A response code that doesn't match expectation (OKAY where an error was expected, or vice versa).
2. A data mismatch on a read (`sb_rdata !== expected` from the shadow model).
3. The simulation hanging (a `$finish` timeout backstop) — would indicate a master's request never
   got acknowledged, exactly the class of bug found and fixed below.

## Invariants that should always hold

- Every request eventually gets a response — no request is ever left permanently un-acknowledged,
  whether it targets a real slave or nothing at all.
- DECERR is returned only for genuinely unmapped addresses; SLVERR is returned only when a request
  reached a real slave that itself rejected it (illegal offset within `apb_regbank`) — these are
  deliberately different response codes for different failure classes, not interchangeable.
- Data written to a real, valid register is exactly the data read back, regardless of which master
  wrote it, which master reads it, or how much unrelated contention happens in between.
- A master never observes another master's transaction's response.
- Register storage resets to a defined, known value (0) — never silently holds X.

## Two real bugs found by testing, not assumed correct

### 1. DECERR grant never acknowledged the requesting master's handshake (hang)

An early version of `axi_lite_interconnect.sv` only drove `AWREADY`/`WREADY`/`ARREADY` while
actively routing to a REAL slave (`WR_ACTIVE`/`RD_ACTIVE`). The DECERR path transitioned the
internal state machine correctly and even asserted `BVALID`/`RVALID` with the right error code —
but never asserted the requesting master's own `*READY`, so from the master's point of view its
request just sat there forever, unacknowledged. Found immediately by an isolated directed test
(`debug_decerr.sv`) that specifically exercised an out-of-range read and watched for a hang; the
full system testbench's Phase 2 would have hit the exact same hang (confirmed: it did, before the
fix — see the raw run log). **Fixed** by computing the arbitration grant decision in one shared
combinational block, used by both the state-transition logic and the ready-signal logic, so the
granted master's `*READY` asserts on the exact same cycle for both a real-slave grant and a DECERR
grant.

### 2. Register storage never reset — reads of never-written registers returned X

Both `axi_lite_regfile.sv` and `apb_regbank.sv` declared their `regs[]` array but never reset it;
only explicitly-written entries ever got a defined value. Phase 1–4 never caught this (every
register they touched was written before being read). Phase 5's randomized traffic did — it reads
registers that may never have been written yet, and the shadow model (correctly) expects 0 for
those. **Fixed** by adding an explicit reset loop (`for (r) regs[r] <= '0`) to both modules' reset
branch.

**Why this matters**: neither bug was hypothesized in advance — both were
found by actually running the testbench and reading what it reported, exactly the discipline the
async FIFO project also demonstrates (see `../async_fifo/docs/verification.md`'s two toolchain/RTL
findings). This is the answer to "tell me about a bug you found" that's backed by an actual log,
not a rehearsed anecdote.

## Functional coverage that would matter

- Cross of (region 0/1/2) × (master 0/1) × (read/write) — Phase 5's randomization covers this
  directionally; a real coverage plan would track it as an explicit `covergroup` cross and report
  which combinations were actually hit.
- Both-masters-same-region vs. both-masters-different-regions contention (Phases 3/4 cover both
  directedly).
- DECERR vs. SLVERR vs. OKAY response distribution.
- APB `WAIT_CYCLES` > 0 backpressure (this testbench's `apb_regbank` instance uses `WAIT_CYCLES=1`
  — real wait-state behavior is exercised on every APB-routed transaction, not just the 0-wait-state
  case).

## Realistic bugs this testbench is specifically built to catch

- An arbiter that grants the wrong master under simultaneous request (Phase 3 exercises this
  directly, with a shadow model per-region so an actually-swapped grant would show up as a data
  mismatch on the follow-up read).
- Address decode off-by-one at a region boundary (not currently swept exhaustively — see
  `docs/prep.md` for what a more thorough version would add).
- A response routed back to the wrong master (Phase 3/4's contention design would catch this: each
  master's read-back is checked against ITS OWN write, so a misrouted response reads as either a
  hang on one master or a wrong-data mismatch on the other).
- APB SETUP/ACCESS timing violations (an `apb_regbank` that responded before a real SETUP cycle
  would desync the bridge's own state machine, which the end-to-end data check would catch).

## If this were verified with UVM instead

Proportionate scope note, same as the async FIFO project: a self-checking SV testbench is
appropriately sized for a 2-master/3-slave block like this. If it were one block inside a larger
SoC UVM environment, the natural mapping:
- Two `uvm_agent`s (one per AXI4-Lite master), each with driver + monitor.
- A `uvm_scoreboard` per region (or one scoreboard keyed by region+address, matching this repo's
  shadow-array-per-region design) fed by both agents' monitors via analysis ports.
- `uvm_reg`/RAL would genuinely fit here (unlike the FIFO project) — `apb_regbank`'s registers are
  exactly what RAL models; a register model with `mirror`/`predict` could replace the hand-written
  shadow arrays.
- Sequences per phase above, plus a virtual sequencer coordinating the two agents for the
  concurrent-contention phases (3/4).

## Toolchain notes

Same Icarus Verilog 14.0 environment and same discipline as the async FIFO project (see
`../async_fifo/docs/verification.md`'s toolchain-gotchas section for the full list — clocking
blocks, `bind`, concurrent assertions, `$past`/`$rose`/`$changed`, and the broken `$onehot` all
apply equally here since it's the same toolchain). Two additional findings specific to this
project's RTL style:

- **Enum-typed ternary assignment** (`state <= cond ? ENUM_A : ENUM_B;`) triggered an "explicit
  cast required" compile error in this simulator; worked around with a plain `if/else` instead.
  Not a SystemVerilog language issue — just this build's type-checking being stricter than
  necessary here.
- **Forward reference to a later always block's combinational output** (the exact same class of
  bug as the FIFO project's `sb_exp_val` finding) appeared twice more here — once in
  `axi_lite_regfile.sv` (`wr_addr_valid_range_next` used before its computing `always_comb` was
  declared) and once in `axi_lite_to_apb_bridge.sv` (`pslverr_latched`/`prdata_latched`). Both
  fixed the same way: move the declaration (and, where applicable, the computing block) ahead of
  first use.
