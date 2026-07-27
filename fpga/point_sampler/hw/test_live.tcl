# Attaches probes to the already-programmed board, drives one known
# triangle + (u,v) through the live barycentric core via VIO, and prints
# the result read back over JTAG.
#
# v0=(0,0,0) v1=(10,0,0) v2=(0,10,0) u=0.25 v=0.25
# expected = 0.5*v0 + 0.25*v1 + 0.25*v2 = (2.5, 2.5, 0)

open_hw_manager
connect_hw_server
set hw_target [lindex [get_hw_targets] 0]
open_hw_target $hw_target
set dev [lindex [get_hw_devices xck26_0] 0]
current_hw_device $dev

set_property PROBES.FILE {./hw/vivado_proj/barycentric_vio.runs/impl_1/barycentric_vio_top.ltx} $dev
refresh_hw_device $dev

set vio [lindex [get_hw_vios -of_objects $dev] 0]
puts "VIO_CORE: $vio"

proc to_hex32 {val} {
    if {$val < 0} { set val [expr {$val + (1 << 32)}] }
    return [format %08X $val]
}
proc from_hex32 {hexstr} {
    set val 0
    scan $hexstr "%x" val
    if {$val >= (1 << 31)} { set val [expr {$val - (1 << 32)}] }
    return $val
}

array set vals {
    v0x 0      v0y 0      v0z 0
    v1x 655360 v1y 0      v1z 0
    v2x 0      v2y 655360 v2z 0
    u   16384  v   16384
}

foreach {name val} [array get vals] {
    set p [get_hw_probes $name -of_objects $vio]
    set_property OUTPUT_VALUE [to_hex32 $val] $p
}
commit_hw_vio [get_hw_probes {v0x v0y v0z v1x v1y v1z v2x v2y v2z u v} -of_objects $vio]

after 200
refresh_hw_vio $vio

set valid [get_property INPUT_VALUE [get_hw_probes dut_valid_out -of_objects $vio]]
set outx  [from_hex32 [get_property INPUT_VALUE [get_hw_probes dut_outx -of_objects $vio]]]
set outy  [from_hex32 [get_property INPUT_VALUE [get_hw_probes dut_outy -of_objects $vio]]]
set outz  [from_hex32 [get_property INPUT_VALUE [get_hw_probes dut_outz -of_objects $vio]]]

set outx_f [expr {$outx / 65536.0}]
set outy_f [expr {$outy / 65536.0}]
set outz_f [expr {$outz / 65536.0}]

puts "LIVE_RESULT valid=$valid outx=$outx_f outy=$outy_f outz=$outz_f"
puts "EXPECTED    outx=2.5 outy=2.5 outz=0.0"

close_hw_manager
