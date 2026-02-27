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
    input  logic i_rst_n,
    input  logic i_jtag_tck,
    input  logic i_jtag_tms,
    input  logic i_jtag_trst_n,
    input  logic i_jtag_tdi,
    output logic o_jtag_tdo
);

    /* verilator lint_off SYNCASYNCNET */
    /* verilator lint_on WIDTHTRUNC */

    logic w_uart_tx;
    logic w_timer_irq;
    logic w_sw_irq;
    logic w_uart_irq;
    logic [63:0] w_mtime;
    logic r_debug_req;

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
        .i_debug_req (r_debug_req),
        .i_jtag_tck  (i_jtag_tck),
        .i_jtag_tms  (i_jtag_tms),
        .i_jtag_trst_n(i_jtag_trst_n),
        .i_jtag_tdi  (i_jtag_tdi),
        .o_jtag_tdo  (o_jtag_tdo),
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
    int r_debug_req_cycle;
    int r_debug_req_width;
    int r_run_dmi_script;
    logic r_debug_taken_q;
    logic r_debug_exc_taken_q;
    typedef enum logic [1:0] {
        DMI_IDLE,
        DMI_REQ,
        DMI_RSP,
        DMI_DONE
    } dmi_script_state_e;

    dmi_script_state_e r_dmi_state;
    logic [4:0]  r_dmi_step;
    logic        r_dmi_phase;
    logic        r_cmdbusy_q;
    logic [2:0]  r_cmderror_q;
    logic        r_halted_q;
    logic        r_dmi_req_valid_q;
    logic        r_dmi_req_ready_q;
    logic [6:0]  w_dmi_step_addr;
    logic [31:0] w_dmi_step_data;
    dm::dtm_op_e w_dmi_step_op;
    logic        w_dmi_step_is_read;

    localparam int unsigned ECALL_DRAIN_CYCLES = 3;

    initial begin
        r_finish_on_ecall = 1;
        r_finish_on_ebreak = 0;
        r_debug_req_cycle = -1;
        r_debug_req_width = 1;
        r_run_dmi_script = 0;
        void'($value$plusargs("finish_on_ecall=%d", r_finish_on_ecall));
        void'($value$plusargs("finish_on_ebreak=%d", r_finish_on_ebreak));
        void'($value$plusargs("debug_req_cycle=%d", r_debug_req_cycle));
        void'($value$plusargs("debug_req_width=%d", r_debug_req_width));
        void'($value$plusargs("run_dmi_script=%d", r_run_dmi_script));
    end

    always_comb begin
        w_dmi_step_addr = 7'h00;
        w_dmi_step_data = 32'h0000_0000;
        w_dmi_step_op = dm::DTM_NOP;
        w_dmi_step_is_read = 1'b0;

        unique case (r_dmi_step)
            5'd0: begin // dmactive=1
                w_dmi_step_addr = 7'h10;
                w_dmi_step_data = 32'h0000_0001;
                w_dmi_step_op = dm::DTM_WRITE;
            end
            5'd1: begin // haltreq=1
                w_dmi_step_addr = 7'h10;
                w_dmi_step_data = 32'h8000_0001;
                w_dmi_step_op = dm::DTM_WRITE;
            end
            5'd2: begin // wait until halted
                w_dmi_step_addr = 7'h00;
                w_dmi_step_data = 32'h0000_0000;
                w_dmi_step_op = dm::DTM_NOP;
            end
            5'd3: begin // command: read misa
                w_dmi_step_addr = 7'h17;
                w_dmi_step_data = 32'h0032_1008;
                w_dmi_step_op = dm::DTM_WRITE;
            end
            default: begin
                w_dmi_step_addr = 7'h00;
                w_dmi_step_data = 32'h0000_0000;
                w_dmi_step_op = dm::DTM_NOP;
                w_dmi_step_is_read = 1'b0;
            end
        endcase
    end

    assign w_ecall_trap = u_dut.u_top.u_core.w_exc_valid &&
                          ((u_dut.u_top.u_core.w_exc_cause == 32'd8)  ||
                           (u_dut.u_top.u_core.w_exc_cause == 32'd9)  ||
                           (u_dut.u_top.u_core.w_exc_cause == 32'd11));

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_finish_pending <= 1'b0;
            r_finish_count   <= '0;
            r_debug_req      <= 1'b0;
            r_debug_taken_q  <= 1'b0;
            r_debug_exc_taken_q <= 1'b0;
            r_dmi_state      <= DMI_IDLE;
            r_dmi_step       <= 5'd0;
            r_dmi_phase      <= 1'b0;
            r_cmdbusy_q      <= 1'b0;
            r_cmderror_q     <= 3'd0;
            r_halted_q       <= 1'b0;
            r_dmi_req_valid_q <= 1'b0;
            r_dmi_req_ready_q <= 1'b0;
            release u_dut.u_dm_top.dmi_rsp_ready;
            release u_dut.u_dm_top.dmi_rst_n;
            release u_dut.u_dm_top.dmi_req_valid;
            release u_dut.u_dm_top.dmi_req.op;
            release u_dut.u_dm_top.dmi_req.addr;
            release u_dut.u_dm_top.dmi_req.data;
        end else begin
            if ((r_debug_req_cycle >= 0) &&
                (cycle_count >= longint'(r_debug_req_cycle)) &&
                (cycle_count < (longint'(r_debug_req_cycle) + longint'(r_debug_req_width)))) begin
                r_debug_req <= 1'b1;
            end else begin
                r_debug_req <= 1'b0;
            end

            r_debug_taken_q <= u_dut.u_top.u_core.w_debug_taken;
            r_debug_exc_taken_q <= u_dut.u_top.u_core.w_debug_exc_taken;

            if (u_dut.u_dm_top.cmdbusy != r_cmdbusy_q) begin
                $display("[K10_TB:DMI] cmdbusy=%0d cycle=%0d", u_dut.u_dm_top.cmdbusy, cycle_count);
            end
            if (u_dut.u_dm_top.cmderror != r_cmderror_q) begin
                $display("[K10_TB:DMI] cmderror=0x%0h cycle=%0d", u_dut.u_dm_top.cmderror, cycle_count);
            end
            if (u_dut.u_dm_top.halted[0] != r_halted_q) begin
                $display("[K10_TB:DMI] halted=%0d cycle=%0d", u_dut.u_dm_top.halted[0], cycle_count);
            end
            if (u_dut.u_dm_top.dmi_req_valid != r_dmi_req_valid_q) begin
                $display("[K10_TB:DMI] dmi_req_valid=%0d cycle=%0d", u_dut.u_dm_top.dmi_req_valid, cycle_count);
            end
            if (u_dut.u_dm_top.dmi_req_ready != r_dmi_req_ready_q) begin
                $display("[K10_TB:DMI] dmi_req_ready=%0d cycle=%0d", u_dut.u_dm_top.dmi_req_ready, cycle_count);
            end

            r_cmdbusy_q  <= u_dut.u_dm_top.cmdbusy;
            r_cmderror_q <= u_dut.u_dm_top.cmderror;
            r_halted_q   <= u_dut.u_dm_top.halted[0];
            r_dmi_req_valid_q <= u_dut.u_dm_top.dmi_req_valid;
            r_dmi_req_ready_q <= u_dut.u_dm_top.dmi_req_ready;

            if (u_dut.u_top.u_core.w_debug_taken && !r_debug_taken_q) begin
                $display("[K10_TB] debug_taken cycle=%0d target=%08h", cycle_count,
                         u_dut.u_top.u_core.w_pc_target);
            end

            if (u_dut.u_top.u_core.w_debug_exc_taken && !r_debug_exc_taken_q) begin
                $display("[K10_TB] debug_exception cycle=%0d cause=%08h pc=%08h", cycle_count,
                         u_dut.u_top.u_core.w_exc_cause, u_dut.u_top.u_core.w_exc_pc);
            end

            if ((r_run_dmi_script != 0) && (r_dmi_state == DMI_IDLE) && (cycle_count >= 64)) begin
                force u_dut.u_dm_top.dmi_rsp_ready = 1'b1;
                force u_dut.u_dm_top.dmi_rst_n    = 1'b1;
                force u_dut.u_dm_top.dmi_req_valid = 1'b0;
                force u_dut.u_dm_top.dmi_req.op    = dm::DTM_NOP;
                force u_dut.u_dm_top.dmi_req.addr  = 7'd0;
                force u_dut.u_dm_top.dmi_req.data  = 32'd0;
                r_dmi_step  <= 5'd0;
                r_dmi_phase <= 1'b0;
                r_dmi_state <= DMI_REQ;
                $display("[K10_TB:DMI] start script");
            end else begin
                unique case (r_dmi_state)
                    DMI_REQ: begin
                        if (w_dmi_step_op == dm::DTM_NOP) begin
                            if ((r_dmi_step == 5'd2) && u_dut.u_dm_top.halted[0]) begin
                                r_dmi_step <= r_dmi_step + 5'd1;
                            end
                        end else if (!r_dmi_phase) begin
                            force u_dut.u_dm_top.dmi_req.addr  = w_dmi_step_addr;
                            force u_dut.u_dm_top.dmi_req.data  = w_dmi_step_data;
                            force u_dut.u_dm_top.dmi_req.op    = w_dmi_step_op;
                            force u_dut.u_dm_top.dmi_req_valid = (w_dmi_step_op != dm::DTM_NOP);
                            r_dmi_phase <= 1'b1;
                        end else begin
                            force u_dut.u_dm_top.dmi_req_valid = 1'b0;
                            force u_dut.u_dm_top.dmi_req.op    = dm::DTM_NOP;
                            r_dmi_phase <= 1'b0;

                            if (w_dmi_step_is_read) begin
                                r_dmi_state <= DMI_RSP;
                            end else if (r_dmi_step == 5'd3) begin
                                r_dmi_state <= DMI_DONE;
                            end else begin
                                r_dmi_step <= r_dmi_step + 5'd1;
                            end
                        end
                    end

                    DMI_RSP: begin
                        if (u_dut.u_dm_top.dmi_rsp_valid) begin
                            $display("[K10_TB:DMI] step=%0d read_data=0x%08h resp=%0d",
                                     r_dmi_step,
                                     u_dut.u_dm_top.dmi_rsp.data,
                                     u_dut.u_dm_top.dmi_rsp.resp);

                            if (r_dmi_step == 5'd2) begin
                                r_dmi_state <= DMI_DONE;
                            end else begin
                                r_dmi_step <= r_dmi_step + 5'd1;
                                r_dmi_state <= DMI_REQ;
                            end
                        end
                    end

                    DMI_DONE: begin
                        force u_dut.u_dm_top.dmi_req_valid = 1'b0;
                        force u_dut.u_dm_top.dmi_req.op    = dm::DTM_NOP;
                    end

                    default: begin
                        r_dmi_state <= DMI_IDLE;
                    end
                endcase
            end

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
