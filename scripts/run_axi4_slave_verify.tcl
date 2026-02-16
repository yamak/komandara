# ============================================================================
# Komandara — AXI4 Full Slave Verification
# ============================================================================
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize "$script_dir/.."]
set build_dir  "$proj_root/build/axi4_slave_verify"
set axi4_rtl   "$proj_root/ip/axi4/rtl"
set axi4_tb    "$proj_root/ip/axi4/rtl/tb"
set common_rtl "$proj_root/ip/common/rtl"

file mkdir $build_dir
create_project -force axi4_slave_verify $build_dir -part xc7a100tcsg324-1
set_property simulator_language Verilog [current_project]

# AXI VIP Master (AXI4 Full)
create_ip -name axi_vip -vendor xilinx.com -library ip -version 1.1 \
          -module_name axi_vip_mst
set_property -dict [list \
    CONFIG.INTERFACE_MODE {MASTER} \
    CONFIG.PROTOCOL       {AXI4}  \
    CONFIG.ADDR_WIDTH     {32}    \
    CONFIG.DATA_WIDTH     {32}    \
    CONFIG.ID_WIDTH       {4}     \
    CONFIG.HAS_BURST      {1}     \
    CONFIG.HAS_LOCK       {1}     \
    CONFIG.HAS_CACHE      {1}     \
    CONFIG.HAS_REGION     {1}     \
    CONFIG.HAS_QOS        {1}     \
    CONFIG.HAS_PROT       {1}     \
    CONFIG.HAS_WSTRB      {1}     \
    CONFIG.HAS_BRESP      {1}     \
    CONFIG.HAS_RRESP      {1}     \
] [get_ips axi_vip_mst]
generate_target all [get_ips axi_vip_mst]

add_files -fileset sim_1 [list \
    "$axi4_rtl/komandara_axi4_pkg.sv"    \
    "$common_rtl/komandara_skid_buffer.sv" \
    "$axi4_rtl/komandara_axi4_slave.sv"   \
    "$axi4_tb/tb_axi4_slave.sv"           \
]
set_property top tb_axi4_slave [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "Launching AXI4 Slave simulation..."
launch_simulation -mode behavioral
run all
close_sim
close_project
