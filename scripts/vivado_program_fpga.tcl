set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {$argc >= 1} {
    set bit_file [file normalize [lindex $argv 0]]
} else {
    set bit_file [file join $repo_root "build" "komandara_core_k10_0.1.0" "genesys2_synth-vivado" "komandara_core_k10_0.1.0.bit"]
}

if {![file exists $bit_file]} {
    puts "ERROR: Bitstream not found: $bit_file"
    exit 1
}

open_hw_manager
connect_hw_server

set hw_targets [get_hw_targets *]
if {[llength $hw_targets] == 0} {
    puts "ERROR: No hardware target found. Check JTAG cable/board power."
    close_hw_manager
    exit 1
}

set hw_target [lindex $hw_targets 0]
open_hw_target $hw_target

set hw_devices [get_hw_devices xc7k325t*]
if {[llength $hw_devices] == 0} {
    puts "ERROR: No xc7k325t device found on hw target."
    close_hw_manager
    exit 1
}

set hw_device [lindex $hw_devices 0]
current_hw_device $hw_device
refresh_hw_device $hw_device

set_property PROGRAM.FILE $bit_file $hw_device
program_hw_devices $hw_device
refresh_hw_device $hw_device

puts "INFO: Programmed $hw_device with $bit_file"
close_hw_manager
