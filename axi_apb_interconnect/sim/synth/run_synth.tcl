# run_synth.tcl -- Vivado non-project-mode synthesis flow for axi_lite_interconnect (+ its
# downstream slaves + the APB bridge, all synthesized together as one top for a realistic PPA view).
#
# Usage: vivado -mode batch -source run_synth.tcl -tclargs <PART>
# Example: vivado -mode batch -source run_synth.tcl -tclargs xc7a100tcsg324-1

if {[llength $argv] < 1} {
    puts "Usage: vivado -mode batch -source run_synth.tcl -tclargs <PART>"
    exit 1
}
set PART [lindex $argv 0]

set RTL_DIR [file join [file dirname [info script]] .. .. rtl]
set OUT_DIR [file join [file dirname [info script]] out]
file mkdir $OUT_DIR

read_verilog -sv [list \
    "$RTL_DIR/axi_lite_pkg.sv" \
    "$RTL_DIR/axi_lite_regfile.sv" \
    "$RTL_DIR/apb_regbank.sv" \
    "$RTL_DIR/axi_lite_to_apb_bridge.sv" \
    "$RTL_DIR/axi_lite_interconnect.sv" \
]

# This project has no top-level module that instantiates the interconnect + both regfiles + the
# bridge + apb_regbank together outside the testbench (tb/tb_axi_lite_apb_interconnect.sv does,
# but that's simulation-only, not synthesizable top). Synthesize axi_lite_interconnect on its own
# out-of-context; synthesize the other 3 modules separately if you want their individual PPA too.
synth_design -top axi_lite_interconnect -part $PART -mode out_of_context

read_xdc [file join [file dirname [info script]] axi_lite_interconnect.sdc]

report_utilization -file "$OUT_DIR/utilization.rpt"
report_timing_summary -file "$OUT_DIR/timing_summary.rpt"
report_timing -delay_type max -max_paths 10 -file "$OUT_DIR/timing_max_paths.rpt"
write_checkpoint -force "$OUT_DIR/post_synth.dcp"

puts "Synthesis complete. Reports in $OUT_DIR."
