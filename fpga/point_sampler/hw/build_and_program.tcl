# Builds barycentric_vio_top for the connected Kria K26 SOM, generates a
# bitstream, and programs it over JTAG. Run with:
#   vivado -mode batch -source hw/build_and_program.tcl
# from the fpga/point_sampler directory.

set part "xck26-sfvc784-2LV-c"
set proj_dir "./hw/vivado_proj"
set proj_name "barycentric_vio"

create_project $proj_name $proj_dir -part $part -force

add_files -norecurse {rtl/fixed_pkg.sv rtl/barycentric.sv hw/barycentric_vio_top.sv}
set_property file_type SystemVerilog [get_files rtl/fixed_pkg.sv]
set_property file_type SystemVerilog [get_files rtl/barycentric.sv]
set_property file_type SystemVerilog [get_files hw/barycentric_vio_top.sv]
set_property top barycentric_vio_top [current_fileset]
update_compile_order -fileset sources_1

# --- VIO IP: 4 input probes (valid_out + 3x32b result), 11 output probes
#     (9x32b vertex coords + u + v) ---
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_0

set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN   {4}  \
    CONFIG.C_NUM_PROBE_OUT  {11} \
    CONFIG.C_PROBE_IN0_WIDTH {1} \
    CONFIG.C_PROBE_IN1_WIDTH {32} \
    CONFIG.C_PROBE_IN2_WIDTH {32} \
    CONFIG.C_PROBE_IN3_WIDTH {32} \
    CONFIG.C_PROBE_OUT0_WIDTH  {32} \
    CONFIG.C_PROBE_OUT1_WIDTH  {32} \
    CONFIG.C_PROBE_OUT2_WIDTH  {32} \
    CONFIG.C_PROBE_OUT3_WIDTH  {32} \
    CONFIG.C_PROBE_OUT4_WIDTH  {32} \
    CONFIG.C_PROBE_OUT5_WIDTH  {32} \
    CONFIG.C_PROBE_OUT6_WIDTH  {32} \
    CONFIG.C_PROBE_OUT7_WIDTH  {32} \
    CONFIG.C_PROBE_OUT8_WIDTH  {32} \
    CONFIG.C_PROBE_OUT9_WIDTH  {32} \
    CONFIG.C_PROBE_OUT10_WIDTH {32} \
] [get_ips vio_0]

generate_target all [get_files $proj_dir/$proj_name.srcs/sources_1/ip/vio_0/vio_0.xci]

# --- synth + impl + bitstream ---
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "synth_1 did not complete successfully"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "impl_1 did not complete successfully"
}

puts "== Utilization =="
open_run impl_1
report_utilization -file $proj_dir/utilization.rpt
puts [exec cat $proj_dir/utilization.rpt]

puts "== Timing summary =="
report_timing_summary -file $proj_dir/timing_summary.rpt -max_paths 3
puts [exec cat $proj_dir/timing_summary.rpt]

set bit_file [glob $proj_dir/$proj_name.runs/impl_1/*.bit]
set ltx_file [glob $proj_dir/$proj_name.runs/impl_1/barycentric_vio_top.ltx]
puts "Bitstream: $bit_file"
puts "Probes file: $ltx_file"

# --- program over JTAG ---
open_hw_manager
connect_hw_server
set hw_target [lindex [get_hw_targets] 0]
open_hw_target $hw_target
set hw_dev [lindex [get_hw_devices xck26_0] 0]
current_hw_device $hw_dev
refresh_hw_device -update_hw_probes false $hw_dev

set_property PROGRAM.FILE $bit_file $hw_dev
set_property PROBES.FILE $ltx_file $hw_dev
program_hw_devices $hw_dev
refresh_hw_device $hw_dev

puts "PROGRAMMED_OK"
close_hw_manager
