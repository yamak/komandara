set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set proj_dir [file join $repo_root "build" "komandara_core_k10_0.1.0" "genesys2_synth-vivado"]
set proj_xpr [file join $proj_dir "komandara_core_k10_0.1.0.xpr"]
set ltx_file [file join $proj_dir "komandara_core_k10_0.1.0.ltx"]
set mem_init_hex [file join $repo_root "build" "k10_c_selftest.hex"]
set boot_addr_dec 2147483648

if {![file exists $proj_xpr]} {
    puts "ERROR: Missing Vivado project: $proj_xpr"
    puts "Run setup/build first: fusesoc --cores-root=. run --target=genesys2_synth --setup komandara:core:k10"
    exit 1
}

proc first_net {pattern} {
    set nets [get_nets -hier $pattern]
    if {[llength $nets] == 0} {
        return ""
    }
    foreach n $nets {
        if {([string first "u_ila_dm" $n] < 0) && ([string first "u_ila_" $n] < 0)} {
            return $n
        }
    }
    return [lindex $nets 0]
}

proc add_probe_if_found {ila_name probe_index pattern} {
    set n [first_net $pattern]
    if {$n eq ""} {
        puts "WARNING: No net matched $pattern"
        return 0
    }
    if {$probe_index > 0} {
        create_debug_port $ila_name probe
    }
    set p [format "%s/probe%d" $ila_name $probe_index]
    connect_debug_port $p [get_nets $n]
    puts "INFO: Connected $p <= $n"
    return 1
}

open_project $proj_xpr

if {![file exists $mem_init_hex]} {
    puts "ERROR: MEM_INIT hex missing: $mem_init_hex"
    puts "Build software first so k10_c_selftest.hex exists."
    exit 1
}

set_property generic [format "MEM_SIZE_KB=64 BOOT_ADDR=%d MEM_INIT=%s" $boot_addr_dec $mem_init_hex] [get_filesets sources_1]
puts "INFO: Using BOOT_ADDR=$boot_addr_dec MEM_INIT=$mem_init_hex"

reset_run synth_1
reset_run impl_1

launch_runs synth_1
wait_on_run synth_1

open_run synth_1

set clk_net [first_net "*w_clk_sys*"]
if {$clk_net eq ""} {
    puts "ERROR: Could not find synthesized clock net '*w_clk_sys*'"
    exit 1
}

set existing_cores [get_debug_cores -quiet -filter {CORE_TYPE == ila}]
if {[llength $existing_cores] > 0} {
    delete_debug_core $existing_cores
}

set ila_name u_ila_dm
create_debug_core $ila_name ila
set_property C_DATA_DEPTH 4096 [get_debug_cores $ila_name]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores $ila_name]
connect_debug_port $ila_name/clk [get_nets $clk_net]
puts "INFO: Connected $ila_name/clk <= $clk_net"

set probe_idx 0
foreach pat {
    *w_dm_ndmreset*
    *w_dm_debug_req*
    *i_debug_req0
    *w_dm_req*
    *w_dm_we*
    *r_dm_state*
    *w_dm_addr[[]0[]]
    *w_dm_addr[[]1[]]
    *w_dm_addr[[]2[]]
    *w_dm_addr[[]3[]]
    *w_dm_addr[[]4[]]
    *w_dm_addr[[]5[]]
    *w_dm_addr[[]6[]]
    *w_dm_addr[[]7[]]
    *w_dm_wdata[[]0[]]
    *w_dm_wdata[[]1[]]
    *w_dm_wdata[[]2[]]
    *w_dm_wdata[[]3[]]
    *w_dm_device_rdata[[]0[]]
    *w_dm_device_rdata[[]1[]]
    *w_dm_device_rdata[[]2[]]
    *w_dm_device_rdata[[]3[]]
    *u_dm_top/dmi_rsp_valid
    *u_dm_top/cmderror_valid
    *u_dm_top/cmderror[[]1[]]
    *u_dm_top/halted
    *u_dm_top/debug_req_o[[]0[]]
    *u_dm_top/ndmreset_o
    *u_soc/u_dm_top/i_dm_csrs/dmcontrol_q_reg[[]haltreq[]]*
    *u_soc/r_dm_addr_reg_n_0_[[]0[]]
    *u_soc/r_dm_addr_reg_n_0_[[]1[]]
    *u_soc/r_dm_addr_reg_n_0_[[]2[]]
    *u_soc/r_dm_addr_reg_n_0_[[]3[]]
    *u_soc/r_dm_addr_reg_n_0_[[]4[]]
    *u_soc/r_dm_addr_reg_n_0_[[]5[]]
    *u_soc/r_dm_addr_reg_n_0_[[]6[]]
    *u_soc/r_dm_addr_reg_n_0_[[]7[]]
    *u_soc/r_dm_addr_reg_n_0_[[]8[]]
    *u_soc/r_dm_addr_reg_n_0_[[]9[]]
    *u_soc/r_dm_addr_reg_n_0_[[]10[]]
    *u_soc/r_dm_addr_reg_n_0_[[]11[]]
} {
    set ok [add_probe_if_found $ila_name $probe_idx $pat]
    if {$ok} {
        incr probe_idx
    }
}

if {$probe_idx == 0} {
    puts "ERROR: No probes were connected. Aborting."
    exit 1
}

puts "INFO: Connected $probe_idx probes"
save_constraints -force
implement_debug_core
write_debug_probes -force $ltx_file
puts "INFO: Wrote probes file: $ltx_file"

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    launch_runs impl_1 -to_step write_bitstream
    wait_on_run impl_1
}

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: impl_1 did not complete"
    exit 1
}

set vivado_bit [get_property DIRECTORY [get_runs impl_1]]/[get_property top [current_fileset]].bit
set out_bit [file join $proj_dir "komandara_core_k10_0.1.0.bit"]
file copy -force $vivado_bit $out_bit
puts "INFO: Bitstream ready: $out_bit"
puts "INFO: Probes ready:    $ltx_file"

close_project
exit
