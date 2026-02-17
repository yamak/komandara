// Copyright 2025 The Komandara Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// ============================================================================
// K10 — Verilator Testbench Top  (simulation only)
// ============================================================================
// Wraps k10_top with:
//   - Timer peripheral  (0x4000_0000 – 0x4000_0FFF)
//   - Sim controller    (0x4000_1000 – 0x4000_1FFF)
//   - Peripheral AXI4-Lite address decoder (split by addr[12])
//   - ECALL / sim_ctrl driven termination
// ============================================================================

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

    // -----------------------------------------------------------------------
    // Peripheral AXI4-Lite bus from k10_top
    // -----------------------------------------------------------------------
    logic [31:0] w_peri_awaddr;
    logic [2:0]  w_peri_awprot;
    logic        w_peri_awvalid;
    logic        w_peri_awready;
    logic [31:0] w_peri_wdata;
    logic [3:0]  w_peri_wstrb;
    logic        w_peri_wvalid;
    logic        w_peri_wready;
    logic [1:0]  w_peri_bresp;
    logic        w_peri_bvalid;
    logic        w_peri_bready;
    logic [31:0] w_peri_araddr;
    logic [2:0]  w_peri_arprot;
    logic        w_peri_arvalid;
    logic        w_peri_arready;
    logic [31:0] w_peri_rdata;
    logic [1:0]  w_peri_rresp;
    logic        w_peri_rvalid;
    logic        w_peri_rready;

    // -----------------------------------------------------------------------
    // Peripheral address decoder
    // -----------------------------------------------------------------------
    // Timer:    0x4000_0xxx  (addr[12] = 0)
    // Sim Ctrl: 0x4000_1xxx  (addr[12] = 1)
    //
    // We route AW/W/AR channels based on the address bit[12].
    // For simplicity, we latch the write-side select from awaddr[12]
    // and the read-side select from araddr[12].
    // -----------------------------------------------------------------------

    // --- Timer AXI4-Lite signals ---
    logic [31:0] w_tmr_awaddr, w_tmr_wdata, w_tmr_araddr, w_tmr_rdata;
    logic [2:0]  w_tmr_awprot, w_tmr_arprot;
    logic [3:0]  w_tmr_wstrb;
    logic [1:0]  w_tmr_bresp, w_tmr_rresp;
    logic        w_tmr_awvalid, w_tmr_awready;
    logic        w_tmr_wvalid, w_tmr_wready;
    logic        w_tmr_bvalid, w_tmr_bready;
    logic        w_tmr_arvalid, w_tmr_arready;
    logic        w_tmr_rvalid, w_tmr_rready;

    // --- Sim Ctrl AXI4-Lite signals ---
    logic [31:0] w_sim_awaddr, w_sim_wdata, w_sim_araddr, w_sim_rdata;
    logic [2:0]  w_sim_awprot, w_sim_arprot;
    logic [3:0]  w_sim_wstrb;
    logic [1:0]  w_sim_bresp, w_sim_rresp;
    logic        w_sim_awvalid, w_sim_awready;
    logic        w_sim_wvalid, w_sim_wready;
    logic        w_sim_bvalid, w_sim_bready;
    logic        w_sim_arvalid, w_sim_arready;
    logic        w_sim_rvalid, w_sim_rready;

    // Write address decoder: route based on awaddr[12]
    logic w_aw_sel_sim;
    assign w_aw_sel_sim = w_peri_awaddr[12];

    assign w_tmr_awaddr  = w_peri_awaddr;
    assign w_tmr_awprot  = w_peri_awprot;
    assign w_tmr_awvalid = w_peri_awvalid && !w_aw_sel_sim;
    assign w_tmr_wdata   = w_peri_wdata;
    assign w_tmr_wstrb   = w_peri_wstrb;
    assign w_tmr_wvalid  = w_peri_wvalid && !w_aw_sel_sim;

    assign w_sim_awaddr  = w_peri_awaddr;
    assign w_sim_awprot  = w_peri_awprot;
    assign w_sim_awvalid = w_peri_awvalid && w_aw_sel_sim;
    assign w_sim_wdata   = w_peri_wdata;
    assign w_sim_wstrb   = w_peri_wstrb;
    assign w_sim_wvalid  = w_peri_wvalid && w_aw_sel_sim;

    assign w_peri_awready = w_aw_sel_sim ? w_sim_awready : w_tmr_awready;
    assign w_peri_wready  = w_aw_sel_sim ? w_sim_wready  : w_tmr_wready;

    // Write response mux — latch which peripheral was written
    logic r_wr_sel_sim;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) r_wr_sel_sim <= 1'b0;
        else if (w_peri_awvalid && w_peri_awready) r_wr_sel_sim <= w_aw_sel_sim;
    end

    assign w_tmr_bready  = w_peri_bready && !r_wr_sel_sim;
    assign w_sim_bready  = w_peri_bready && r_wr_sel_sim;
    assign w_peri_bvalid = r_wr_sel_sim ? w_sim_bvalid : w_tmr_bvalid;
    assign w_peri_bresp  = r_wr_sel_sim ? w_sim_bresp  : w_tmr_bresp;

    // Read address decoder: route based on araddr[12]
    logic w_ar_sel_sim;
    assign w_ar_sel_sim = w_peri_araddr[12];

    assign w_tmr_araddr  = w_peri_araddr;
    assign w_tmr_arprot  = w_peri_arprot;
    assign w_tmr_arvalid = w_peri_arvalid && !w_ar_sel_sim;

    assign w_sim_araddr  = w_peri_araddr;
    assign w_sim_arprot  = w_peri_arprot;
    assign w_sim_arvalid = w_peri_arvalid && w_ar_sel_sim;

    assign w_peri_arready = w_ar_sel_sim ? w_sim_arready : w_tmr_arready;

    // Read response mux — latch which peripheral was read
    logic r_rd_sel_sim;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) r_rd_sel_sim <= 1'b0;
        else if (w_peri_arvalid && w_peri_arready) r_rd_sel_sim <= w_ar_sel_sim;
    end

    assign w_tmr_rready  = w_peri_rready && !r_rd_sel_sim;
    assign w_sim_rready  = w_peri_rready && r_rd_sel_sim;
    assign w_peri_rvalid = r_rd_sel_sim ? w_sim_rvalid : w_tmr_rvalid;
    assign w_peri_rdata  = r_rd_sel_sim ? w_sim_rdata  : w_tmr_rdata;
    assign w_peri_rresp  = r_rd_sel_sim ? w_sim_rresp  : w_tmr_rresp;

    // -----------------------------------------------------------------------
    // Timer Peripheral (0x4000_0xxx)
    // -----------------------------------------------------------------------
    logic        w_timer_irq;
    logic [63:0] w_mtime;

    k10_timer u_timer (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .s_axi_awaddr  (w_tmr_awaddr),
        .s_axi_awprot  (w_tmr_awprot),
        .s_axi_awvalid (w_tmr_awvalid),
        .s_axi_awready (w_tmr_awready),
        .s_axi_wdata   (w_tmr_wdata),
        .s_axi_wstrb   (w_tmr_wstrb),
        .s_axi_wvalid  (w_tmr_wvalid),
        .s_axi_wready  (w_tmr_wready),
        .s_axi_bresp   (w_tmr_bresp),
        .s_axi_bvalid  (w_tmr_bvalid),
        .s_axi_bready  (w_tmr_bready),
        .s_axi_araddr  (w_tmr_araddr),
        .s_axi_arprot  (w_tmr_arprot),
        .s_axi_arvalid (w_tmr_arvalid),
        .s_axi_arready (w_tmr_arready),
        .s_axi_rdata   (w_tmr_rdata),
        .s_axi_rresp   (w_tmr_rresp),
        .s_axi_rvalid  (w_tmr_rvalid),
        .s_axi_rready  (w_tmr_rready),
        .o_timer_irq   (w_timer_irq),
        .o_mtime       (w_mtime)
    );

    // -----------------------------------------------------------------------
    // Sim Controller (0x4000_1xxx)
    // -----------------------------------------------------------------------
    logic w_sw_irq;

    k10_sim_ctrl u_sim_ctrl (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .s_axi_awaddr  (w_sim_awaddr),
        .s_axi_awprot  (w_sim_awprot),
        .s_axi_awvalid (w_sim_awvalid),
        .s_axi_awready (w_sim_awready),
        .s_axi_wdata   (w_sim_wdata),
        .s_axi_wstrb   (w_sim_wstrb),
        .s_axi_wvalid  (w_sim_wvalid),
        .s_axi_wready  (w_sim_wready),
        .s_axi_bresp   (w_sim_bresp),
        .s_axi_bvalid  (w_sim_bvalid),
        .s_axi_bready  (w_sim_bready),
        .s_axi_araddr  (w_sim_araddr),
        .s_axi_arprot  (w_sim_arprot),
        .s_axi_arvalid (w_sim_arvalid),
        .s_axi_arready (w_sim_arready),
        .s_axi_rdata   (w_sim_rdata),
        .s_axi_rresp   (w_sim_rresp),
        .s_axi_rvalid  (w_sim_rvalid),
        .s_axi_rready  (w_sim_rready),
        .o_sw_irq      (w_sw_irq)
    );

    // -----------------------------------------------------------------------
    // DUT — BRAM mapped at 0x80000000 (Spike-compatible)
    // -----------------------------------------------------------------------
    k10_top #(
        .MEM_SIZE_KB (MEM_SIZE_KB),
        .MEM_BASE    (32'h8000_0000),
        .MEM_MASK    (32'hFFFF_0000),
        .MEM_INIT    (MEM_INIT),
        .BOOT_ADDR   (BOOT_ADDR)
    ) u_dut (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        // Interrupts — driven by peripherals
        .i_ext_irq      (1'b0),
        .i_timer_irq    (w_timer_irq),
        .i_sw_irq       (w_sw_irq),
        .i_irq_fast     (15'b0),
        // Debug
        .i_debug_req    (1'b0),
        // Timer
        .i_mtime        (w_mtime),
        // Peripheral port — to address decoder
        .o_peri_awaddr  (w_peri_awaddr),
        .o_peri_awprot  (w_peri_awprot),
        .o_peri_awvalid (w_peri_awvalid),
        .o_peri_awready (w_peri_awready),
        .o_peri_wdata   (w_peri_wdata),
        .o_peri_wstrb   (w_peri_wstrb),
        .o_peri_wvalid  (w_peri_wvalid),
        .o_peri_wready  (w_peri_wready),
        .i_peri_bresp   (w_peri_bresp),
        .i_peri_bvalid  (w_peri_bvalid),
        .o_peri_bready  (w_peri_bready),
        .o_peri_araddr  (w_peri_araddr),
        .o_peri_arprot  (w_peri_arprot),
        .o_peri_arvalid (w_peri_arvalid),
        .o_peri_arready (w_peri_arready),
        .i_peri_rdata   (w_peri_rdata),
        .i_peri_rresp   (w_peri_rresp),
        .i_peri_rvalid  (w_peri_rvalid),
        .o_peri_rready  (w_peri_rready)
    );

    // -----------------------------------------------------------------------
    // ECALL detection — watch for ECALL exception in EX stage
    // -----------------------------------------------------------------------
    logic w_ecall_trap;
    logic r_finish_pending;
    logic [3:0] r_finish_count;

    localparam int unsigned ECALL_DRAIN_CYCLES = 3;

    assign w_ecall_trap = u_dut.u_core.w_exc_valid &&
                          ((u_dut.u_core.w_exc_cause == 32'd8)  ||  // EXC_ECALL_U
                           (u_dut.u_core.w_exc_cause == 32'd9)  ||  // EXC_ECALL_S
                           (u_dut.u_core.w_exc_cause == 32'd11));   // EXC_ECALL_M

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_finish_pending <= 1'b0;
            r_finish_count   <= '0;
        end else begin
            if (!r_finish_pending && w_ecall_trap) begin
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
        if (u_dut.u_core.w_exc_valid &&
            (u_dut.u_core.w_exc_cause == 32'd3)) begin
            $display("[K10_TB] EBREAK detected — simulation failed.");
            $finish;
        end
    end

    // -----------------------------------------------------------------------
    // Cycle counter — exposed for C++ testbench timeout
    // -----------------------------------------------------------------------
    longint unsigned cycle_count /* verilator public */;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    /* verilator lint_on SYNCASYNCNET */

endmodule : k10_tb
