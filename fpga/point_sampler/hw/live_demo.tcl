# Reprograms the already-built bitstream onto the Kria K26 (JTAG config is
# volatile, so a fresh unplug/replug needs reprogramming) and then drives a
# handful of varied test cases through the live barycentric core, printing
# a PASS/FAIL table computed against the same formula as the Python golden
# model and the SV testbench.

set proj_dir "./hw/vivado_proj"
set proj_name "barycentric_vio"

set bit_file [glob $proj_dir/$proj_name.runs/impl_1/*.bit]
set ltx_file [glob $proj_dir/$proj_name.runs/impl_1/barycentric_vio_top.ltx]

open_hw_manager
connect_hw_server
set hw_target [lindex [get_hw_targets] 0]
open_hw_target $hw_target
set dev [lindex [get_hw_devices xck26_0] 0]
current_hw_device $dev

puts "== Programming $bit_file =="
set_property PROGRAM.FILE $bit_file $dev
set_property PROBES.FILE $ltx_file $dev
program_hw_devices $dev
refresh_hw_device $dev

set vio [lindex [get_hw_vios -of_objects $dev] 0]
puts "VIO_CORE: $vio\n"

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
proc to_fixed {f} {
    return [expr {int(round($f * 65536))}]
}

# {label v0x v0y v0z v1x v1y v1z v2x v2y v2z u v}
set cases {
    {"centroid-ish sample"                    0  0 0   10  0 0    0 10 0    0.25      0.25}
    {"generic non-collinear triangle"        -5 10 2   20 -3 7    0  0 15   0.6       0.1}
    {"exact vertex (u=1,v=0) -> v1"            0  0 0    1  0 0   0  1 0    1.0       0.0}
    {"triangle centroid (u=v=1/3)"             0  0 0    3  0 0   0  3 0    0.3333333 0.3333333}
    {"extrapolated point outside triangle"     0  0 0   10  0 0   0 10 0    1.2      -0.3}
}

puts [format "%-38s %-24s %-24s %-6s" "case" "expected (x,y,z)" "hardware (x,y,z)" "result"]
puts [string repeat "-" 100]

foreach c $cases {
    lassign $c label v0x v0y v0z v1x v1y v1z v2x v2y v2z u v

    set w [expr {1.0 - $u - $v}]
    set ex [expr {$w*$v0x + $u*$v1x + $v*$v2x}]
    set ey [expr {$w*$v0y + $u*$v1y + $v*$v2y}]
    set ez [expr {$w*$v0z + $u*$v1z + $v*$v2z}]

    foreach {name val} [list v0x $v0x v0y $v0y v0z $v0z \
                              v1x $v1x v1y $v1y v1z $v1z \
                              v2x $v2x v2y $v2y v2z $v2z \
                              u $u v $v] {
        set p [get_hw_probes $name -of_objects $vio]
        set_property OUTPUT_VALUE [to_hex32 [to_fixed $val]] $p
    }
    commit_hw_vio [get_hw_probes {v0x v0y v0z v1x v1y v1z v2x v2y v2z u v} -of_objects $vio]

    after 100
    refresh_hw_vio $vio

    set hx [expr {[from_hex32 [get_property INPUT_VALUE [get_hw_probes dut_outx -of_objects $vio]]] / 65536.0}]
    set hy [expr {[from_hex32 [get_property INPUT_VALUE [get_hw_probes dut_outy -of_objects $vio]]] / 65536.0}]
    set hz [expr {[from_hex32 [get_property INPUT_VALUE [get_hw_probes dut_outz -of_objects $vio]]] / 65536.0}]

    set err [expr {abs($hx-$ex) + abs($hy-$ey) + abs($hz-$ez)}]
    set result [expr {$err < 0.01 ? "PASS" : "FAIL"}]

    set exp_str [format "(%.3f, %.3f, %.3f)" $ex $ey $ez]
    set hw_str  [format "(%.3f, %.3f, %.3f)" $hx $hy $hz]
    puts [format "%-38s %-24s %-24s %-6s" $label $exp_str $hw_str $result]
}

close_hw_manager
