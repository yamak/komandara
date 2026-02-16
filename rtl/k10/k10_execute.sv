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
// K10 — Execute Stage  (EX)
// ============================================================================
// Performs ALU operations, branch comparisons, and jump-target calculations.
// Forwarding muxes select between register data and forwarded results from
// MEM / WB stages.
//
// Outputs:
//   - ALU result (or branch target)
//   - Branch-taken flag + target  (used to redirect IF)
//   - Forwarded rs2 data (needed by MEM for stores)
// ============================================================================

module k10_execute
  import komandara_k10_pkg::*;
(
    // Decoded ID/EX pipeline register inputs
    input  logic [31:0] i_pc,
    input  logic [31:0] i_rs1_data,
    input  logic [31:0] i_rs2_data,
    input  logic [31:0] i_imm,
    input  ctrl_t       i_ctrl,

    // Forwarding from MEM & WB
    input  fwd_sel_e    i_fwd_a,
    input  fwd_sel_e    i_fwd_b,
    input  logic [31:0] i_fwd_mem_data,   // EX/MEM alu_result
    input  logic [31:0] i_fwd_wb_data,    // Writeback data

    // Outputs
    output logic [31:0] o_alu_result,
    output logic [31:0] o_rs1_fwd,        // Forwarded rs1 (for MUL/DIV operand A)
    output logic [31:0] o_rs2_fwd,        // Forwarded rs2 (for store data & MUL/DIV operand B)
    output logic        o_branch_taken,
    output logic [31:0] o_branch_target,

    // PC+4 / PC+2 for link-register writes  (JAL/JALR)
    output logic [31:0] o_pc_plus
);

    // -----------------------------------------------------------------------
    // Forwarding muxes
    // -----------------------------------------------------------------------
    logic [31:0] w_op_a_raw;   // After forwarding (before ALU-A select)
    logic [31:0] w_op_b_raw;   // After forwarding (before ALU-B select)

    always_comb begin
        unique case (i_fwd_a)
            FWD_NONE: w_op_a_raw = i_rs1_data;
            FWD_MEM:  w_op_a_raw = i_fwd_mem_data;
            FWD_WB:   w_op_a_raw = i_fwd_wb_data;
            default:  w_op_a_raw = i_rs1_data;
        endcase
    end

    always_comb begin
        unique case (i_fwd_b)
            FWD_NONE: w_op_b_raw = i_rs2_data;
            FWD_MEM:  w_op_b_raw = i_fwd_mem_data;
            FWD_WB:   w_op_b_raw = i_fwd_wb_data;
            default:  w_op_b_raw = i_rs2_data;
        endcase
    end

    // Forwarded register values (for store data / MUL/DIV operands)
    assign o_rs1_fwd = w_op_a_raw;
    assign o_rs2_fwd = w_op_b_raw;

    // -----------------------------------------------------------------------
    // ALU operand selection
    // -----------------------------------------------------------------------
    logic [31:0] w_alu_a;
    logic [31:0] w_alu_b;

    assign w_alu_a = (i_ctrl.alu_a_sel == ALU_A_PC)  ? i_pc       : w_op_a_raw;
    assign w_alu_b = (i_ctrl.alu_b_sel == ALU_B_IMM)  ? i_imm      : w_op_b_raw;

    // -----------------------------------------------------------------------
    // ALU
    // -----------------------------------------------------------------------
    k10_alu u_alu (
        .i_op     (i_ctrl.alu_op),
        .i_a      (w_alu_a),
        .i_b      (w_alu_b),
        .o_result (o_alu_result)
    );

    // -----------------------------------------------------------------------
    // PC + 4/2  (compressed → +2, normal → +4)
    // -----------------------------------------------------------------------
    assign o_pc_plus = i_pc + (i_ctrl.is_compressed ? 32'd2 : 32'd4);

    // -----------------------------------------------------------------------
    // Branch comparison
    // -----------------------------------------------------------------------
    logic w_branch_cond;

    always_comb begin
        w_branch_cond = 1'b0;

        unique case (i_ctrl.branch_op)
            BR_BEQ:  w_branch_cond = (w_op_a_raw == w_op_b_raw);
            BR_BNE:  w_branch_cond = (w_op_a_raw != w_op_b_raw);
            BR_BLT:  w_branch_cond = ($signed(w_op_a_raw) < $signed(w_op_b_raw));
            BR_BGE:  w_branch_cond = ($signed(w_op_a_raw) >= $signed(w_op_b_raw));
            BR_BLTU: w_branch_cond = (w_op_a_raw < w_op_b_raw);
            BR_BGEU: w_branch_cond = (w_op_a_raw >= w_op_b_raw);
            default: w_branch_cond = 1'b0;
        endcase
    end

    // -----------------------------------------------------------------------
    // Branch / Jump resolution
    // -----------------------------------------------------------------------
    always_comb begin
        o_branch_taken  = 1'b0;
        o_branch_target = 32'd0;

        if (i_ctrl.is_jal) begin
            // JAL: target = PC + imm  (already computed by ALU since a_sel=PC, b_sel=IMM)
            o_branch_taken  = 1'b1;
            o_branch_target = o_alu_result;
        end else if (i_ctrl.is_jalr) begin
            // JALR: target = (rs1 + imm) & ~1
            o_branch_taken  = 1'b1;
            o_branch_target = {o_alu_result[31:1], 1'b0};
        end else if (i_ctrl.is_branch && w_branch_cond) begin
            // Conditional branch taken: target = PC + imm  (ALU)
            o_branch_taken  = 1'b1;
            o_branch_target = o_alu_result;
        end
    end

endmodule : k10_execute
