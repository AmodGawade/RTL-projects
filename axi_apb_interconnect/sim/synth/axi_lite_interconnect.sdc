# axi_lite_interconnect.sdc -- example timing constraints.
# HONESTY NOTE: written to be genuinely applicable, not run against real silicon/FPGA timing here.

create_clock -name clk -period 5.000 [get_ports clk]

set_false_path -from [get_ports aresetn]

# Single clock domain, single reset -- no CDC exceptions needed here (unlike the async FIFO's SDC).
# The interesting timing content in THIS design is the arbitration/address-decode combinational
# path from AWVALID/AWADDR through to the granted slave's AWVALID/AWADDR -- worth explicitly
# calling out even though it doesn't need a special *exception*, just attention in
# report_timing:
#   report_timing -from [get_ports {m0_awvalid m1_awvalid}] -to [get_ports {s0_awvalid s1_awvalid s2_awvalid}]

set_input_delay  -clock clk 1.0 [get_ports {m0_awvalid m0_awaddr m0_wvalid m0_wdata m0_wstrb m0_bready m0_arvalid m0_araddr m0_rready}]
set_input_delay  -clock clk 1.0 [get_ports {m1_awvalid m1_awaddr m1_wvalid m1_wdata m1_wstrb m1_bready m1_arvalid m1_araddr m1_rready}]
set_output_delay -clock clk 1.0 [get_ports {m0_awready m0_wready m0_bvalid m0_bresp m0_arready m0_rvalid m0_rdata m0_rresp}]
set_output_delay -clock clk 1.0 [get_ports {m1_awready m1_wready m1_bvalid m1_bresp m1_arready m1_rvalid m1_rdata m1_rresp}]
