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
// K10 — Core Top
// ============================================================================
// 5-stage in-order RV32IMAC_Zicsr_Zifencei pipeline.
//
// This module instantiates all pipeline stages, the register file, the
// hazard / forwarding unit, the CSR unit, the PMP checker, and the
// multiply/divide unit.  Pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB)
// are managed centrally here so that the hazard unit can stall / flush them.
//
// External bus interfaces:
//   - Instruction bus  (simple valid/ready request–response)
//   - Data bus         (simple valid/ready request–response)
//
// The SoC top (k10_top) wraps these buses with AXI4-Lite masters.
// ============================================================================

module k10_core
  import komandara_k10_pkg::*;
#(
    parameter logic [31:0] BOOT_ADDR   = 32'h0000_0000,
    parameter int unsigned PMP_REGIONS = 16,
    parameter logic [31:0] MHARTID     = 32'd0
)(
    input  logic        i_clk,
    input  logic        i_rst_n,

    // ==== Instruction bus ====
    output logic        o_ibus_req,
    output logic [31:0] o_ibus_addr,
    input  logic        i_ibus_gnt,
    input  logic        i_ibus_rvalid,
    input  logic [31:0] i_ibus_rdata,
    input  logic        i_ibus_err,

    // ==== Data bus ====
    output logic        o_dbus_req,
    output logic        o_dbus_we,
    output logic [31:0] o_dbus_addr,
    output logic [31:0] o_dbus_wdata,
    output logic [3:0]  o_dbus_wstrb,
    input  logic        i_dbus_gnt,
    input  logic        i_dbus_rvalid,
    input  logic [31:0] i_dbus_rdata,
    input  logic        i_dbus_err,

    // ==== Interrupts ====
    input  logic        i_ext_irq,
    input  logic        i_timer_irq,
    input  logic        i_sw_irq,
    input  logic [14:0] i_irq_fast,

    // ==== Debug ====
    input  logic        i_debug_req,

    // ==== Timer ====
    input  logic [63:0] i_mtime
);

    // =======================================================================
    //  Internal wires
    // =======================================================================

    // Hazard unit outputs
    logic       w_stall_if, w_stall_id, w_stall_ex, w_stall_mem;
    logic       w_flush_if, w_flush_id, w_flush_ex, w_flush_mem;
    fwd_sel_e   w_fwd_a, w_fwd_b;

    // Fetch outputs
    logic [31:0] w_if_pc, w_if_instr;
    logic        w_if_is_compressed, w_if_valid, w_if_ibus_err, w_if_busy;

    // Decode outputs
    logic [31:0] w_id_instr_expanded, w_id_imm;
    logic [4:0]  w_id_rs1_addr, w_id_rs2_addr, w_id_rd_addr;
    logic [11:0] w_id_csr_addr;
    ctrl_t       w_id_ctrl;

    // Register file outputs
    logic [31:0] w_rf_rs1_data, w_rf_rs2_data;

    // Execute outputs
    logic [31:0] w_ex_alu_result, w_ex_rs1_fwd, w_ex_rs2_fwd, w_ex_branch_target, w_ex_pc_plus;
    logic        w_ex_branch_taken;

    // Memory outputs
    logic [31:0] w_mem_rdata;
    logic        w_mem_busy, w_mem_err;
    logic        w_mem_misalign_load, w_mem_misalign_store;

    // Writeback outputs
    logic        w_wb_rf_wr_en;
    logic [4:0]  w_wb_rf_rd_addr;
    logic [31:0] w_wb_rf_rd_data;

    // CSR outputs
    logic [31:0] w_csr_rdata;
    logic        w_csr_illegal;
    priv_lvl_e   w_csr_priv;
    logic        w_trap_taken;
    logic [31:0] w_trap_target;
    logic        w_mret_taken;
    logic [31:0] w_mret_target;
    logic        w_dret_taken;
    logic [31:0] w_dret_target;
    logic        w_debug_mode;

    // PMP
    logic [PMP_REGIONS-1:0][7:0]  w_pmp_cfg;
    logic [PMP_REGIONS-1:0][31:0] w_pmp_addr;

    // MUL/DIV
    logic        w_md_busy, w_md_done;
    logic [31:0] w_md_result;

    // PC redirect
    logic        w_pc_set;
    logic [31:0] w_pc_target;

    // =======================================================================
    //  Pipeline Registers
    // =======================================================================
    if_id_t  r_if_id;
    id_ex_t  r_id_ex;
    ex_mem_t r_ex_mem;
    mem_wb_t r_mem_wb;

    // =======================================================================
    //  1. FETCH STAGE
    // =======================================================================
    assign w_pc_set    = w_ex_branch_taken || w_trap_taken || w_mret_taken || w_dret_taken;
    assign w_pc_target = w_trap_taken ? w_trap_target :
                         w_dret_taken ? w_dret_target :
                         w_mret_taken ? w_mret_target :
                         w_ex_branch_target;

    k10_fetch #(
        .BOOT_ADDR (BOOT_ADDR)
    ) u_fetch (
        .i_clk           (i_clk),
        .i_rst_n         (i_rst_n),
        .i_stall         (w_stall_if),
        .i_flush         (w_flush_if),
        .i_pc_set        (w_pc_set),
        .i_pc_target     (w_pc_target),
        .o_ibus_req      (o_ibus_req),
        .o_ibus_addr     (o_ibus_addr),
        .i_ibus_gnt      (i_ibus_gnt),
        .i_ibus_rvalid   (i_ibus_rvalid),
        .i_ibus_rdata    (i_ibus_rdata),
        .i_ibus_err      (i_ibus_err),
        .o_pc            (w_if_pc),
        .o_instr         (w_if_instr),
        .o_is_compressed (w_if_is_compressed),
        .o_valid         (w_if_valid),
        .o_ibus_err      (w_if_ibus_err),
        .o_busy          (w_if_busy)
    );

    // ---- IF/ID Pipeline Register ----
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_if_id <= IF_ID_NOP;
        end else if (w_flush_if || w_flush_id) begin
            r_if_id <= IF_ID_NOP;
        end else if (!w_stall_id) begin
            if (w_stall_if) begin
                // IF is stalled: insert bubble into ID
                r_if_id <= IF_ID_NOP;
            end else begin
                r_if_id.pc            <= w_if_pc;
                r_if_id.instr         <= w_if_instr;
                r_if_id.is_compressed <= w_if_is_compressed;
                r_if_id.valid         <= w_if_valid;
            end
        end
    end

    // =======================================================================
    //  2. DECODE STAGE
    // =======================================================================
    k10_decode u_decode (
        .i_instr          (r_if_id.instr),
        .i_is_compressed  (r_if_id.is_compressed),
        .o_instr_expanded (w_id_instr_expanded),
        .o_rs1_addr       (w_id_rs1_addr),
        .o_rs2_addr       (w_id_rs2_addr),
        .o_rd_addr        (w_id_rd_addr),
        .o_imm            (w_id_imm),
        .o_csr_addr       (w_id_csr_addr),
        .o_ctrl           (w_id_ctrl)
    );

    // Register file  (reads in ID, writes in WB — same cycle forwarding)
    k10_regfile u_regfile (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_rs1_addr (w_id_rs1_addr),
        .o_rs1_data (w_rf_rs1_data),
        .i_rs2_addr (w_id_rs2_addr),
        .o_rs2_data (w_rf_rs2_data),
        .i_wr_en    (w_wb_rf_wr_en),
        .i_rd_addr  (w_wb_rf_rd_addr),
        .i_rd_data  (w_wb_rf_rd_data)
    );

    // ---- ID/EX Pipeline Register ----
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_id_ex <= ID_EX_NOP;
        end else if (w_flush_id) begin
            r_id_ex <= ID_EX_NOP;
        end else if (!w_stall_ex) begin
            if (w_stall_id) begin
                // ID is stalled: insert bubble into EX
                r_id_ex <= ID_EX_NOP;
            end else begin
                r_id_ex.pc       <= r_if_id.pc;
                r_id_ex.instr    <= w_id_instr_expanded;
                r_id_ex.rs1_data <= w_rf_rs1_data;
                r_id_ex.rs2_data <= w_rf_rs2_data;
                r_id_ex.imm      <= w_id_imm;
                r_id_ex.rs1_addr <= w_id_rs1_addr;
                r_id_ex.rs2_addr <= w_id_rs2_addr;
                r_id_ex.rd_addr  <= w_id_rd_addr;
                r_id_ex.csr_addr <= w_id_csr_addr;
                r_id_ex.ctrl     <= r_if_id.valid ? w_id_ctrl : CTRL_NOP;
                r_id_ex.valid    <= r_if_id.valid && !w_flush_id;
            end
        end
    end

    // =======================================================================
    //  3. EXECUTE STAGE
    // =======================================================================

    // Forwarding data from later stages
    logic [31:0] w_fwd_mem_data;
    logic [31:0] w_fwd_wb_data;
    assign w_fwd_mem_data = r_ex_mem.alu_result;
    assign w_fwd_wb_data  = w_wb_rf_rd_data;

    k10_execute u_execute (
        .i_pc            (r_id_ex.pc),
        .i_rs1_data      (r_id_ex.rs1_data),
        .i_rs2_data      (r_id_ex.rs2_data),
        .i_imm           (r_id_ex.imm),
        .i_ctrl          (r_id_ex.ctrl),
        .i_fwd_a         (w_fwd_a),
        .i_fwd_b         (w_fwd_b),
        .i_fwd_mem_data  (w_fwd_mem_data),
        .i_fwd_wb_data   (w_fwd_wb_data),
        .o_alu_result    (w_ex_alu_result),
        .o_rs1_fwd       (w_ex_rs1_fwd),
        .o_rs2_fwd       (w_ex_rs2_fwd),
        .o_branch_taken  (w_ex_branch_taken),
        .o_branch_target (w_ex_branch_target),
        .o_pc_plus       (w_ex_pc_plus)
    );

    // CSR unit  (read happens in EX, write committed if no trap)
    logic [31:0] w_csr_wdata;
    assign w_csr_wdata = r_id_ex.ctrl.csr_imm
                         ? {27'd0, r_id_ex.rs1_addr}  // zimm
                         : w_ex_rs1_fwd;

    // Exception aggregation
    logic        w_exc_valid;
    logic [31:0] w_exc_cause;
    logic [31:0] w_exc_pc;
    logic [31:0] w_exc_tval;

    always_comb begin
        w_exc_valid = 1'b0;
        w_exc_cause = 32'd0;
        w_exc_pc    = r_id_ex.pc;
        w_exc_tval  = 32'd0;

        if (r_id_ex.valid) begin
            if (r_id_ex.ctrl.illegal || w_csr_illegal) begin
                w_exc_valid = 1'b1;
                w_exc_cause = EXC_ILLEGAL_INSTR;
                w_exc_tval  = w_id_instr_expanded;  // The offending instruction
            end else if (r_id_ex.ctrl.is_ecall) begin
                w_exc_valid = 1'b1;
                w_exc_cause = (w_csr_priv == PRIV_M) ? EXC_ECALL_M : EXC_ECALL_U;
            end else if (r_id_ex.ctrl.is_ebreak) begin
                w_exc_valid = 1'b1;
                w_exc_cause = EXC_BREAKPOINT;
                w_exc_tval  = r_id_ex.pc;
            end
        end

        // Memory-stage exceptions (from previous cycle's MEM stage)
        if (r_ex_mem.valid) begin
            if (w_mem_misalign_load) begin
                w_exc_valid = 1'b1;
                w_exc_cause = EXC_LOAD_MISALIGN;
                w_exc_pc    = r_ex_mem.pc;
                w_exc_tval  = r_ex_mem.alu_result;  // Faulting address
            end else if (w_mem_misalign_store) begin
                w_exc_valid = 1'b1;
                w_exc_cause = EXC_STORE_MISALIGN;
                w_exc_pc    = r_ex_mem.pc;
                w_exc_tval  = r_ex_mem.alu_result;
            end else if (w_mem_err) begin
                w_exc_valid = 1'b1;
                w_exc_cause = r_ex_mem.ctrl.mem_read ? EXC_LOAD_FAULT : EXC_STORE_FAULT;
                w_exc_pc    = r_ex_mem.pc;
                w_exc_tval  = r_ex_mem.alu_result;
            end
        end
    end

    k10_csr #(
        .MHARTID     (MHARTID),
        .PMP_REGIONS (PMP_REGIONS)
    ) u_csr (
        .i_clk           (i_clk),
        .i_rst_n         (i_rst_n),
        .i_csr_en        (r_id_ex.valid && r_id_ex.ctrl.csr_en),
        .i_csr_op        (r_id_ex.ctrl.csr_op),
        .i_csr_addr      (r_id_ex.csr_addr),
        .i_csr_wdata     (w_csr_wdata),
        .o_csr_rdata     (w_csr_rdata),
        .o_csr_illegal   (w_csr_illegal),
        .o_priv_lvl      (w_csr_priv),
        .i_exc_valid     (w_exc_valid),
        .i_exc_cause     (w_exc_cause),
        .i_exc_pc        (w_exc_pc),
        .i_exc_tval      (w_exc_tval),
        .i_is_mret       (r_id_ex.valid && r_id_ex.ctrl.is_mret),
        .i_is_wfi        (r_id_ex.valid && r_id_ex.ctrl.is_wfi),
        .i_is_dret       (r_id_ex.valid && r_id_ex.ctrl.is_dret),
        .i_ext_irq       (i_ext_irq && r_id_ex.valid),
        .i_timer_irq     (i_timer_irq && r_id_ex.valid),
        .i_sw_irq        (i_sw_irq && r_id_ex.valid),
        .i_irq_fast      (i_irq_fast & {15{r_id_ex.valid}}),
        .i_debug_req     (i_debug_req),
        .o_debug_mode    (w_debug_mode),
        .o_trap_taken    (w_trap_taken),
        .o_trap_target   (w_trap_target),
        .o_mret_taken    (w_mret_taken),
        .o_mret_target   (w_mret_target),
        .o_dret_taken    (w_dret_taken),
        .o_dret_target   (w_dret_target),
        .i_instr_retired (r_mem_wb.valid),
        .o_pmp_cfg       (w_pmp_cfg),
        .o_pmp_addr      (w_pmp_addr),
        .i_mtime         (i_mtime)
    );



    // Multiply / Divide — uses forwarded operands (critical for data hazards)
    k10_mul_div u_md (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_start  (r_id_ex.valid && r_id_ex.ctrl.md_en),
        .i_op     (r_id_ex.ctrl.md_op),
        .i_a      (w_ex_rs1_fwd),
        .i_b      (w_ex_rs2_fwd),
        .o_busy   (w_md_busy),
        .o_done   (w_md_done),
        .o_result (w_md_result)
    );

    // PMP check for data bus  (instruction bus PMP is optional for K10)
    logic w_dbus_pmp_ok;
    k10_pmp #(
        .PMP_REGIONS (PMP_REGIONS)
    ) u_pmp_dbus (
        .i_pmp_cfg  (w_pmp_cfg),
        .i_pmp_addr (w_pmp_addr),
        .i_addr     (w_ex_alu_result),
        .i_priv     (w_csr_priv),
        .i_read     (r_id_ex.ctrl.mem_read),
        .i_write    (r_id_ex.ctrl.mem_write),
        .i_exec     (1'b0),
        .o_allowed  (w_dbus_pmp_ok)
    );

    // ---- EX/MEM Pipeline Register ----
    // Select result: ALU or MUL/DIV
    logic [31:0] w_ex_result;
    assign w_ex_result = (r_id_ex.ctrl.md_en && w_md_done) ? w_md_result :
                         (r_id_ex.ctrl.wb_sel == WB_PC4)   ? w_ex_pc_plus :
                         w_ex_alu_result;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_ex_mem <= EX_MEM_NOP;
        end else if (w_flush_ex) begin
            r_ex_mem <= EX_MEM_NOP;
        end else if (!w_stall_mem) begin
            if (w_stall_ex) begin
                // EX is stalled (e.g. multi-cycle divide): insert bubble
                r_ex_mem <= EX_MEM_NOP;
            end else begin
                r_ex_mem.pc         <= r_id_ex.pc;
                r_ex_mem.instr      <= r_id_ex.instr;
                r_ex_mem.alu_result <= w_ex_result;
                r_ex_mem.rs2_data   <= w_ex_rs2_fwd;
                r_ex_mem.rd_addr    <= r_id_ex.rd_addr;
                r_ex_mem.csr_addr   <= r_id_ex.csr_addr;
                r_ex_mem.csr_rdata  <= w_csr_rdata;
                r_ex_mem.ctrl       <= r_id_ex.ctrl;
                r_ex_mem.valid      <= r_id_ex.valid && !w_flush_ex && !w_trap_taken;
            end
        end
    end

    // =======================================================================
    //  4. MEMORY STAGE
    // =======================================================================
    k10_memory u_memory (
        .i_clk            (i_clk),
        .i_rst_n          (i_rst_n),
        .i_alu_result     (r_ex_mem.alu_result),
        .i_rs2_data       (r_ex_mem.rs2_data),
        .i_ctrl           (r_ex_mem.ctrl),
        .i_valid          (r_ex_mem.valid),
        .o_dbus_req       (o_dbus_req),
        .o_dbus_we        (o_dbus_we),
        .o_dbus_addr      (o_dbus_addr),
        .o_dbus_wdata     (o_dbus_wdata),
        .o_dbus_wstrb     (o_dbus_wstrb),
        .i_dbus_gnt       (i_dbus_gnt),
        .i_dbus_rvalid    (i_dbus_rvalid),
        .i_dbus_rdata     (i_dbus_rdata),
        .i_dbus_err       (i_dbus_err),
        .o_mem_rdata      (w_mem_rdata),
        .o_busy           (w_mem_busy),
        .o_mem_err        (w_mem_err),
        .o_misalign_load  (w_mem_misalign_load),
        .o_misalign_store (w_mem_misalign_store)
    );

    // ---- MEM/WB Pipeline Register ----
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mem_wb <= MEM_WB_NOP;
        end else if (w_flush_mem) begin
            r_mem_wb <= MEM_WB_NOP;
        end else if (w_stall_mem) begin
            // MEM stage busy (LSU in progress) — insert bubble into WB
            r_mem_wb <= MEM_WB_NOP;
        end else begin
            r_mem_wb.pc         <= r_ex_mem.pc;
            r_mem_wb.instr      <= r_ex_mem.instr;
            r_mem_wb.alu_result <= r_ex_mem.alu_result;
            r_mem_wb.mem_rdata  <= w_mem_rdata;
            r_mem_wb.csr_rdata  <= r_ex_mem.csr_rdata;
            r_mem_wb.rd_addr    <= r_ex_mem.rd_addr;
            r_mem_wb.ctrl       <= r_ex_mem.ctrl;
            r_mem_wb.valid      <= r_ex_mem.valid && !w_flush_mem;
        end
    end

    // =======================================================================
    //  5. WRITEBACK STAGE
    // =======================================================================
    k10_writeback u_writeback (
        .i_alu_result (r_mem_wb.alu_result),
        .i_mem_rdata  (r_mem_wb.mem_rdata),
        .i_csr_rdata  (r_mem_wb.csr_rdata),
        .i_pc         (r_mem_wb.pc),
        .i_rd_addr    (r_mem_wb.rd_addr),
        .i_ctrl       (r_mem_wb.ctrl),
        .i_valid      (r_mem_wb.valid),
        .o_rf_wr_en   (w_wb_rf_wr_en),
        .o_rf_rd_addr (w_wb_rf_rd_addr),
        .o_rf_rd_data (w_wb_rf_rd_data)
    );

    // =======================================================================
    //  HAZARD UNIT
    // =======================================================================
    k10_hazard_unit u_hazard (
        // EX stage register addresses
        .i_ex_rs1_addr   (r_id_ex.rs1_addr),
        .i_ex_rs2_addr   (r_id_ex.rs2_addr),

        // ID stage register addresses (for load-use detection)
        .i_id_rs1_addr   (w_id_rs1_addr),
        .i_id_rs2_addr   (w_id_rs2_addr),

        // MEM stage info
        .i_mem_rd_addr   (r_ex_mem.rd_addr),
        .i_mem_reg_write (r_ex_mem.ctrl.reg_write),
        .i_mem_mem_read  (r_ex_mem.ctrl.mem_read),
        .i_mem_valid     (r_ex_mem.valid),

        // WB stage info
        .i_wb_rd_addr    (r_mem_wb.rd_addr),
        .i_wb_reg_write  (r_mem_wb.ctrl.reg_write),
        .i_wb_valid      (r_mem_wb.valid),

        // Control events
        .i_branch_taken  (w_ex_branch_taken && r_id_ex.valid),
        .i_trap_taken    (w_trap_taken),
        .i_mret_taken    (w_mret_taken),
        .i_dret_taken    (w_dret_taken),
        .i_fence_i       (r_if_id.valid && w_id_ctrl.is_fence_i),

        // Busy signals
        .i_fetch_busy    (w_if_busy),
        .i_mem_busy      (w_mem_busy),
        .i_md_busy       (w_md_busy),

        // ID/EX stage load detection (for load-use)
        .i_ex_mem_read   (r_id_ex.ctrl.mem_read),
        .i_ex_rd_addr    (r_id_ex.rd_addr),
        .i_ex_valid      (r_id_ex.valid),

        // Outputs
        .o_stall_if      (w_stall_if),
        .o_stall_id      (w_stall_id),
        .o_stall_ex      (w_stall_ex),
        .o_stall_mem     (w_stall_mem),
        .o_flush_if      (w_flush_if),
        .o_flush_id      (w_flush_id),
        .o_flush_ex      (w_flush_ex),
        .o_flush_mem     (w_flush_mem),
        .o_fwd_a         (w_fwd_a),
        .o_fwd_b         (w_fwd_b)
    );

    // =======================================================================
    //  INSTRUCTION TRACER  (simulation only)
    // =======================================================================
`ifndef SYNTHESIS
    k10_tracer u_tracer (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_valid    (r_mem_wb.valid),
        .i_pc       (r_mem_wb.pc),
        .i_instr    (r_mem_wb.instr),
        .i_rd_addr  (r_mem_wb.rd_addr),
        .i_rd_data  (w_wb_rf_rd_data),
        .i_rd_wr_en (w_wb_rf_wr_en),
        .i_mode     (w_csr_priv)
    );
`endif


endmodule : k10_core
