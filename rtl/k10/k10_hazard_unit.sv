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
// K10 — Hazard Detection & Forwarding Unit
// ============================================================================
// Centralized hazard handling for the 5-stage pipeline.
//
// Responsibilities:
//   1. Data-hazard forwarding  (MEM→EX, WB→EX)
//   2. Load-use stall          (insert bubble when load result needed next cycle)
//   3. Control-hazard flush    (branch/jump taken  →  flush IF, ID)
//   4. Trap/MRET flush         (full pipeline flush)
//   5. Memory-busy stall       (ibus / dbus not responding)
//   6. MUL/DIV busy stall
//   7. FENCE.I flush           (flush pipeline + refetch)
// ============================================================================

module k10_hazard_unit
  import komandara_k10_pkg::*;
(
    // ---- ID/EX stage info (instruction in EX) ----
    input  logic [4:0]  i_ex_rs1_addr,
    input  logic [4:0]  i_ex_rs2_addr,
    input  logic [4:0]  i_id_rs1_addr,     // from decode (for load-use)
    input  logic [4:0]  i_id_rs2_addr,

    // ---- EX/MEM stage info ----
    input  logic [4:0]  i_mem_rd_addr,
    input  logic        i_mem_reg_write,
    input  logic        i_mem_mem_read,     // load in MEM stage
    input  logic        i_mem_valid,

    // ---- MEM/WB stage info ----
    input  logic [4:0]  i_wb_rd_addr,
    input  logic        i_wb_reg_write,
    input  logic        i_wb_valid,

    // ---- Control events ----
    input  logic        i_branch_taken,     // from EX
    input  logic        i_trap_taken,       // from CSR
    input  logic        i_mret_taken,       // from CSR
    input  logic        i_dret_taken,       // from CSR (debug return)
    input  logic        i_fence_i,          // FENCE.I in ID stage

    // ---- Busy signals ----
    input  logic        i_fetch_busy,       // IF stage waiting for ibus
    input  logic        i_mem_busy,         // MEM stage waiting for dbus
    input  logic        i_md_busy,          // MUL/DIV in progress

    // ---- ID/EX stage load detection (for load-use) ----
    input  logic        i_ex_mem_read,      // load in EX stage
    input  logic [4:0]  i_ex_rd_addr,
    input  logic        i_ex_valid,

    // ===== Outputs =====

    // Stall signals (prevent pipeline register from advancing)
    output logic        o_stall_if,
    output logic        o_stall_id,
    output logic        o_stall_ex,
    output logic        o_stall_mem,

    // Flush signals (invalidate pipeline register)
    output logic        o_flush_if,
    output logic        o_flush_id,
    output logic        o_flush_ex,
    output logic        o_flush_mem,

    // Forwarding control for EX stage
    output fwd_sel_e    o_fwd_a,
    output fwd_sel_e    o_fwd_b
);

    // -----------------------------------------------------------------------
    // 1. Data forwarding  (EX/MEM → EX, MEM/WB → EX)
    // -----------------------------------------------------------------------
    always_comb begin
        // Default: no forwarding
        o_fwd_a = FWD_NONE;
        o_fwd_b = FWD_NONE;

        // Forward A  (rs1 in EX)
        if (i_mem_valid && i_mem_reg_write &&
            (i_mem_rd_addr != 5'd0) &&
            (i_mem_rd_addr == i_ex_rs1_addr)) begin
            o_fwd_a = FWD_MEM;
        end else if (i_wb_valid && i_wb_reg_write &&
                     (i_wb_rd_addr != 5'd0) &&
                     (i_wb_rd_addr == i_ex_rs1_addr)) begin
            o_fwd_a = FWD_WB;
        end

        // Forward B  (rs2 in EX)
        if (i_mem_valid && i_mem_reg_write &&
            (i_mem_rd_addr != 5'd0) &&
            (i_mem_rd_addr == i_ex_rs2_addr)) begin
            o_fwd_b = FWD_MEM;
        end else if (i_wb_valid && i_wb_reg_write &&
                     (i_wb_rd_addr != 5'd0) &&
                     (i_wb_rd_addr == i_ex_rs2_addr)) begin
            o_fwd_b = FWD_WB;
        end
    end

    // -----------------------------------------------------------------------
    // 2. Load-use hazard  (load in EX, dependent instruction in ID)
    // -----------------------------------------------------------------------
    logic w_load_use;
    assign w_load_use = i_ex_valid && i_ex_mem_read && (i_ex_rd_addr != 5'd0) &&
                        ((i_ex_rd_addr == i_id_rs1_addr) ||
                         (i_ex_rd_addr == i_id_rs2_addr));

    // -----------------------------------------------------------------------
    // Stall / Flush generation
    // -----------------------------------------------------------------------

    // Memory-stage stall propagates upward
    logic w_mem_stall;
    assign w_mem_stall = i_mem_busy;

    // EX-stage stall (MUL/DIV busy)
    logic w_ex_stall;
    assign w_ex_stall = i_md_busy;

    // ID-stage stall (load-use)
    logic w_id_stall;
    assign w_id_stall = w_load_use;

    // IF-stage stall (fetch busy)
    logic w_if_stall;
    assign w_if_stall = i_fetch_busy;

    // ---- Stall outputs (propagate: if lower stage stalls, upper ones do too) ----
    assign o_stall_mem = w_mem_stall;
    assign o_stall_ex  = w_mem_stall || w_ex_stall;
    assign o_stall_id  = w_mem_stall || w_ex_stall || w_id_stall;
    assign o_stall_if  = w_mem_stall || w_ex_stall || w_id_stall || w_if_stall;

    // ---- Flush outputs ----
    // Trap / MRET: flush everything
    // Branch taken: flush IF/ID and ID/EX
    // FENCE.I: flush like branch + refetch
    // Load-use: insert bubble into EX (flush ID/EX)
    always_comb begin
        o_flush_if  = 1'b0;
        o_flush_id  = 1'b0;
        o_flush_ex  = 1'b0;
        o_flush_mem = 1'b0;

        if (i_trap_taken || i_mret_taken || i_dret_taken) begin
            // Full pipeline flush
            o_flush_if  = 1'b1;
            o_flush_id  = 1'b1;
            o_flush_ex  = 1'b1;
            o_flush_mem = 1'b1;
        end else if (i_branch_taken || i_fence_i) begin
            // Flush IF and ID stages (wrong-path instructions)
            o_flush_if = 1'b1;
            o_flush_id = 1'b1;
        end else if (w_load_use && !w_mem_stall && !w_ex_stall) begin
            // Insert bubble: handled by w_stall_id in k10_core.sv
            // (w_stall_id causes ID/EX to load NOP while stalling IF/ID)
        end
    end

endmodule : k10_hazard_unit
