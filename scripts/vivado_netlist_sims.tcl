if {$argc < 1} {
    puts "ERROR: Usage: vivado -mode batch -source vivado_netlist_sims.tcl -tclargs <project.xpr> [tb.sv]"
    exit 1
}

set xpr [file normalize [lindex $argv 0]]
set script_dir [file dirname [file normalize [info script]]]

if {$argc >= 2} {
    set tb_file [file normalize [lindex $argv 1]]
} else {
    set tb_file [file normalize [file join $script_dir ".." "rtl" "k10" "target" "k10_genesys2_gate_tb.sv"]]
}

if {![file exists $xpr]} {
    puts "ERROR: Vivado project not found: $xpr"
    exit 1
}

if {![file exists $tb_file]} {
    puts "ERROR: Testbench not found: $tb_file"
    exit 1
}

open_project $xpr
set_property source_mgmt_mode None [current_project]

set tb_top [file rootname [file tail $tb_file]]

if {[llength [get_files -quiet $tb_file]] == 0} {
    add_files -fileset sim_1 $tb_file
}

set_property top $tb_top [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "INFO: Running post-synthesis functional simulation"
launch_simulation -mode post-synthesis -type functional
run all
close_sim

puts "INFO: Running post-implementation timing simulation"
launch_simulation -mode post-implementation -type timing
run all
close_sim

close_project
exit
