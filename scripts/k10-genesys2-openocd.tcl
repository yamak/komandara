# OpenOCD configuration for the Digilent Genesys 2 FPGA board
# Connecting to the K10 RISC-V softcore debug module via JTAG/BSCANE2

interface ftdi
transport select jtag

# FTDI layout for Digilent boards
ftdi_vid_pid 0x0403 0x6010
ftdi_channel 1

# Setup pin mappings
ftdi_layout_init 0x0088 0x008b
ftdi_layout_signal nTRST -ndata 0x0010

# Board Target Configuration
set CPU_NAME k10_core
set TAP_IDCODE 0x43651093

# Register the new TAP
jtag newtap $CPU_NAME cpu -irlen 6 -expected-id $TAP_IDCODE -ignore-version

# Define the target CPU
set TARGET_CPU $CPU_NAME.cpu
target create $TARGET_CPU riscv -chain-position $TARGET_CPU

# RISC-V debug module instruction register configurations
riscv set_ir idcode 0x09
riscv set_ir dtmcs 0x22
riscv set_ir dmi 0x23

# Adapter parameters
adapter speed 1000
reset_config none

# Hardware configuration
riscv set_prefer_sba on
gdb_breakpoint_override hard
gdb_report_data_abort enable
gdb_report_register_access_error enable

init
halt
