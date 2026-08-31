# RTL Technical Prep Repo

Two projects, built as real, simulatable SystemVerilog and actually compiled and run (Icarus
Verilog 14.0): an Asynchronous FIFO + CDC Infrastructure project, and an AXI4-Lite Interconnect +
APB Subsystem project.

## Repository tree

```
random/
├── README.md                              (this file)
├── async_fifo/                             Project 1: Asynchronous FIFO + CDC Infrastructure
│   ├── README.md
│   ├── rtl/        (7 files: rst_sync, sync_r2r, fifo_mem, wptr_full, rptr_empty,
│   │                 fifo_sva_checker, async_fifo)
│   ├── tb/         tb_async_fifo.sv
│   ├── sim/        run_sim.sh, synth/ (Vivado Tcl + SDC)
│   └── docs/       architecture.md, cdc_notes.md, verification.md, prep.md
└── axi_apb_interconnect/                   Project 2: AXI4-Lite Interconnect + APB Subsystem
    ├── README.md
    ├── rtl/        (5 files: axi_lite_pkg, axi_lite_regfile, apb_regbank,
    │                 axi_lite_to_apb_bridge, axi_lite_interconnect)
    ├── tb/         tb_axi_lite_apb_interconnect.sv
    ├── sim/        run_sim.sh, synth/ (Vivado Tcl + SDC)
    └── docs/       architecture.md, verification.md, prep.md
```

## Running everything

```bash
cd async_fifo/sim          && ./run_sim.sh              # PASS, DEPTH=16/WIDTH=8, seed=1
cd ../../axi_apb_interconnect/sim && ./run_sim.sh        # PASS, seed=1
```

Both pass across multiple seeds, and the FIFO project sweeps multiple depth/width parameter
combinations. See each project's own `docs/verification.md` for what's checked and the bugs found
and fixed along the way.

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
   repo's debugging history (the full/empty invariant, the DECERR hang, the unreset registers, and
   the Icarus gotchas) is real practice material for exactly this skill, which is frequently probed
   directly ("tell me about a bug you found").
10. **Static timing analysis basics** — clock definitions, false paths, `-datapath_only`, why
    asynchronous clock groups matter, critical path / slack vocabulary (both projects' `sim/synth/`
    SDC files are study material for this).
