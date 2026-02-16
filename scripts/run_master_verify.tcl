# ============================================================================
# Komandara — AXI4-Lite Master Verification with Xilinx AXI VIP
# ============================================================================
# Usage: vivado -mode batch -source scripts/run_master_verify.tcl
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize "$script_dir/.."]
set build_dir  "$proj_root/build/master_verify"
set ip_rtl     "$proj_root/ip/axi4lite/rtl"
set ip_tb      "$proj_root/ip/axi4lite/rtl/tb"
set common_rtl "$proj_root/ip/common/rtl"

puts "============================================="
puts "  Komandara AXI4-Lite Master Verification"
puts "============================================="

file mkdir $build_dir
create_project -force master_verify $build_dir -part xc7a100tcsg324-1
set_property simulator_language Verilog [current_project]
set_property target_language    Verilog [current_project]

create_ip -name axi_vip -vendor xilinx.com -library ip -version 1.1 \
          -module_name axi_vip_slv
set_property -dict [list \
    CONFIG.INTERFACE_MODE {SLAVE}   \
    CONFIG.PROTOCOL       {AXI4LITE} \
    CONFIG.ADDR_WIDTH     {32}     \
    CONFIG.DATA_WIDTH     {32}     \
] [get_ips axi_vip_slv]
generate_target all [get_ips axi_vip_slv]

add_files -fileset sim_1 [list \
    "$ip_rtl/komandara_axi4lite_pkg.sv"    \
    "$common_rtl/komandara_skid_buffer.sv"  \
    "$ip_rtl/komandara_axi4lite_master.sv"  \
    "$ip_tb/tb_axi4lite_master.sv"          \
]

set_property top tb_axi4lite_master [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -mode behavioral
run all
close_sim
close_project
