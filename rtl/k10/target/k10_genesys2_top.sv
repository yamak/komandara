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
    input  logic       IO_CLK_P,
    input  logic       IO_CLK_N,
    input  logic       IO_RST,
    input  logic [7:0] gp_i,
    output logic [7:0] gp_o,
    input  logic       uart0_rx_i,
    output logic       uart0_tx_o
);

    logic w_clk_sys;
    logic w_rst_sys_n;
    logic w_timer_irq;
    logic w_sw_irq;
    logic w_uart_irq;
    logic [63:0] w_mtime;

    clkgen_xil7series_lvds u_clkgen (
        .IO_CLK_P (IO_CLK_P),
        .IO_CLK_N (IO_CLK_N),
        .IO_RST_N (~IO_RST),
        .clk_sys  (w_clk_sys),
        .rst_sys_n(w_rst_sys_n)
    );

    k10_soc #(
        .MEM_SIZE_KB (MEM_SIZE_KB),
        .MEM_BASE    (32'h8000_0000),
        .MEM_MASK    (32'hFFFF_0000),
        .MEM_INIT    (MEM_INIT),
        .BOOT_ADDR   (BOOT_ADDR)
    ) u_soc (
        .i_clk      (w_clk_sys),
        .i_rst_n    (w_rst_sys_n),
        .i_ext_irq  (1'b0),
        .i_irq_fast (15'd0),
        .i_debug_req(gp_i[0]),
        .i_uart_rx  (uart0_rx_i),
        .o_uart_tx  (uart0_tx_o),
        .o_timer_irq(w_timer_irq),
        .o_sw_irq   (w_sw_irq),
        .o_uart_irq (w_uart_irq),
        .o_mtime    (w_mtime)
    );

    assign gp_o[0] = w_timer_irq;
    assign gp_o[1] = w_sw_irq;
    assign gp_o[2] = w_uart_irq;
    assign gp_o[3] = w_rst_sys_n;
    assign gp_o[4] = w_mtime[0];
    assign gp_o[5] = gp_i[5];
    assign gp_o[6] = gp_i[6];
    assign gp_o[7] = gp_i[7];

endmodule : k10_genesys2_top
