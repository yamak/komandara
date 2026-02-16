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
// SystemVerilog wrapper around k10_top for Verilator simulation.
// - Instantiates k10_top with BRAM memory
// - Provides clock/reset generation (driven from C++)
// - Ties off peripheral port (all reads return 0)
// - Detects ECALL instruction retirement for test termination
// - Exposes signals for the C++ testbench to monitor
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
    // Peripheral port tie-off signals
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
    // Simple peripheral responder — accepts all transactions, returns 0 data
    // -----------------------------------------------------------------------
    // Write path: always ready, respond immediately
    assign w_peri_awready = 1'b1;
    assign w_peri_wready  = 1'b1;

    // Write response
    logic r_peri_bvalid;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_peri_bvalid <= 1'b0;
        end else begin
            r_peri_bvalid <= w_peri_awvalid && w_peri_wvalid && !r_peri_bvalid;
        end
    end
    assign w_peri_bvalid = r_peri_bvalid;
    assign w_peri_bresp  = 2'b00; // OKAY

    // Read path: always ready, respond with 0
    assign w_peri_arready = 1'b1;

    logic r_peri_rvalid;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_peri_rvalid <= 1'b0;
        end else begin
            r_peri_rvalid <= w_peri_arvalid && !r_peri_rvalid;
        end
    end
    assign w_peri_rvalid = r_peri_rvalid;
    assign w_peri_rdata  = 32'd0;
    assign w_peri_rresp  = 2'b00; // OKAY

    // -----------------------------------------------------------------------
    // Timer — simple free-running counter
    // -----------------------------------------------------------------------
    logic [63:0] r_mtime;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_mtime <= 64'd0;
        else
            r_mtime <= r_mtime + 64'd1;
    end

    // -----------------------------------------------------------------------
    // DUT — BRAM mapped at 0x80000000 (Spike-compatible)
    // -----------------------------------------------------------------------
    k10_top #(
        .MEM_SIZE_KB (MEM_SIZE_KB),
        .MEM_BASE    (32'h8000_0000),
        .MEM_MASK    (32'hFFFF_0000),  // Top bits for 64KB
        .MEM_INIT    (MEM_INIT),
        .BOOT_ADDR   (BOOT_ADDR)
    ) u_dut (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        // Interrupts: tied off
        .i_ext_irq      (1'b0),
        .i_timer_irq    (1'b0),
        .i_sw_irq       (1'b0),
        .i_mtime        (r_mtime),
        // Peripheral port
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
    // ECALL raises a trap that flushes the pipeline, so the instruction
    // never reaches WB.  Instead, detect the exception cause in EX.
    logic w_ecall_trap;
    assign w_ecall_trap = u_dut.u_core.w_exc_valid &&
                          (u_dut.u_core.w_exc_cause == 32'd11);  // EXC_ECALL_M

    logic w_ebreak_trap;
    assign w_ebreak_trap = u_dut.u_core.w_exc_valid &&
                           (u_dut.u_core.w_exc_cause == 32'd3);  // EXC_BREAKPOINT

    always @(posedge i_clk) begin
        if (w_ecall_trap) begin
            $display("[K10_TB] ECALL detected — simulation PASSED.");
            $finish;
        end
        if (w_ebreak_trap) begin
            $display("[K10_TB] EBREAK detected — TEST FAILED (a0 = %0d).",
                     u_dut.u_core.u_regfile.r_regs[10]);  // a0
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
