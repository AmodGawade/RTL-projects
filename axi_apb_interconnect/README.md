# AXI4-Lite SoC Interconnect + APB Subsystem

Reconstruction of the "AXI4-Lite SoC Interconnect + APB Subsystem" project. See
`../docs/claims.md` §2 for the exact claim-to-implementation mapping.

## Layout

```
axi_apb_interconnect/
├── rtl/
│   ├── axi_lite_pkg.sv           -- shared RESP_OKAY/SLVERR/DECERR constants
│   ├── axi_lite_regfile.sv       -- generic AXI4-Lite slave (used as slave0 and slave1)
│   ├── apb_regbank.sv             -- APB completer, real SETUP/ACCESS timing, error handling
│   ├── axi_lite_to_apb_bridge.sv -- converts one AXI4-Lite transaction into an APB sequence
│   └── axi_lite_interconnect.sv  -- 2-master/3-slave arbiter + address decode + router
├── tb/
│   └── tb_axi_lite_apb_interconnect.sv  -- full-system self-checking testbench
├── sim/
│   ├── run_sim.sh                 -- compile + run with Icarus Verilog
│   └── synth/                     -- Vivado non-project-mode synthesis flow (NOT executed here)
└── docs/
    ├── architecture.md            -- block diagram, address map, design decisions
    ├── verification.md            -- verification strategy + 2 real bugs found and fixed
    └── prep.md                     -- 60s/5min explanations, 15+ Q&A, whiteboard problems
```

## Running the testbench

```bash
cd sim
./run_sim.sh          # seed=1
./run_sim.sh 42         # different seed -> different Phase 5 randomized traffic pattern
```

Requires the `iverilog/14.0` environment module (or `iverilog`/`vvp` on PATH some other way).
**Verified passing** across 7+ random seeds — this is not a claim, it was actually run; see
`docs/verification.md` for what "passing" checks and for the two real bugs found and fixed along
the way (a DECERR hang, and unreset register storage).

## Synthesis

`sim/synth/run_synth.tcl` + `sim/synth/axi_lite_interconnect.sdc` are real, runnable Vivado
non-project-mode scripts — **not executed in this environment** (no Vivado install here). Run them
yourself for real utilization/timing numbers.

## Status

- RTL: complete — interconnect, 2 generic AXI4-Lite slaves, AXI4-Lite-to-APB bridge, APB register
  bank with error handling.
- Testbench: complete, self-checking, passing across directed + concurrent-contention + randomized
  phases, across 7+ seeds.
- Two real bugs found by testing, not assumed away: a DECERR grant that never acknowledged the
  requesting master's handshake (protocol-completeness bug), and register storage that was never
  reset (state-initialization bug only randomized testing surfaced). See `docs/verification.md`.
- Synthesis: scripted but unexecuted (no Vivado available) — see honesty note above.
