# Async FIFO + CDC Infrastructure

Asynchronous FIFO + CDC Infrastructure project.

## Layout

```
async_fifo/
├── rtl/
│   ├── rst_sync.sv          -- async-assert/sync-deassert reset synchronizer
│   ├── sync_r2r.sv          -- generic N-bit 2-flop synchronizer (for Gray pointers)
│   ├── fifo_mem.sv           -- storage array, one write port + one combinational read port
│   ├── wptr_full.sv          -- write pointer + full-flag generation (wr_clk domain)
│   ├── rptr_empty.sv         -- read pointer + empty-flag generation (rd_clk domain)
│   ├── fifo_sva_checker.sv  -- simulation-only property checks (see docs/verification.md)
│   └── async_fifo.sv        -- top-level, wires everything together
├── tb/
│   └── tb_async_fifo.sv     -- self-checking testbench (see docs/verification.md)
├── sim/
│   ├── run_sim.sh            -- compile + run with Icarus Verilog
│   └── synth/                -- Vivado non-project-mode synthesis flow
└── docs/
    ├── architecture.md       -- block diagram, design decisions, corner cases
    ├── cdc_notes.md           -- CDC technique explanations (read this first)
    └── verification.md       -- verification strategy + toolchain gotchas found along the way
```

## Running the testbench

```bash
cd sim
./run_sim.sh                  # seed=1, DEPTH=16, DATA_WIDTH=8
./run_sim.sh 42                # different seed -> different randomized clock ratio
./run_sim.sh 11 4 8             # DEPTH=4 sweep point (see docs/cdc_notes.md #7 for what this reveals)
./run_sim.sh 7 8 32             # DEPTH=8, DATA_WIDTH=32
```

Requires the `iverilog/14.0` environment module (or `iverilog`/`vvp` on PATH some other way).
Passing across DEPTH ∈ {4, 8, 16, 32}, DATA_WIDTH ∈ {4, 8, 32}, and multiple random seeds
(different clock ratios each time); see `docs/verification.md` for what "passing" checks.

## Synthesis

`sim/synth/run_synth.tcl` + `sim/synth/async_fifo.sdc` are Vivado non-project-mode scripts for
utilization/timing analysis.

RTL matches the classic Cummings dual-clock FIFO architecture. One design insight found by
testing: full/empty can transiently (and correctly, harmlessly) disagree at very shallow depths
relative to synchronizer latency — see `docs/cdc_notes.md` §7. An earlier assertion encoding the
opposite (wrong) assumption was found and fixed as a direct result.
