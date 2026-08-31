# async_fifo.sdc -- example timing constraints for the async FIFO.
#
# HONESTY NOTE: written to be genuinely applicable, not run against real silicon/FPGA timing here
# (see run_synth.tcl's header). The two `create_clock` + CDC exception lines are the actual
# most conceptually important content; the input/output delay numbers are placeholder-reasonable, not
# derived from any real interface spec (the source doesn't specify one).

# ---- Clock definitions: two genuinely independent, unrelated clocks ----
create_clock -name wr_clk -period 10.000 [get_ports wr_clk]
create_clock -name rd_clk -period 7.000  [get_ports rd_clk]

# ---- Declare the two clocks asynchronous to each other ----
# This is the single most important line in this file for an async FIFO. Without it, the timing
# tool will try to analyze setup/hold timing BETWEEN wr_clk and rd_clk domains as if they had some
# fixed phase relationship -- which is meaningless for genuinely asynchronous clocks, and would
# either report false violations or, worse, false passes that don't mean anything.
set_clock_groups -asynchronous -group [get_clocks wr_clk] -group [get_clocks rd_clk]

# ---- CDC synchronizer paths: false-path the FIRST synchronizer flop's input ----
# Only the synchronizer's own first stage needs this treatment -- everything downstream of it is
# safely single-clock-domain again. `set_clock_groups -asynchronous` above already covers this for
# Vivado (it implies false-path treatment between the two clock groups), but a real project would
# often ALSO want a per-path `set_max_delay -datapath_only` on just the two synchronizer input nets
# below, so a stray change elsewhere doesn't accidentally regroup the clocks and silently reintroduce
# a timed cross-domain path:
set_max_delay -datapath_only -from [get_pins u_sync_wptr_to_rd/meta_stage_reg*/D] 10.0
set_max_delay -datapath_only -from [get_pins u_sync_rptr_to_wr/meta_stage_reg*/D] 10.0

# ---- Reset synchronizer paths: same treatment, reset is also asynchronous by design ----
set_false_path -from [get_ports wr_arst_n]
set_false_path -from [get_ports rd_arst_n]

# ---- I/O delays (placeholder-reasonable; adjust to a real board/interface spec if this ever
#      needs to be more than a synthesis-and-look-at-the-report exercise) ----
set_input_delay  -clock wr_clk 2.0 [get_ports {wr_en wdata[*]}]
set_output_delay -clock wr_clk 2.0 [get_ports {full}]
set_input_delay  -clock rd_clk 2.0 [get_ports {rd_en}]
set_output_delay -clock rd_clk 2.0 [get_ports {rdata[*] empty}]
