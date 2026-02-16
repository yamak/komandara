# ============================================================================
# Komandara — AXI4-Lite Crossbar Verification (2M × 2S)
# ============================================================================
# Usage: vivado -mode batch -source scripts/run_xbar_verify.tcl
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize "$script_dir/.."]
set build_dir  "$proj_root/build/xbar_verify"
set ip_rtl     "$proj_root/ip/axi4lite/rtl"
set ip_tb      "$proj_root/ip/axi4lite/rtl/tb"
set common_rtl "$proj_root/ip/common/rtl"

puts "============================================="
puts "  Komandara AXI4-Lite Crossbar Verification"
puts "============================================="

file mkdir $build_dir
create_project -force xbar_verify $build_dir -part xc7a100tcsg324-1
set_property simulator_language Verilog [current_project]
set_property target_language    Verilog [current_project]

# ---- Create two AXI VIP IPs in MASTER mode ----
foreach idx {0 1} {
    set ip_name "axi_vip_mst${idx}"
    create_ip -name axi_vip -vendor xilinx.com -library ip -version 1.1 \
              -module_name $ip_name
    set_property -dict [list \
        CONFIG.INTERFACE_MODE {MASTER}   \
        CONFIG.PROTOCOL       {AXI4LITE} \
        CONFIG.ADDR_WIDTH     {32}       \
        CONFIG.DATA_WIDTH     {32}       \
    ] [get_ips $ip_name]
    generate_target all [get_ips $ip_name]
}

# ---- Add RTL and TB sources ----
add_files -fileset sim_1 [list \
    "$ip_rtl/komandara_axi4lite_pkg.sv"   \
    "$common_rtl/komandara_skid_buffer.sv" \
    "$common_rtl/komandara_arbiter.sv"     \
    "$ip_rtl/komandara_axi4lite_slave.sv"  \
    "$ip_rtl/komandara_axi4lite_xbar.sv"   \
    "$ip_tb/tb_axi4lite_xbar.sv"           \
]

set_property top tb_axi4lite_xbar [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "Launching simulation..."
launch_simulation -mode behavioral
run all

puts "============================================="
puts "  Simulation complete."
puts "============================================="

close_sim
close_project
