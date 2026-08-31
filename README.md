# RTL Projects

Two digital design projects, implemented as synthesizable SystemVerilog with self-checking
testbenches, compiled and simulated with Icarus Verilog 14.0:

1. **Asynchronous FIFO + CDC Infrastructure** — a parameterized dual-clock FIFO with Gray-coded
   pointers, multi-flop synchronizers, and reset synchronization across independent clock domains.
2. **AXI4-Lite Interconnect + APB Subsystem** — a 2-master/3-slave AXI4-Lite interconnect with
   address decoding and arbitration, plus an AXI4-Lite-to-APB bridge and APB register bank.

## Repository structure

```
.
├── async_fifo/                             Asynchronous FIFO + CDC Infrastructure
│   ├── README.md
│   ├── rtl/        7 modules: rst_sync, sync_r2r, fifo_mem, wptr_full, rptr_empty,
│   │               fifo_sva_checker, async_fifo
│   ├── tb/         tb_async_fifo.sv
│   ├── sim/        run_sim.sh, synth/ (Vivado Tcl + SDC)
│   └── docs/       architecture.md, cdc_notes.md, verification.md
└── axi_apb_interconnect/                   AXI4-Lite Interconnect + APB Subsystem
    ├── README.md
    ├── rtl/        5 modules: axi_lite_pkg, axi_lite_regfile, apb_regbank,
    │               axi_lite_to_apb_bridge, axi_lite_interconnect
    ├── tb/         tb_axi_lite_apb_interconnect.sv
    ├── sim/        run_sim.sh, synth/ (Vivado Tcl + SDC)
    └── docs/       architecture.md, verification.md
```

## Running the simulations

```bash
cd async_fifo/sim                 && ./run_sim.sh   # PASS, DEPTH=16/WIDTH=8, seed=1
cd ../../axi_apb_interconnect/sim && ./run_sim.sh   # PASS, seed=1
```

Both pass across multiple random seeds, and the FIFO project additionally sweeps depth/width
parameter combinations. See each project's own `docs/verification.md` for verification strategy
and the bugs found and fixed during development.

## Highlights

- **Clock-domain crossing**: metastability-safe synchronizer design, Gray-code pointer encoding
  for multi-bit CDC, and asynchronous-assert/synchronous-deassert reset synchronization
  (`async_fifo/docs/cdc_notes.md`).
- **AMBA protocol implementation**: AXI4-Lite VALID/READY handshaking, response coding
  (OKAY/SLVERR/DECERR), and APB SETUP/ACCESS timing, including a protocol bridge between the two
  (`axi_apb_interconnect/docs/architecture.md`).
- **Arbitration and address decoding**: fixed-priority arbitration with backpressure propagation
  across concurrent masters.
- **Verification**: self-checking testbenches with reference-model scoreboards, SVA-based
  property checks, and randomized stimulus (clock ratios, traffic patterns, reset timing) that
  surfaced real design bugs — documented with root cause and fix in each project's
  `docs/verification.md`.
- **Static timing analysis groundwork**: Vivado non-project-mode synthesis scripts and SDC timing
  constraints for both designs (`sim/synth/`).
