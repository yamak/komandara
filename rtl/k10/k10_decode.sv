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
// K10 — Decode Stage  (ID)
// ============================================================================
// Decodes 32-bit (and expanded 16-bit) RISC-V instructions into the
// ctrl_t control structure consumed by downstream pipeline stages.
//
// This module is purely combinational.  The compressed-instruction
// expansion is performed here by instantiating k10_compressed_decoder.
// Immediate generation is done by instantiating k10_imm_gen.
//
// Register-file reads are done externally (in k10_core); this module
// only produces register addresses and the control word.
// ============================================================================

module k10_decode
  import komandara_k10_pkg::*;
(
    // Raw instruction from IF/ID register
    input  logic [31:0] i_instr,
    input  logic        i_is_compressed,

    // Decoded outputs
    output logic [31:0] o_instr_expanded, // 32-bit instruction (after C expansion)
    output logic [4:0]  o_rs1_addr,
    output logic [4:0]  o_rs2_addr,
    output logic [4:0]  o_rd_addr,
    output logic [31:0] o_imm,
    output logic [11:0] o_csr_addr,
    output ctrl_t       o_ctrl
);

    // -----------------------------------------------------------------------
    // Compressed instruction expansion
    // -----------------------------------------------------------------------
    logic [31:0] w_expanded;
    logic        w_c_illegal;

    k10_compressed_decoder u_cdec (
        .i_cinstr  (i_instr[15:0]),
        .o_instr   (w_expanded),
        .o_illegal (w_c_illegal)
    );

    // Select expanded or raw 32-bit instruction
    logic [31:0] w_instr;
    assign w_instr = i_is_compressed ? w_expanded : i_instr;
    assign o_instr_expanded = w_instr;

    // -----------------------------------------------------------------------
    // Immediate generation
    // -----------------------------------------------------------------------
    k10_imm_gen u_immgen (
        .i_instr (w_instr),
        .o_imm   (o_imm)
    );

    // -----------------------------------------------------------------------
    // Instruction field extraction
    // -----------------------------------------------------------------------
    logic [6:0]  w_opcode;
    logic [2:0]  w_funct3;
    logic [6:0]  w_funct7;
    logic [4:0]  w_rs1, w_rs2, w_rd;
    logic [11:0] w_funct12;   // SYSTEM instructions

    assign w_opcode  = w_instr[6:0];
    assign w_funct3  = w_instr[14:12];
    assign w_funct7  = w_instr[31:25];
    assign w_rs1     = w_instr[19:15];
    assign w_rs2     = w_instr[24:20];
    assign w_rd      = w_instr[11:7];
    assign w_funct12 = w_instr[31:20];

    assign o_rs1_addr = w_rs1;
    assign o_rs2_addr = w_rs2;
    assign o_rd_addr  = w_rd;
    assign o_csr_addr = w_instr[31:20];

    // -----------------------------------------------------------------------
    // Control signal generation
    // -----------------------------------------------------------------------
    always_comb begin
        // Default: NOP-like — no side effects
        o_ctrl = '{
            alu_op:        ALU_ADD,
            alu_a_sel:     ALU_A_RS1,
            alu_b_sel:     ALU_B_RS2,
            md_en:         1'b0,
            md_op:         MD_MUL,
            is_branch:     1'b0,
            is_jal:        1'b0,
            is_jalr:       1'b0,
            branch_op:     BR_BEQ,
            mem_read:      1'b0,
            mem_write:     1'b0,
            mem_size:      LS_WORD,
            reg_write:     1'b0,
            wb_sel:        WB_ALU,
            csr_en:        1'b0,
            csr_op:        CSR_RW,
            csr_imm:       1'b0,
            is_ecall:      1'b0,
            is_ebreak:     1'b0,
            is_mret:       1'b0,
            is_dret:       1'b0,
            is_wfi:        1'b0,
            is_fence:      1'b0,
            is_fence_i:    1'b0,
            is_atomic:     1'b0,
            amo_op:        AMO_ADD,
            is_compressed: i_is_compressed,
            illegal:       1'b0
        };

        unique case (w_opcode)

            // =============================================================
            // LUI
            // =============================================================
            OP_LUI: begin
                o_ctrl.alu_op    = ALU_PASS_B;
                o_ctrl.alu_b_sel = ALU_B_IMM;
                o_ctrl.reg_write = 1'b1;
                o_ctrl.wb_sel    = WB_ALU;
            end

            // =============================================================
            // AUIPC
            // =============================================================
            OP_AUIPC: begin
                o_ctrl.alu_op    = ALU_ADD;
                o_ctrl.alu_a_sel = ALU_A_PC;
                o_ctrl.alu_b_sel = ALU_B_IMM;
                o_ctrl.reg_write = 1'b1;
                o_ctrl.wb_sel    = WB_ALU;
            end

            // =============================================================
            // JAL
            // =============================================================
            OP_JAL: begin
                o_ctrl.is_jal    = 1'b1;
                o_ctrl.alu_op    = ALU_ADD;
                o_ctrl.alu_a_sel = ALU_A_PC;
                o_ctrl.alu_b_sel = ALU_B_IMM;
                o_ctrl.reg_write = 1'b1;
                o_ctrl.wb_sel    = WB_PC4;
            end

            // =============================================================
            // JALR
            // =============================================================
            OP_JALR: begin
                o_ctrl.is_jalr   = 1'b1;
                o_ctrl.alu_op    = ALU_ADD;
                o_ctrl.alu_a_sel = ALU_A_RS1;
                o_ctrl.alu_b_sel = ALU_B_IMM;
                o_ctrl.reg_write = 1'b1;
                o_ctrl.wb_sel    = WB_PC4;
            end

            // =============================================================
            // BRANCH
            // =============================================================
            OP_BRANCH: begin
                o_ctrl.is_branch = 1'b1;
                o_ctrl.branch_op = branch_op_e'(w_funct3);
                o_ctrl.alu_op    = ALU_ADD;
                o_ctrl.alu_a_sel = ALU_A_PC;
                o_ctrl.alu_b_sel = ALU_B_IMM;
            end

            // =============================================================
            // LOAD
            // =============================================================
            OP_LOAD: begin
                o_ctrl.mem_read  = 1'b1;
                o_ctrl.mem_size  = ls_size_e'(w_funct3);
                o_ctrl.alu_op    = ALU_ADD;
                o_ctrl.alu_a_sel = ALU_A_RS1;
                o_ctrl.alu_b_sel = ALU_B_IMM;
                o_ctrl.reg_write = 1'b1;
                o_ctrl.wb_sel    = WB_MEM;
            end

            // =============================================================
            // STORE
            // =============================================================
            OP_STORE: begin
                o_ctrl.mem_write = 1'b1;
                o_ctrl.mem_size  = ls_size_e'(w_funct3);
                o_ctrl.alu_op    = ALU_ADD;
                o_ctrl.alu_a_sel = ALU_A_RS1;
                o_ctrl.alu_b_sel = ALU_B_IMM;
            end

            // =============================================================
            // OP-IMM  (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
            // =============================================================
            OP_OP_IMM: begin
                o_ctrl.alu_a_sel = ALU_A_RS1;
                o_ctrl.alu_b_sel = ALU_B_IMM;
                o_ctrl.reg_write = 1'b1;
                o_ctrl.wb_sel    = WB_ALU;

                unique case (w_funct3)
                    3'b000: o_ctrl.alu_op = ALU_ADD;           // ADDI
                    3'b010: o_ctrl.alu_op = ALU_SLT;           // SLTI
                    3'b011: o_ctrl.alu_op = ALU_SLTU;          // SLTIU
                    3'b100: o_ctrl.alu_op = ALU_XOR;           // XORI
                    3'b110: o_ctrl.alu_op = ALU_OR;            // ORI
                    3'b111: o_ctrl.alu_op = ALU_AND;           // ANDI
                    3'b001: o_ctrl.alu_op = ALU_SLL;           // SLLI
                    3'b101: begin
                        if (w_funct7[5])
                            o_ctrl.alu_op = ALU_SRA;           // SRAI
                        else
                            o_ctrl.alu_op = ALU_SRL;           // SRLI
                    end
                    default: o_ctrl.illegal = 1'b1;
                endcase
            end

            // =============================================================
            // OP  (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND)
            //     + M extension (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU)
            // =============================================================
            OP_OP: begin
                o_ctrl.alu_a_sel = ALU_A_RS1;
                o_ctrl.alu_b_sel = ALU_B_RS2;
                o_ctrl.reg_write = 1'b1;
                o_ctrl.wb_sel    = WB_ALU;

                if (w_funct7 == 7'b0000001) begin
                    // M extension
                    o_ctrl.md_en = 1'b1;
                    o_ctrl.md_op = md_op_e'(w_funct3);
                end else begin
                    unique case (w_funct3)
                        3'b000: begin
                            if (w_funct7[5])
                                o_ctrl.alu_op = ALU_SUB;       // SUB
                            else
                                o_ctrl.alu_op = ALU_ADD;       // ADD
                        end
                        3'b001: o_ctrl.alu_op = ALU_SLL;       // SLL
                        3'b010: o_ctrl.alu_op = ALU_SLT;       // SLT
                        3'b011: o_ctrl.alu_op = ALU_SLTU;      // SLTU
                        3'b100: o_ctrl.alu_op = ALU_XOR;       // XOR
                        3'b101: begin
                            if (w_funct7[5])
                                o_ctrl.alu_op = ALU_SRA;       // SRA
                            else
                                o_ctrl.alu_op = ALU_SRL;       // SRL
                        end
                        3'b110: o_ctrl.alu_op = ALU_OR;        // OR
                        3'b111: o_ctrl.alu_op = ALU_AND;       // AND
                        default: o_ctrl.illegal = 1'b1;
                    endcase
                end
            end

            // =============================================================
            // MISC-MEM  (FENCE, FENCE.I)
            // =============================================================
            OP_MISC_MEM: begin
                if (w_funct3 == 3'b000) begin
                    o_ctrl.is_fence = 1'b1;                    // FENCE
                end else if (w_funct3 == 3'b001) begin
                    o_ctrl.is_fence_i = 1'b1;                  // FENCE.I
                end else begin
                    o_ctrl.illegal = 1'b1;
                end
            end

            // =============================================================
            // SYSTEM  (ECALL, EBREAK, MRET, WFI, CSR*)
            // =============================================================
            OP_SYSTEM: begin
                if (w_funct3 == 3'b000) begin
                    // ECALL / EBREAK / MRET / WFI
                    unique case (w_funct12)
                        12'h000: o_ctrl.is_ecall  = 1'b1;     // ECALL
                        12'h001: o_ctrl.is_ebreak = 1'b1;     // EBREAK
                        12'h302: o_ctrl.is_mret   = 1'b1;     // MRET
                        12'h7B2: o_ctrl.is_dret   = 1'b1;     // DRET
                        12'h105: o_ctrl.is_wfi    = 1'b1;     // WFI
                        default: o_ctrl.illegal   = 1'b1;
                    endcase
                end else begin
                    // CSR instructions
                    o_ctrl.csr_en   = 1'b1;
                    o_ctrl.csr_op   = csr_op_e'(w_funct3[1:0]);
                    o_ctrl.csr_imm  = w_funct3[2];             // 1 → zimm
                    o_ctrl.reg_write = 1'b1;
                    o_ctrl.wb_sel    = WB_CSR;
                end
            end

            // =============================================================
            // AMO  (A extension — LR.W, SC.W, AMO*.W)
            // =============================================================
            OP_AMO: begin
                if (w_funct3 == 3'b010) begin    // .W only for RV32
                    o_ctrl.is_atomic = 1'b1;
                    o_ctrl.amo_op    = amo_op_e'(w_funct7[6:2]);
                    o_ctrl.mem_read  = 1'b1;
                    o_ctrl.mem_write = (amo_op_e'(w_funct7[6:2]) != AMO_LR);
                    o_ctrl.reg_write = 1'b1;
                    o_ctrl.wb_sel    = WB_MEM;
                    // ALU computes address (rs1 + 0)
                    o_ctrl.alu_op    = ALU_ADD;
                    o_ctrl.alu_a_sel = ALU_A_RS1;
                    o_ctrl.alu_b_sel = ALU_B_IMM; // imm will be 0
                end else begin
                    o_ctrl.illegal = 1'b1;
                end
            end

            default: begin
                o_ctrl.illegal = 1'b1;
            end

        endcase

        // Mark compressed-illegal
        if (i_is_compressed && w_c_illegal) begin
            o_ctrl.illegal = 1'b1;
        end
    end

endmodule : k10_decode
