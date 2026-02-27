set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# 200 MHz System Clock
create_clock -name sys_clk_pin -period 5.000 [get_ports IO_CLK_P]
set_property -dict {PACKAGE_PIN AD12 IOSTANDARD LVDS} [get_ports IO_CLK_P]
set_property -dict {PACKAGE_PIN AD11 IOSTANDARD LVDS} [get_ports IO_CLK_N]

# Reset Button (BTNC)
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS12} [get_ports IO_RST]

# UART
set_property -dict {PACKAGE_PIN Y20 IOSTANDARD LVCMOS33} [get_ports uart0_rx_i]
set_property -dict {PACKAGE_PIN Y23 IOSTANDARD LVCMOS33} [get_ports uart0_tx_o]

# Status LEDs
set_property -dict {PACKAGE_PIN T30  IOSTANDARD LVCMOS33} [get_ports led_timer_irq_o]
set_property -dict {PACKAGE_PIN AC26 IOSTANDARD LVCMOS33} [get_ports led_sw_irq_o]
set_property -dict {PACKAGE_PIN AJ27 IOSTANDARD LVCMOS33} [get_ports led_uart_irq_o]
set_property -dict {PACKAGE_PIN U29  IOSTANDARD LVCMOS33} [get_ports led_sys_rst_o]
set_property -dict {PACKAGE_PIN V20  IOSTANDARD LVCMOS33} [get_ports led_mtime_0_o]

# Debug Switch (SW0)
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS12} [get_ports ext_dbg_req_i]
