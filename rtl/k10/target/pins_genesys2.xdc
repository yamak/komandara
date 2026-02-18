set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

create_clock -name io_clk -period 5.000 [get_ports IO_CLK_P]

set_property -dict {PACKAGE_PIN AD11 IOSTANDARD LVDS} [get_ports IO_CLK_N]
set_property -dict {PACKAGE_PIN AD12 IOSTANDARD LVDS} [get_ports IO_CLK_P]

# BTNC
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS12} [get_ports IO_RST]

# Leds
set_property -dict {PACKAGE_PIN T30  IOSTANDARD LVCMOS33} [get_ports {gp_o[0]}]
set_property -dict {PACKAGE_PIN AC26 IOSTANDARD LVCMOS33} [get_ports {gp_o[1]}]
set_property -dict {PACKAGE_PIN AJ27 IOSTANDARD LVCMOS33} [get_ports {gp_o[2]}]
set_property -dict {PACKAGE_PIN U29  IOSTANDARD LVCMOS33} [get_ports {gp_o[3]}]
set_property -dict {PACKAGE_PIN V20  IOSTANDARD LVCMOS33} [get_ports {gp_o[4]}]
set_property -dict {PACKAGE_PIN V26  IOSTANDARD LVCMOS33} [get_ports {gp_o[5]}]
set_property -dict {PACKAGE_PIN W24  IOSTANDARD LVCMOS33} [get_ports {gp_o[6]}]
set_property -dict {PACKAGE_PIN W23  IOSTANDARD LVCMOS33} [get_ports {gp_o[7]}]

# Switches
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS12} [get_ports {gp_i[0]}]
set_property -dict {PACKAGE_PIN G25 IOSTANDARD LVCMOS12} [get_ports {gp_i[1]}]
set_property -dict {PACKAGE_PIN H24 IOSTANDARD LVCMOS12} [get_ports {gp_i[2]}]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS12} [get_ports {gp_i[3]}]
set_property -dict {PACKAGE_PIN N19 IOSTANDARD LVCMOS12} [get_ports {gp_i[4]}]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS12} [get_ports {gp_i[5]}]
set_property -dict {PACKAGE_PIN P26 IOSTANDARD LVCMOS33} [get_ports {gp_i[6]}]
set_property -dict {PACKAGE_PIN P27 IOSTANDARD LVCMOS33} [get_ports {gp_i[7]}]

# Console UART
set_property -dict {PACKAGE_PIN Y23 IOSTANDARD LVCMOS33} [get_ports uart0_tx_o]
set_property -dict {PACKAGE_PIN Y20 IOSTANDARD LVCMOS33} [get_ports uart0_rx_i]
