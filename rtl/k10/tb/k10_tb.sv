// Copyright 2025 The Komandara Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

/* verilator lint_off WIDTHTRUNC */
module k10_tb
  import komandara_k10_pkg::*;
#(
    parameter int          MEM_SIZE_KB = 64,
    parameter              MEM_INIT    = "",
    parameter logic [31:0] BOOT_ADDR   = 32'h8000_0000
)(
    input  logic i_clk,
    input  logic i_rst_n
);

    /* verilator lint_off SYNCASYNCNET */
    /* verilator lint_on WIDTHTRUNC */

    logic w_uart_tx;
    logic w_timer_irq;
    logic w_sw_irq;
    logic w_uart_irq;
    logic [63:0] w_mtime;

    k10_soc #(
        .MEM_SIZE_KB (MEM_SIZE_KB),
        .MEM_BASE    (32'h8000_0000),
        .MEM_MASK    (32'hFFFF_0000),
        .MEM_INIT    (MEM_INIT),
        .BOOT_ADDR   (BOOT_ADDR)
    ) u_dut (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .i_ext_irq   (1'b0),
        .i_irq_fast  (15'd0),
        .i_debug_req (1'b0),
        .i_uart_rx   (1'b1),
        .o_uart_tx   (w_uart_tx),
        .o_timer_irq (w_timer_irq),
        .o_sw_irq    (w_sw_irq),
        .o_uart_irq  (w_uart_irq),
        .o_mtime     (w_mtime)
    );

    logic w_ecall_trap;
    logic r_finish_pending;
    logic [3:0] r_finish_count;
    int r_finish_on_ecall;
    int r_finish_on_ebreak;

    localparam int unsigned ECALL_DRAIN_CYCLES = 3;

    initial begin
        r_finish_on_ecall = 1;
        r_finish_on_ebreak = 0;
        void'($value$plusargs("finish_on_ecall=%d", r_finish_on_ecall));
        void'($value$plusargs("finish_on_ebreak=%d", r_finish_on_ebreak));
    end

    assign w_ecall_trap = u_dut.u_top.u_core.w_exc_valid &&
                          ((u_dut.u_top.u_core.w_exc_cause == 32'd8)  ||
                           (u_dut.u_top.u_core.w_exc_cause == 32'd9)  ||
                           (u_dut.u_top.u_core.w_exc_cause == 32'd11));

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_finish_pending <= 1'b0;
            r_finish_count   <= '0;
        end else begin
            if (!r_finish_pending && (r_finish_on_ecall != 0) && w_ecall_trap) begin
                r_finish_pending <= 1'b1;
                r_finish_count   <= ECALL_DRAIN_CYCLES[3:0];
            end else if (r_finish_pending && (r_finish_count != 0)) begin
                r_finish_count <= r_finish_count - 1'b1;
            end

            if (r_finish_pending && (r_finish_count == 0)) begin
                $display("[K10_TB] ECALL detected — simulation complete.");
                $finish;
            end
        end
    end

    always_ff @(posedge i_clk) begin
        if ((r_finish_on_ebreak != 0) &&
            u_dut.u_top.u_core.w_exc_valid &&
            (u_dut.u_top.u_core.w_exc_cause == 32'd3)) begin
            $display("[K10_TB] EBREAK detected — simulation failed.");
            $finish;
        end
    end

    longint unsigned cycle_count /* verilator public */;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    /* verilator lint_on SYNCASYNCNET */

endmodule : k10_tb
