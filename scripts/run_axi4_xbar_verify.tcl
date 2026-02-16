# ============================================================================
# Komandara — AXI4 Full Crossbar Verification (2M × 2S)
# ============================================================================
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize "$script_dir/.."]
set build_dir  "$proj_root/build/axi4_xbar_verify"
set axi4_rtl   "$proj_root/ip/axi4/rtl"
set axi4_tb    "$proj_root/ip/axi4/rtl/tb"
set common_rtl "$proj_root/ip/common/rtl"

file mkdir $build_dir
create_project -force axi4_xbar_verify $build_dir -part xc7a100tcsg324-1
set_property simulator_language Verilog [current_project]

# Two AXI VIP Masters (AXI4 Full)
foreach idx {0 1} {
    set ip_name "axi_vip_mst${idx}"
    create_ip -name axi_vip -vendor xilinx.com -library ip -version 1.1 \
              -module_name $ip_name
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
    ] [get_ips $ip_name]
    generate_target all [get_ips $ip_name]
}

add_files -fileset sim_1 [list \
    "$axi4_rtl/komandara_axi4_pkg.sv"      \
    "$common_rtl/komandara_skid_buffer.sv"   \
    "$common_rtl/komandara_arbiter.sv"       \
    "$axi4_rtl/komandara_axi4_slave.sv"     \
    "$axi4_rtl/komandara_axi4_xbar.sv"      \
    "$axi4_tb/tb_axi4_xbar.sv"             \
]
set_property top tb_axi4_xbar [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "Launching AXI4 Crossbar simulation..."
launch_simulation -mode behavioral
run all
close_sim
close_project
