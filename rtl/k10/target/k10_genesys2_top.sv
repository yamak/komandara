// Copyright 2026 The Komandara Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

module k10_genesys2_top #(
    parameter int          MEM_SIZE_KB = 64,
    parameter logic [31:0] BOOT_ADDR   = 32'h8000_0000,
    parameter              MEM_INIT    = ""
)(
    input  logic IO_CLK_P,
    input  logic IO_CLK_N,
    input  logic IO_RST,
    
    // UART interface
    input  logic uart0_rx_i,
    output logic uart0_tx_o,

    // Debug Request Switch
    input  logic ext_dbg_req_i,
    
    // Status LEDs
    output logic led_timer_irq_o,
    output logic led_sw_irq_o,
    output logic led_uart_irq_o,
    output logic led_sys_rst_o,
    output logic led_mtime_0_o
);

    logic w_core_clk;
    logic w_core_rst_n;
    
    logic w_irq_timer_out;
    logic w_irq_sw_out;
    logic w_irq_uart_out;
    logic [63:0] w_mtime_out;

    k10_clock_wizard u_clock_generator (
        .IO_CLK_P (IO_CLK_P),
        .IO_CLK_N (IO_CLK_N),
        .IO_RST_N (~IO_RST),
        .clk_sys  (w_core_clk),
        .rst_sys_n(w_core_rst_n)
    );

    k10_soc #(
        .MEM_SIZE_KB (MEM_SIZE_KB),
        .MEM_BASE    (32'h8000_0000),
        .MEM_MASK    (32'hFFFF_0000),
        .MEM_INIT    (MEM_INIT),
        .BOOT_ADDR   (BOOT_ADDR)
    ) u_k10_system (
        .i_clk      (w_core_clk),
        .i_rst_n    (w_core_rst_n),
        .i_ext_irq  (1'b0),
        .i_irq_fast (15'd0),
        .i_debug_req(ext_dbg_req_i),
        .i_jtag_tck (1'b0),
        .i_jtag_tms (1'b1),
        .i_jtag_trst_n(w_core_rst_n),
        .i_jtag_tdi (1'b0),
        .o_jtag_tdo (),
        .i_uart_rx  (uart0_rx_i),
        .o_uart_tx  (uart0_tx_o),
        .o_timer_irq(w_irq_timer_out),
        .o_sw_irq   (w_irq_sw_out),
        .o_uart_irq (w_irq_uart_out),
        .o_mtime    (w_mtime_out)
    );

    assign led_timer_irq_o = w_irq_timer_out;
    assign led_sw_irq_o    = w_irq_sw_out;
    assign led_uart_irq_o  = w_irq_uart_out;
    assign led_sys_rst_o   = w_core_rst_n;
    assign led_mtime_0_o   = w_mtime_out[0];

endmodule : k10_genesys2_top
