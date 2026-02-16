# ============================================================================
# Komandara — AXI4-Lite Slave Verification with Xilinx AXI VIP
# ============================================================================
# Usage: vivado -mode batch -source scripts/run_slave_verify.tcl
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize "$script_dir/.."]
set build_dir  "$proj_root/build/slave_verify"
set ip_rtl     "$proj_root/ip/axi4lite/rtl"
set ip_tb      "$proj_root/ip/axi4lite/rtl/tb"
set common_rtl "$proj_root/ip/common/rtl"

puts "============================================="
puts "  Komandara AXI4-Lite Slave Verification"
puts "============================================="

file mkdir $build_dir
create_project -force slave_verify $build_dir -part xc7a100tcsg324-1
set_property simulator_language Verilog [current_project]
set_property target_language    Verilog [current_project]

create_ip -name axi_vip -vendor xilinx.com -library ip -version 1.1 \
          -module_name axi_vip_mst
set_property -dict [list \
    CONFIG.INTERFACE_MODE {MASTER}  \
    CONFIG.PROTOCOL       {AXI4LITE} \
    CONFIG.ADDR_WIDTH     {32}     \
    CONFIG.DATA_WIDTH     {32}     \
] [get_ips axi_vip_mst]
generate_target all [get_ips axi_vip_mst]

add_files -fileset sim_1 [list \
    "$ip_rtl/komandara_axi4lite_pkg.sv"   \
    "$common_rtl/komandara_skid_buffer.sv" \
    "$ip_rtl/komandara_axi4lite_slave.sv"  \
    "$ip_tb/tb_axi4lite_slave.sv"          \
]

set_property top tb_axi4lite_slave [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -mode behavioral
run all
close_sim
close_project
