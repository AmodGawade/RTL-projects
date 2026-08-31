# run_synth.tcl -- Vivado non-project-mode synthesis flow for async_fifo.
#
# HONESTY NOTE: this script was written to be genuinely runnable, but has NOT been executed --
# there is no Vivado install in the environment this repo was built in (confirmed: no `vivado` on
# PATH, no licensed install found). Any area/timing numbers you get from actually running this are
# real measured data; nothing here should be quoted as a result until you've run it yourself.
#
# Usage (from a machine with Vivado on PATH):
#   vivado -mode batch -source run_synth.tcl -tclargs <DEPTH> <DATA_WIDTH> <TARGET_PART>
# Example:
#   vivado -mode batch -source run_synth.tcl -tclargs 16 8 xc7a100tcsg324-1

if {[llength $argv] < 3} {
    puts "Usage: vivado -mode batch -source run_synth.tcl -tclargs <DEPTH> <DATA_WIDTH> <PART>"
    exit 1
}
set DEPTH      [lindex $argv 0]
set DATA_WIDTH [lindex $argv 1]
set PART       [lindex $argv 2]

set RTL_DIR [file join [file dirname [info script]] .. .. rtl]
set OUT_DIR [file join [file dirname [info script]] out_d${DEPTH}_w${DATA_WIDTH}]
file mkdir $OUT_DIR

read_verilog -sv [list \
    "$RTL_DIR/rst_sync.sv" \
    "$RTL_DIR/sync_r2r.sv" \
    "$RTL_DIR/fifo_mem.sv" \
    "$RTL_DIR/wptr_full.sv" \
    "$RTL_DIR/rptr_empty.sv" \
    "$RTL_DIR/async_fifo.sv" \
]
# fifo_sva_checker.sv is intentionally NOT read here: it's guarded by `ifndef SYNTHESIS` in
# async_fifo.sv, but Vivado's out-of-context synth doesn't predefine SYNTHESIS by default -- define
# it explicitly so the checker instantiation is skipped even if this flag were left unset.
set_property verilog_define {SYNTHESIS=1} [current_fileset]

synth_design -top async_fifo -part $PART \
    -generic DATA_WIDTH=$DATA_WIDTH -generic DEPTH=$DEPTH \
    -mode out_of_context

read_xdc [file join [file dirname [info script]] async_fifo.sdc]

report_utilization -file "$OUT_DIR/utilization.rpt"
report_timing_summary -file "$OUT_DIR/timing_summary.rpt"
report_timing -delay_type max -max_paths 10 -file "$OUT_DIR/timing_max_paths.rpt"
write_checkpoint -force "$OUT_DIR/post_synth.dcp"

puts "Synthesis complete. Reports in $OUT_DIR."
puts "Re-run with different -tclargs DEPTH/DATA_WIDTH values to sweep configurations, per the"
puts "source's 'multiple depth/width configurations' claim (docs/claims.md #1)."
