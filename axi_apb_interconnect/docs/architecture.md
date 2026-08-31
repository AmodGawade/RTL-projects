# AXI4-Lite SoC Interconnect + APB Subsystem — Architecture

Source claims this map to (see `../docs/claims.md` §2 for the full table):
- Parameterized 2-master AXI4-Lite interconnect: address decoding, arbitration, backpressure
- Routes read/write transactions across 3 memory-mapped slaves
- AXI4-Lite-to-APB bridge + APB peripheral register bank, configurable address mapping, error handling

## Top-level architecture

```
  Master 0 (AXI4-Lite)          Master 1 (AXI4-Lite)
        |                              |
        v                              v
   +--------------------------------------------+
   |            axi_lite_interconnect            |
   |  +----------------+  +--------------------+ |
   |  | write arbiter  |  |  read arbiter       | |
   |  | (fixed-prio,   |  |  (fixed-prio,       | |
   |  |  m0 > m1)      |  |   m0 > m1)          | |
   |  +----------------+  +--------------------+ |
   |          |                     |             |
   |          v                     v             |
   |  +----------------+  +--------------------+ |
   |  | addr decode (AW)|  | addr decode (AR)   | |
   |  +----------------+  +--------------------+ |
   |          |                     |             |
   +----------|---------------------|-------------+
              |         |           |         |
              v         v           v         v
         slave0     slave1     slave2 (AXI4-Lite side of the bridge)
     (axi_lite_    (axi_lite_       |
      regfile)      regfile)        v
                              +---------------+      +----------------+
                              | axi_lite_to_  |----->| apb_regbank    |
                              | apb_bridge    |<-----| (APB completer)|
                              +---------------+      +----------------+
```

Only ONE master's write transaction, and (independently) only ONE master's read transaction, is
"in flight" through the interconnect at any time — this is a shared/muxed bus, not a full crossbar
with independent simultaneous paths per master. The arbiter grants exclusive use of the downstream
write (or read) path to one master for the duration of one full transaction (AW+W+B, or AR+R), then
re-arbitrates. This is the simplest reasonable interpretation of "arbitration and backpressure
handling" for a 2-master interconnect (see `../docs/claims.md` §2) — a full
independent-per-master crossbar would be architecturally heavier than what a 2-master, 3-slave
design needs, and the source doesn't claim outstanding-transaction-level concurrency.

## Major modules

| Module | Role |
|---|---|
| `axi_lite_interconnect` | Arbitration + address decode + routing; the crossbar itself |
| `axi_lite_regfile` | Generic downstream AXI4-Lite slave (a small register file); instantiated twice, for slave0/slave1 |
| `axi_lite_to_apb_bridge` | Converts one AXI4-Lite slave-side transaction into an APB SETUP/ACCESS sequence |
| `apb_regbank` | APB completer: a small addressable register bank with error handling on illegal offsets |

## Address map (see claims.md's "Assumption made" column — source doesn't specify
## exact offsets, this is a documented, simple, equal-size 3-way split)

| Region | Base | Size | Target |
|---|---|---|---|
| 0 | `0x0000_0000` | 4KB | slave0 (`axi_lite_regfile #0`) |
| 1 | `0x0000_1000` | 4KB | slave1 (`axi_lite_regfile #1`) |
| 2 | `0x0000_2000` | 4KB | slave2 (`axi_lite_to_apb_bridge` -> `apb_regbank`) |
| any other address | -- | -- | DECERR, no downstream access at all |

`apb_regbank`'s own aperture size and base offset (within region 2) are separate `parameter`s on
that module — this is the "configurable address mapping" the source claims for the APB side
specifically, distinct from the interconnect's own (fixed, documented) 3-way split.

## Interfaces

Flat (non-`interface`-based) AXI4-Lite signal bundles are used throughout — `AWVALID/AWREADY/
AWADDR/AWPROT`, `WVALID/WREADY/WDATA/WSTRB`, `BVALID/BREADY/BRESP`, `ARVALID/ARREADY/ARADDR/
ARPROT`, `RVALID/RREADY/RDATA/RRESP` per port, doubled for the two master-facing ports and tripled
for the three slave-facing ports. This is a deliberate portability choice, not an oversight:
SystemVerilog `interface`/`modport` support was not tested against this repo's Icarus Verilog
toolchain before committing to it, given the async FIFO project already found several SV feature
gaps in this exact toolchain (clocking blocks, `bind`, concurrent assertions — see
`../async_fifo/docs/verification.md`'s toolchain-gotchas section). Flat ports also mirror how a lot
of real interconnect RTL is written specifically for portability across simulators and lint tools.

## Clock/reset domains

Single clock domain, single synchronous active-low reset (`aresetn`) — this project has no CDC
content; that's the async FIFO project's territory. All channels are registered; no combinational
path from any input directly to any output within a single cycle (the arbiter's grant decision
and address decode are combinational, but they gate registered handshake state, not raw pass-through).

## Data / control flow: one write transaction, cycle by cycle

1. A master asserts `AWVALID` with `AWADDR` (and eventually `WVALID`/`WDATA`/`WSTRB`).
2. The write arbiter, if the write path is idle, grants that master (fixed priority: master 0 before
   master 1 if both request in the same cycle) and asserts that master's `AWREADY`.
3. Address decode combinationally maps `AWADDR` to one of the 3 slave targets (or DECERR).
4. The interconnect forwards `AWVALID/AWADDR` and `WVALID/WDATA/WSTRB` to the selected slave's AW/W
   ports, and forwards that slave's `AWREADY/WREADY` back to the granted master.
5. Once the slave asserts `BVALID`, the interconnect forwards it (and `BRESP`) back to the granted
   master, and once `BREADY` completes the handshake, the write path returns to idle and
   re-arbitrates.
6. If address decode found no valid target, the interconnect itself generates the `BRESP=DECERR`
   response directly (no slave is actually touched) — same arbitration/grant bookkeeping, different
   response source.

Read transactions follow the symmetric AR/R sequence, arbitrated independently of writes (a master
can have a write and a read both attempted at once; each is arbitrated on its own path).

## Key state machines

- **Write arbiter**: `IDLE -> GRANTED -> IDLE` per grant cycle — `GRANTED` holds until `BVALID &&
  BREADY` for the currently-granted master, then re-arbitrates.
- **Read arbiter**: symmetric, `IDLE -> GRANTED -> IDLE` gated on `RVALID && RREADY`.
- **`axi_lite_to_apb_bridge`**: `IDLE -> APB_SETUP -> APB_ACCESS -> RESP`, implementing the APB
  2-phase SETUP/ACCESS sequence from a single AXI4-Lite transaction, per APB4 protocol rules.

## Key design decisions

- **Fixed-priority arbitration (master 0 > master 1), not round-robin** — simplest reasonable choice
  for a 2-master design (see claims.md); round-robin is discussed in
  `axi_lite_interconnect.sv`'s comments as the natural alternative if fairness under sustained
  contention from both masters ever mattered, but isn't implemented as the default.
- **Whole-transaction granularity arbitration**, not per-beat — since AXI4-Lite has no burst
  (`AWLEN`/`ARLEN` don't exist), "per-transaction" and "per-beat" are almost the same thing here
  anyway; this just means the W channel isn't separately arbitrated from its AW.
- **Address-decode-generated DECERR for unmapped addresses**, not a silent hang — an accessed
  address outside all 3 regions must still get a response (AXI VALID/READY semantics require every
  request to eventually complete), so the interconnect itself completes the transaction with
  `BRESP`/`RRESP = DECERR` rather than leaving the master waiting forever.
- **APB bridge is a real protocol converter, not a passthrough** — implements the actual
  SETUP-then-ACCESS timing APB requires, not just a same-cycle reinterpretation of AXI signals.

## Parameterization

- `ADDR_WIDTH`, `DATA_WIDTH` on the interconnect and both slave types.
- `apb_regbank`: `BASE_ADDR`, `APERTURE_SIZE`, `NUM_REGS` — the "configurable address mapping" claim.

## Corner cases handled

- Both masters asserting `AWVALID` in the same cycle — arbiter picks one deterministically (fixed
  priority), the other's `AWREADY` stays low (backpressure) until granted.
- A master asserting `AWVALID` well before `WVALID` (or vice versa) — the interconnect doesn't
  assume they arrive together; the bridge/regfile slaves are simply not exercised (their `WREADY`/
  `AWREADY` reflect real skew, not an assumed lockstep).
- Access to an unmapped address — DECERR, no downstream slave touched, no hang.
- Illegal offset within the APB region (mapped through the bridge, but past `apb_regbank`'s own
  valid register range) — `apb_regbank` returns `PSLVERR`, and the bridge maps that to
  `BRESP/RRESP = SLVERR` (distinguishing "address decode failure" (DECERR) from "reached a real
  slave, which itself rejected the access" (SLVERR) — the AXI-correct distinction between the two
  error responses).
