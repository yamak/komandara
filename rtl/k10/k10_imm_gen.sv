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
// K10 — Immediate Generator
// ============================================================================
// Extracts and sign-extends the immediate field from a 32-bit RISC-V
// instruction.  Handles all five immediate formats (I, S, B, U, J).
//
// The opcode is used to select the format — this keeps the module
// self-contained so the decoder can simply pass the raw instruction.
// ============================================================================

module k10_imm_gen
  import komandara_k10_pkg::*;
(
    input  logic [31:0] i_instr,
    output logic [31:0] o_imm
);

    logic [6:0] w_opcode;
    assign w_opcode = i_instr[6:0];

    always_comb begin
        o_imm = 32'd0;  // default

        unique case (w_opcode)
            // ---------------------------------------------------------------
            // I-type: OP-IMM, LOAD, JALR, SYSTEM (CSR immediate = zimm)
            // ---------------------------------------------------------------
            OP_OP_IMM,
            OP_LOAD,
            OP_JALR: begin
                o_imm = {{20{i_instr[31]}}, i_instr[31:20]};
            end

            // ---------------------------------------------------------------
            // S-type: STORE
            // ---------------------------------------------------------------
            OP_STORE: begin
                o_imm = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]};
            end

            // ---------------------------------------------------------------
            // B-type: BRANCH
            // ---------------------------------------------------------------
            OP_BRANCH: begin
                o_imm = {{19{i_instr[31]}}, i_instr[31], i_instr[7],
                          i_instr[30:25], i_instr[11:8], 1'b0};
            end

            // ---------------------------------------------------------------
            // U-type: LUI, AUIPC
            // ---------------------------------------------------------------
            OP_LUI,
            OP_AUIPC: begin
                o_imm = {i_instr[31:12], 12'd0};
            end

            // ---------------------------------------------------------------
            // J-type: JAL
            // ---------------------------------------------------------------
            OP_JAL: begin
                o_imm = {{11{i_instr[31]}}, i_instr[31], i_instr[19:12],
                          i_instr[20], i_instr[30:21], 1'b0};
            end

            // SYSTEM — CSR zimm (unsigned 5-bit zero-extended)
            OP_SYSTEM: begin
                o_imm = {27'd0, i_instr[19:15]};
            end

            default: begin
                o_imm = 32'd0;
            end
        endcase
    end

endmodule : k10_imm_gen
