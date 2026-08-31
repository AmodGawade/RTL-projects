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
