set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {$argc >= 1} {
    set bit_file [file normalize [lindex $argv 0]]
} else {
    set bit_file [file join $repo_root "build" "komandara_core_k10_0.1.0" "genesys2_synth-vivado" "komandara_core_k10_0.1.0.bit"]
}

if {$argc >= 2} {
    set probes_file [file normalize [lindex $argv 1]]
} else {
    set probes_file [file join $repo_root "build" "komandara_core_k10_0.1.0" "genesys2_synth-vivado" "komandara_core_k10_0.1.0.ltx"]
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

set hw_device_found 0
foreach hw_target $hw_targets {
    current_hw_target $hw_target

    set hw_target_opened 0
    for {set open_hw_target_try 1} {$open_hw_target_try <= 3} {incr open_hw_target_try} {
        if {[catch {open_hw_target} res_open_hw_target] == 0} {
            set hw_target_opened 1
            break
        }
    }
    if {$hw_target_opened == 0} {
        continue
    }

    set hw_devices [get_hw_devices xc7k325t*]
    if {[llength $hw_devices] > 0} {
        set hw_device [lindex $hw_devices 0]
        set hw_device_found 1
        break
    }

    close_hw_target
}

if {!$hw_device_found} {
    puts "ERROR: No xc7k325t device found on any hw target."
    close_hw_manager
    exit 1
}

current_hw_device $hw_device
refresh_hw_device $hw_device

set_property PROGRAM.FILE $bit_file $hw_device
if {[file exists $probes_file]} {
    set_property PROBES.FILE $probes_file $hw_device
    set_property FULL_PROBES.FILE $probes_file $hw_device
    puts "INFO: Loaded probes file $probes_file"
} else {
    puts "WARNING: Probes file not found: $probes_file"
}
program_hw_devices $hw_device
refresh_hw_device $hw_device

puts "INFO: Programmed $hw_device with $bit_file"
close_hw_manager
