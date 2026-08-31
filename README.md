# RTL Technical Prep Repo

Reconstructions of two projects, built as real, simulatable SystemVerilog and actually
compiled and run (Icarus Verilog 14.0) — not written and assumed correct. Scope is deliberately
limited to these two (per explicit direction): the MIPS Processor Simulation project and the
Agrani-inspired reconstructions (OTP Fuse Controller, CSR/RDL, AMBA interconnect) are out of scope
here.

See `docs/claims.md` for the exact claim-to-implementation table this whole
repo is grounded in — read that first if anything below seems oddly specific (an address map, a
depth choice, a response code) — the mapping doc explains which source claim it satisfies and which
part was an explicit, documented assumption.

## Repository tree

```
random/
├── README.md                              (this file)
├── docs/
│   └── claims.md            source claim -> implementation mapping (read first)
├── async_fifo/                             Project 1: Asynchronous FIFO + CDC Infrastructure
│   ├── README.md
│   ├── rtl/        (7 files: rst_sync, sync_r2r, fifo_mem, wptr_full, rptr_empty,
│   │                 fifo_sva_checker, async_fifo)
│   ├── tb/         tb_async_fifo.sv
│   ├── sim/        run_sim.sh, synth/ (Vivado Tcl + SDC, unexecuted -- see honesty notes)
│   └── docs/       architecture.md, cdc_notes.md, verification.md, prep.md
└── axi_apb_interconnect/                   Project 2: AXI4-Lite Interconnect + APB Subsystem
    ├── README.md
    ├── rtl/        (5 files: axi_lite_pkg, axi_lite_regfile, apb_regbank,
    │                 axi_lite_to_apb_bridge, axi_lite_interconnect)
    ├── tb/         tb_axi_lite_apb_interconnect.sv
    ├── sim/        run_sim.sh, synth/ (Vivado Tcl + SDC, unexecuted -- see honesty notes)
    └── docs/       architecture.md, verification.md, prep.md
```

## Running everything

```bash
cd async_fifo/sim          && ./run_sim.sh              # PASS, DEPTH=16/WIDTH=8, seed=1
cd ../../axi_apb_interconnect/sim && ./run_sim.sh        # PASS, seed=1
```

Both are **verified passing** — actually compiled and simulated, multiple seeds, multiple parameter
sweeps for the FIFO project — not a claim taken on faith. See each project's own `docs/
verification.md` for exactly what's checked and the real bugs found and fixed along the way.

## What's real vs. what's honestly caveated

| | Real, verified | Honestly caveated |
|---|---|---|
| RTL | Both projects' full RTL, compiled and simulated | — |
| Testbenches | Both, self-checking, passing across multiple seeds | Reset-with-data-in-flight is an explicitly untested, architecturally-undefined case for the FIFO (see cdc_notes.md) |
| Bugs found | 3 real bugs total (1 FIFO assertion-encoded-a-false-invariant, 2 in the interconnect: DECERR hang + unreset registers), all logged with before/after evidence | — |
| Synthesis | Scripts are real and runnable | **Not executed** — no Vivado in this environment. No area/timing number anywhere in this repo should be treated as measured; run the scripts yourself |
| Toolchain gotchas | 6 confirmed Icarus Verilog 14.0 limitations, each isolated with a minimal reproduction before being trusted (see async_fifo's verification.md) | — |

## Concepts to study for a Digital Design Engineer technical discussion

Grounded in what these two projects actually exercise, roughly in priority order:

1. **Metastability and synchronizer theory** — why 2 flops, what MTBF means, when 3+ is justified.
   (`async_fifo/docs/cdc_notes.md` §1–2)
2. **Gray code for CDC** — the one-bit-change property, why binary pointers are unsafe to
   synchronize directly, full/empty derivation from Gray pointers. (`cdc_notes.md` §3, §5)
3. **Reset synchronization** — async assert / sync deassert, and why deassertion timing matters.
   (`cdc_notes.md` §6)
4. **AXI4/AXI4-Lite protocol semantics** — VALID/READY rules (never wait for READY before VALID),
   response codes (OKAY/SLVERR/DECERR) and when each applies, why AXI4-Lite has no bursts/IDs the
   way full AXI4 does. (`axi_apb_interconnect/docs/architecture.md`, `prep.md` §Fundamentals)
5. **APB protocol** — SETUP/ACCESS timing, PSEL/PENABLE/PREADY relationship, PSLVERR semantics.
   (`axi_apb_interconnect/rtl/apb_regbank.sv`'s comments)
6. **Arbitration** — fixed-priority vs. round-robin, starvation, whole-transaction vs. per-beat
   granularity. (`axi_apb_interconnect/docs/prep.md` §D)
7. **Protocol bridging** — what it actually means to convert one handshake protocol into another
   (not just wire renaming) — AXI4-Lite-to-APB as the concrete example.
8. **Verification methodology fundamentals** — self-checking testbenches vs. UVM, when each is the
   right amount of machinery, scoreboards, functional coverage, the specific SVA properties that
   matter (not assertions for quantity).
9. **The distinction between a design bug, a testbench bug, and a toolchain limitation** — this
   repo's actual debugging history (the false full/empty invariant, the DECERR hang, the unreset
   registers, and the 6 Icarus gotchas) is real practice material for exactly this skill, which is
   frequently probed directly ("tell me about a bug you found").
10. **Static timing analysis basics** — clock definitions, false paths, `-datapath_only`, why
    asynchronous clock groups matter, critical path / slack vocabulary (both projects' `sim/synth/`
    SDC files, even though unexecuted, are genuine study material for this).

## Claims to be prepared to defend

Every bullet below is something the source states and this repo either substantiates directly or
documents as an assumption — see `docs/claims.md` for the full table. Quick-reference
list of what you should be able to open the actual RTL for and explain line-by-line:

**Asynchronous FIFO + CDC Infrastructure**
- "parameterized asynchronous FIFO supporting independent read/write clock domains" — `async_fifo.sv`
- "Gray-coded pointers and synchronized CDC control signals" — `wptr_full.sv`, `rptr_empty.sv`, `sync_r2r.sv`
- "robust reset and full/empty handling across asynchronous clock domains" — `rst_sync.sv` + cdc_notes.md §7's finding
- "verified boundary conditions using randomized clock ratios and reset sequences" — `tb_async_fifo.sv` Phases 0/1/2/6
- "Synthesized ... applied timing constraints ... across multiple depth/width configurations" — `sim/synth/`, honestly caveated as unexecuted; the depth/width *simulation* sweep (4/8/16/32 × 4/8/32) is real and passing

**AXI4-Lite SoC Interconnect + APB Subsystem**
- "parameterized 2-master AXI4-Lite interconnect with address decoding, arbitration, and backpressure handling" — `axi_lite_interconnect.sv`
- "routing read/write transactions across 3 memory-mapped slaves" — `tb_axi_lite_apb_interconnect.sv` Phase 1
- "AXI4-Lite-to-APB bridge and APB peripheral register bank with configurable address mapping and error handling" — `axi_lite_to_apb_bridge.sv`, `apb_regbank.sv`, Phase 2 (DECERR vs SLVERR)
- "Synthesized ... authored SDC timing constraints ... iterated RTL based on timing/area results" — `sim/synth/`, honestly caveated as unexecuted

**What this repo does NOT claim to substantiate** (per the scope note, unchanged from earlier in
this conversation): the MIPS Processor Simulation project, and the Agrani Labs Inc. bullets (OTP
Fuse Controller, Boot Subsystem CSR/RDL, AMBA interconnect) — none of those are reconstructed here.
If asked about them, that's a separate preparation exercise, not covered by this
repo.
