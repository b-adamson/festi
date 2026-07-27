# Builds a Zynq UltraScale+ PS + AXI-Lite block design wiring
# barycentric_axi into the PS's memory map, so it's addressable as
# ordinary MMIO from the ARM cores -- the AXI/embedded-Linux replacement
# for barycentric_vio_top.sv's JTAG/VIO debug path (see
# rtl/barycentric_axi.sv).
#
# Scope note: this proves out PS+PL connectivity/addressing/bitstream
# generation standalone. Actually loading this onto the K26 *while the
# existing Ubuntu image keeps running* is a separate step -- Kria SOMs
# expect new PL logic to arrive as an "accelerator platform" overlay
# (.bit + .dtbo, loaded at runtime via xmutil/fpga-manager) built against
# Xilinx's own base platform project, not a from-scratch PS configuration
# like this one. That packaging step comes after this design is validated.
#
# Run with: vivado -mode batch -source hw/build_axi_bd.tcl
# from the fpga/point_sampler directory.

set part      "xck26-sfvc784-2LV-c"
set proj_dir  "./hw/vivado_proj_axi"
set proj_name "barycentric_axi_bd"
set ip_repo   [file normalize "./hw/ip_repo"]

create_project $proj_name $proj_dir -part $part -force

# ---- Package barycentric_axi as a reusable AXI4-Lite IP ----
# The block-design address editor and connection automation only work
# against a proper IP-XACT bus interface, not loose ports, so this needs
# packaging once before it can go in a block design.
add_files -norecurse {rtl/fixed_pkg.sv rtl/barycentric.sv rtl/barycentric_axi.sv}
set_property file_type SystemVerilog [get_files fixed_pkg.sv]
set_property file_type SystemVerilog [get_files barycentric.sv]
set_property file_type SystemVerilog [get_files barycentric_axi.sv]
set_property top barycentric_axi [current_fileset]
update_compile_order -fileset sources_1

file mkdir $ip_repo
ipx::package_project -root_dir $ip_repo -vendor festi.local -library point_sampler \
    -taxonomy /UserIP -import_files -force
set core [ipx::current_core]
set_property name barycentric_axi_v1_0 $core
set_property display_name "Barycentric Point Sampler (AXI4-Lite)" $core
set_property description \
    "AXI4-Lite wrapper around festi's barycentric point-on-triangle core" $core

# Infer interfaces from port names rather than trusting silent
# auto-detection -- explicit, and easier to debug if it doesn't match.
ipx::infer_bus_interface clk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface rst_n xilinx.com:signal:reset_rtl:1.0 $core
ipx::infer_bus_interface {
    s_axi_awaddr s_axi_awvalid s_axi_awready
    s_axi_wdata s_axi_wstrb s_axi_wvalid s_axi_wready
    s_axi_bresp s_axi_bvalid s_axi_bready
    s_axi_araddr s_axi_arvalid s_axi_arready
    s_axi_rdata s_axi_rresp s_axi_rvalid s_axi_rready
} xilinx.com:interface:aximm_rtl:1.0 $core

puts "== Bus interfaces after inference =="
foreach bi [ipx::get_bus_interfaces -of_objects $core] {
    puts "  [get_property NAME $bi] : [get_property ABSTRACTION_TYPE_NAME $bi] (mode=[get_property INTERFACE_MODE $bi])"
}

# Find the inferred AXI4-Lite slave interface by abstraction type rather
# than assuming Vivado's auto-generated name for it.
set axi_if [lindex [ipx::get_bus_interfaces -of_objects $core \
    -filter {ABSTRACTION_TYPE_NAME == aximm_rtl}] 0]
if {$axi_if eq ""} {
    error "Could not find an inferred AXI4-Lite bus interface -- check port names in barycentric_axi.sv"
}
set axi_if_name [get_property NAME $axi_if]
puts "Using AXI interface: $axi_if_name"

set_property interface_mode slave $axi_if
set_property value ACTIVE_LOW [ipx::get_bus_parameters POLARITY \
    -of_objects [ipx::get_bus_interfaces rst_n -of_objects $core]]
set_property value $axi_if_name [ipx::get_bus_parameters ASSOCIATED_BUSIF \
    -of_objects [ipx::get_bus_interfaces clk -of_objects $core]]
set_property value rst_n [ipx::get_bus_parameters ASSOCIATED_RESET \
    -of_objects [ipx::get_bus_interfaces clk -of_objects $core]]

ipx::add_memory_map $axi_if_name $core
ipx::add_address_block reg0 [ipx::get_memory_maps $axi_if_name -of_objects $core]
set_property range 64 [ipx::get_address_blocks reg0 \
    -of_objects [ipx::get_memory_maps $axi_if_name -of_objects $core]]
set_property slave_memory_map_ref $axi_if_name $axi_if

set_property core_revision 2 $core
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

# The loose copies are now redundant with the packaged IP's own bundled
# sources -- remove them so synthesis doesn't see each module twice.
remove_files {fixed_pkg.sv barycentric.sv barycentric_axi.sv}

set_property ip_repo_paths $ip_repo [current_project]
update_ip_catalog

# ---- Block design: Zynq PS + AXI interconnect + our peripheral ----
# IP core version numbers shift between Vivado releases, so look up
# what's actually in this install's catalog rather than hardcoding one.
proc find_ipdef {name} {
    set defs [get_ipdefs -filter "NAME == \"$name\""]
    if {[llength $defs] == 0} {
        error "No IP definition named '$name' in the IP catalog -- check it's available under your Vivado license/edition."
    }
    if {[llength $defs] > 1} {
        puts "Multiple versions of $name found: $defs -- using [lindex $defs 0]"
    }
    return [lindex $defs 0]
}

set zynq_vlnv [find_ipdef zynq_ultra_ps_e]
puts "Using Zynq PS IP: $zynq_vlnv"

create_bd_design "design_1"

create_bd_cell -type ip -vlnv $zynq_vlnv zynq_ps
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "0"} [get_bd_cells zynq_ps]

# One general-purpose AXI master from the PS so the ARM cores can issue
# MMIO reads/writes into the PL, and one PL fabric clock to run our
# peripheral and the interconnect from.
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
] [get_bd_cells zynq_ps]

create_bd_cell -type ip -vlnv festi.local:point_sampler:barycentric_axi_v1_0:1.0 barycentric_axi_0

set smc_vlnv [find_ipdef smartconnect]
set rst_vlnv [find_ipdef proc_sys_reset]
puts "Using SmartConnect IP: $smc_vlnv"
puts "Using proc_sys_reset IP: $rst_vlnv"

create_bd_cell -type ip -vlnv $smc_vlnv axi_smc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_smc]

create_bd_cell -type ip -vlnv $rst_vlnv rst_ps

connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins rst_ps/slowest_sync_clk]
connect_bd_net [get_bd_pins zynq_ps/pl_resetn0] [get_bd_pins rst_ps/ext_reset_in]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins axi_smc/aclk]
connect_bd_net [get_bd_pins rst_ps/peripheral_aresetn] [get_bd_pins axi_smc/aresetn]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins barycentric_axi_0/clk]
connect_bd_net [get_bd_pins rst_ps/peripheral_aresetn] [get_bd_pins barycentric_axi_0/rst_n]
connect_bd_net [get_bd_pins zynq_ps/pl_clk0] [get_bd_pins zynq_ps/maxihpm0_fpd_aclk]

connect_bd_intf_net [get_bd_intf_pins zynq_ps/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins barycentric_axi_0/$axi_if_name]

assign_bd_address
puts "== Assigned address segments =="
foreach seg [get_bd_addr_segs -of_objects [get_bd_cells barycentric_axi_0]] {
    puts "  $seg : offset [get_property OFFSET $seg] range [get_property RANGE $seg]"
}

validate_bd_design
save_bd_design

make_wrapper -files [get_files design_1.bd] -top
add_files -norecurse [glob $proj_dir/$proj_name.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v]
update_compile_order -fileset sources_1
set_property top design_1_wrapper [current_fileset]

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

puts "BD_BUILD_OK"
puts "Bitstream: [glob $proj_dir/$proj_name.runs/impl_1/*.bit]"
