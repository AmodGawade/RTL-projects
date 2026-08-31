# Claim → Implementation Mapping

**Source of truth**: `hmm.pdf` (uploaded source document, as recorded 2026-08-31). No source wording is
changed anywhere in this document or repo — this is a mapping *from* the source, not a rewrite *of*
it. Every "Assumption" below is an engineering decision made to fill a gap the source itself leaves
open; where a claim cannot be reconstructed without proprietary information, that is stated
explicitly rather than invented.

**Scope note**: per explicit direction, this repo covers only the two RTL/digital-design projects
below (Async FIFO + CDC, AXI4-Lite interconnect + APB). MIPS Processor Simulation and the
Agrani-inspired reconstructions (OTP Fuse Controller, CSR/RDL, AMBA interconnect) are intentionally
out of scope here.

---

## 1. Asynchronous FIFO + CDC Infrastructure (Dec 2025 – Jan 2026)

| Claim | Technical meaning | Implementation required | Ambiguous? | Assumption made |
|---|---|---|---|---|
| "parameterized asynchronous FIFO supporting independent read/write clock domains" | Two independent, unrelated clocks (`wr_clk`, `rd_clk`), FIFO depth/width as compile-time parameters | Parameterized SV module, `DEPTH`/`WIDTH` as `parameter`, fully separate clock inputs, no shared combinational logic across the domains | Depth must be power-of-2 for Gray-code pointer math to stay simple | Assume `DEPTH` is a power of 2, parameter-checked with `$fatal`/`initial` assertion if violated |
| "using Gray-coded pointers" | Write/read pointers converted to Gray code before crossing domains, so only one bit changes per increment | Binary pointer generation + binary→Gray conversion + Gray pointer registers | None — this is a precise, standard technique | Standard `MSB`-extended Gray-code full/empty comparison (Cummings' classic method) |
| "synchronized CDC control signals" | Gray pointers synchronized via multi-flop synchronizers before being used to generate full/empty in the *other* domain | 2-flop (minimum) synchronizer chain per crossing pointer | Source doesn't state synchronizer depth | Assume 2-flop synchronizers (industry-standard minimum); document why 3 could be used for higher-MTBF designs |
| "robust reset and full/empty handling across asynchronous clock domains" | Both clock domains need independently synchronized, deasserted resets; full/empty must never glitch-assert incorrectly across a reset | Dual asynchronous-assert/synchronous-deassert reset synchronizers (one per clock domain) | Source doesn't specify async or sync reset input | Assume the external reset input is asynchronous-assert active-low (`arst_n`), synchronized internally per domain |
| "verified boundary conditions using randomized clock ratios and reset sequences" | Testbench drives `wr_clk`/`rd_clk` at randomized, unrelated periods; issues resets at random points in a transaction stream | Two independent clock-generation processes with randomized period ratios; randomized reset injection task | None | Clock ratio randomized within a bounded, realistic range (e.g. 1:1 to 1:7) rather than unbounded, to keep sim runtime sane |
| "Synthesized the FIFO in Vivado, applied timing constraints, and analyzed critical-path timing and resource utilization across multiple depth/width configurations" | Real Vivado synthesis run, real SDC-style constraints (`create_clock`, `set_false_path`/`set_max_delay -datapath_only` on CDC paths), real utilization/timing reports across ≥2 depth/width configs | Requires an actual Vivado license/install to produce genuine numbers | **Yes — no Vivado install exists in this environment** | See note below: **cannot produce real Vivado PPA numbers here.** Repo includes a ready-to-run Vivado batch-mode script + example SDC; any *actual* utilization/timing numbers quoted must come from you running it, not from me inventing figures. |

**Honesty note on synthesis**: I do not have access to Vivado in this environment. I will write a
real, runnable Vivado non-project-mode Tcl script (`synth/run_synth.tcl`) and SDC file that you can
execute yourself to get genuine numbers. Anything I say about expected critical path or LUT/FF count
will be described as *expected, not measured* until you've run it and can quote real numbers.

---

## 2. AXI4-Lite SoC Interconnect + APB Subsystem (Sep 2025 – Nov 2025)

| Claim | Technical meaning | Implementation required | Ambiguous? | Assumption made |
|---|---|---|---|---|
| "parameterized 2-master AXI4-Lite interconnect with address decoding, arbitration, and backpressure handling" | Exactly 2 manager ports, a shared address decoder, an arbiter resolving simultaneous access, VALID/READY backpressure propagated correctly end-to-end | 2 AXI4-Lite manager-facing slave ports on the interconnect, fixed or round-robin arbiter, address decode ROM/case-based, full VALID/READY chains on AW/W/B/AR/R | Source doesn't state arbitration policy | Assume **fixed-priority arbitration with round-robin as a documented, code-level alternative** — simplest reasonable choice; both are discussed, only fixed-priority is implemented as default |
| "routing read/write transactions across 3 memory-mapped slaves" | 3 distinct address regions/subordinates reachable from either master | 3 target ports out of the interconnect, address map with 3 non-overlapping windows + default/error region | Source doesn't give the address map | Assume a simple, documented 3-way equal-size address map (e.g. `0x0000_0000`, `0x0000_1000`, `0x0000_2000`, 4KB windows each) |
| "AXI4-Lite-to-APB bridge and APB peripheral register bank with configurable address mapping and error handling" | A bridge converting one AXI4-Lite slave region into an APB SETUP/ACCESS sequence, and an APB completer exposing addressable registers, with PSLVERR wired for illegal accesses | Bridge FSM (IDLE→SETUP→ACCESS), APB completer with a small register file, PSLVERR generation logic | "configurable address mapping" — configurable how? | Assume address mapping is configurable via a `parameter` base address / aperture size, not a runtime-programmable register (simplest reasonable reading; documented as such) |
| "Synthesized the interconnect in Vivado, authored SDC timing constraints, analyzed critical paths and slack, iterated RTL based on timing/area results" | Same as FIFO — real synthesis run with real SDC and real reports | Vivado non-project batch script + SDC | **Yes — same Vivado-availability gap as FIFO** | Same honesty note as above: script provided, real numbers require you to run it |

---

## Summary of hard boundaries (cannot be reconstructed as real artifacts, only as educational analogues)

1. **Vivado synthesis/timing numbers** (both FIFO and AXI/APB projects) — no Vivado license exists
   in this environment. Scripts and SDC files are provided so you can run them yourself; any real
   utilization/timing numbers must come from that run, not from an invented figure here.

Everything else above (Async FIFO + CDC, AXI4-Lite interconnect + APB bridge) is fully reconstructed
as real, simulatable SystemVerilog in this repo, and actually compiled/run with Icarus Verilog to
confirm it works — not just written and assumed correct.
