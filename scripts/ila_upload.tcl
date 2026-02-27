set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set ltx_file [file join $repo_root "build" "komandara_core_k10_0.1.0" "genesys2_synth-vivado" "komandara_core_k10_0.1.0.ltx"]
set csv_file [file join $repo_root "build" "ila_capture.csv"]

open_hw_manager
connect_hw_server

set hw_device_found 0
foreach hw_target [get_hw_targets] {
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

    foreach hw_device [get_hw_devices] {
        if {[string first [get_property PART $hw_device] "xc7k325tffg900-2"] == 0} {
            current_hw_device $hw_device
            set hw_device_found 1
            break
        }
    }

    if {$hw_device_found} {
        break
    }

    close_hw_target
}

if {!$hw_device_found} {
    puts "ERROR: target/device not found"
    exit 1
}

set dev [current_hw_device]
set_property PROBES.FILE $ltx_file $dev
set_property FULL_PROBES.FILE $ltx_file $dev
refresh_hw_device $dev

set ila [lindex [get_hw_ilas] 0]
set data_obj [upload_hw_ila_data $ila]
write_hw_ila_data -force -csv_file $csv_file $data_obj
puts "INFO: capture written to $csv_file"

close_hw_target
disconnect_hw_server
close_hw_manager
exit
