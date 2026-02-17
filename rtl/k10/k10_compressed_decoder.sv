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
// K10 — Compressed Instruction Decoder  (RV32C → RV32I expansion)
// ============================================================================
// Purely combinational.  Takes a 16-bit compressed instruction and produces
// the equivalent 32-bit base instruction.
//
// Reference: riscv-spec-20191213, Chapter 16 — "C" Standard Extension.
//
// Compact register mapping (3-bit → 5-bit):
//   rs1'/rs2'/rd' →  x8 .. x15  (add 8 to the 3-bit field)
// ============================================================================

module k10_compressed_decoder
  import komandara_k10_pkg::*;
(
    input  logic [15:0] i_cinstr,      // 16-bit compressed instruction
    output logic [31:0] o_instr,       // Expanded 32-bit instruction
    output logic        o_illegal      // 1 = unrecognised / illegal
);

    // -----------------------------------------------------------------------
    // Instruction field extraction
    // -----------------------------------------------------------------------
    logic [1:0]  w_op;
    logic [2:0]  w_funct3;
    logic [4:0]  w_rd_rs1;   // CI / CR format rd/rs1
    logic [4:0]  w_rs2;      // CR / CSS format rs2
    logic [2:0]  w_rd_p;     // CIW / CL / CA format rd'   (compact)
    logic [2:0]  w_rs1_p;    // CL / CS / CA / CB format rs1' (compact)
    //logic [2:0]  w_rs2_p;    // CS / CA format rs2' (compact)  (same as w_rd_p)

    // Expand compact registers:  3-bit → x8..x15
    logic [4:0]  w_rd_exp;
    logic [4:0]  w_rs1_exp;
    logic [4:0]  w_rs2_exp;

    assign w_op      = i_cinstr[1:0];
    assign w_funct3  = i_cinstr[15:13];
    assign w_rd_rs1  = i_cinstr[11:7];
    assign w_rs2     = i_cinstr[6:2];
    assign w_rd_p    = i_cinstr[4:2];
    assign w_rs1_p   = i_cinstr[9:7];
    //assign w_rs2_p   = i_cinstr[4:2];  // same as w_rd_p

    assign w_rd_exp  = {2'b01, w_rd_p};
    assign w_rs1_exp = {2'b01, w_rs1_p};
    assign w_rs2_exp = {2'b01, w_rd_p};  // rs2' = rd'

    // -----------------------------------------------------------------------
    // Pre-computed intermediates (always valid, used only in specific branches)
    // All are pure functions of i_cinstr — no latches.
    // -----------------------------------------------------------------------

    // Q0: C.ADDI4SPN  nzuimm[9:2] scaled by 4
    logic [9:0] w_q0_nzuimm;
    assign w_q0_nzuimm = {i_cinstr[10:7], i_cinstr[12:11],
                           i_cinstr[5], i_cinstr[6], 2'b00};

    // Q0: C.LW / C.SW  offset[6:2] scaled by 4
    logic [6:0] w_q0_offset;
    assign w_q0_offset = {i_cinstr[5], i_cinstr[12:10], i_cinstr[6], 2'b00};

    // Q1: C.NOP/C.ADDI  nzimm[5:0]
    logic [5:0] w_q1_nzimm;
    assign w_q1_nzimm = {i_cinstr[12], i_cinstr[6:2]};

    // Q1: C.JAL / C.J  jimm[11:0]
    logic [11:0] w_q1_jimm;
    assign w_q1_jimm = {i_cinstr[12], i_cinstr[8], i_cinstr[10:9],
                         i_cinstr[6], i_cinstr[7], i_cinstr[2],
                         i_cinstr[11], i_cinstr[5:3], 1'b0};

    // Q1: C.LI / C.ANDI  imm[5:0]
    logic [5:0] w_q1_imm6;
    assign w_q1_imm6 = {i_cinstr[12], i_cinstr[6:2]};

    // Q1: C.ADDI16SP  nzimm[9:0] scaled by 16
    logic [9:0] w_q1_addi16sp_nzimm;
    assign w_q1_addi16sp_nzimm = {i_cinstr[12], i_cinstr[4:3], i_cinstr[5],
                                   i_cinstr[2], i_cinstr[6], 4'b0000};

    // Q1: C.LUI  nzimm[5:0] (upper immediate bits)
    logic [5:0] w_q1_lui_nzimm;
    assign w_q1_lui_nzimm = {i_cinstr[12], i_cinstr[6:2]};

    // Q1: C.MISC-ALU funct2 select
    logic [1:0] w_q1_funct2_hi;
    assign w_q1_funct2_hi = i_cinstr[11:10];
    logic [1:0] w_q1_funct2_lo;
    assign w_q1_funct2_lo = i_cinstr[6:5];

    // Q1: C.SRLI/C.SRAI/C.SLLI  shamt[5:0]
    logic [5:0] w_q1_shamt;
    assign w_q1_shamt = {i_cinstr[12], i_cinstr[6:2]};

    // Q1: C.BEQZ / C.BNEZ  bimm[8:0]
    logic [8:0] w_q1_bimm;
    assign w_q1_bimm = {i_cinstr[12], i_cinstr[6:5], i_cinstr[2],
                         i_cinstr[11:10], i_cinstr[4:3], 1'b0};

    // Q2: C.LWSP  offset[7:0] scaled by 4
    logic [7:0] w_q2_lwsp_offset;
    assign w_q2_lwsp_offset = {i_cinstr[3:2], i_cinstr[12],
                                i_cinstr[6:4], 2'b00};

    // Q2: C.SWSP  offset[7:0] scaled by 4
    logic [7:0] w_q2_swsp_offset;
    assign w_q2_swsp_offset = {i_cinstr[8:7], i_cinstr[12:9], 2'b00};

    // -----------------------------------------------------------------------
    // Expansion logic
    // -----------------------------------------------------------------------
    always_comb begin
        o_instr   = 32'h0000_0000;
        o_illegal = 1'b0;

        unique case (w_op)

        // ===================================================================
        // Quadrant 0  (op = 2'b00)
        // ===================================================================
        2'b00: begin
            unique case (w_funct3)
                // C.ADDI4SPN → addi rd', x2, nzuimm
                3'b000: begin
                    if (w_q0_nzuimm == 10'd0) begin
                        o_illegal = 1'b1;
                    end else begin
                        o_instr = {{2'd0, w_q0_nzuimm}, 5'd2, 3'b000,
                                   w_rd_exp, 7'b0010011};
                    end
                end

                // C.FLD — RV32DC — not supported, illegal
                3'b001: o_illegal = 1'b1;

                // C.LW → lw rd', offset(rs1')
                3'b010: begin
                    o_instr = {{5'd0, w_q0_offset}, w_rs1_exp, 3'b010,
                               w_rd_exp, 7'b0000011};
                end

                // C.FLW — RV32FC — not supported, illegal
                3'b011: o_illegal = 1'b1;

                // Reserved
                3'b100: o_illegal = 1'b1;

                // C.FSD — RV32DC — not supported, illegal
                3'b101: o_illegal = 1'b1;

                // C.SW → sw rs2', offset(rs1')
                3'b110: begin
                    // S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
                    o_instr = {{5'd0, w_q0_offset[6:5]}, w_rs2_exp, w_rs1_exp,
                               3'b010, w_q0_offset[4:0], 7'b0100011};
                end

                // C.FSW — RV32FC — not supported, illegal
                3'b111: o_illegal = 1'b1;

                default: o_illegal = 1'b1;
            endcase
        end

        // ===================================================================
        // Quadrant 1  (op = 2'b01)
        // ===================================================================
        2'b01: begin
            unique case (w_funct3)
                // C.NOP / C.ADDI → addi rd, rd, nzimm
                3'b000: begin
                    // rd=0 → NOP;  nzimm=0 && rd!=0 → HINT (treat as NOP)
                    o_instr = {{6{w_q1_nzimm[5]}}, w_q1_nzimm, w_rd_rs1, 3'b000,
                               w_rd_rs1, 7'b0010011};
                end

                // C.JAL → jal x1, offset   (RV32 only)
                3'b001: begin
                    // J-type: imm[20|10:1|11|19:12] | rd | opcode
                    o_instr = {w_q1_jimm[11], w_q1_jimm[10:1], w_q1_jimm[11],
                               {8{w_q1_jimm[11]}}, 5'd1, 7'b1101111};
                end

                // C.LI → addi rd, x0, imm
                3'b010: begin
                    o_instr = {{6{w_q1_imm6[5]}}, w_q1_imm6, 5'd0, 3'b000,
                               w_rd_rs1, 7'b0010011};
                end

                // C.ADDI16SP / C.LUI
                3'b011: begin
                    if (w_rd_rs1 == 5'd2) begin
                        // C.ADDI16SP → addi x2, x2, nzimm
                        if (w_q1_addi16sp_nzimm == 10'd0) begin
                            o_illegal = 1'b1;
                        end else begin
                            o_instr = {{2{w_q1_addi16sp_nzimm[9]}},
                                       w_q1_addi16sp_nzimm, 5'd2, 3'b000,
                                       5'd2, 7'b0010011};
                        end
                    end else begin
                        // C.LUI → lui rd, nzimm
                        if (w_q1_lui_nzimm == 6'd0 || w_rd_rs1 == 5'd0) begin
                            o_illegal = 1'b1;
                        end else begin
                            o_instr = {{14{w_q1_lui_nzimm[5]}}, w_q1_lui_nzimm,
                                       w_rd_rs1, 7'b0110111};
                        end
                    end
                end

                // C.MISC-ALU (SRLI, SRAI, ANDI, SUB, XOR, OR, AND)
                3'b100: begin
                    unique case (w_q1_funct2_hi)
                        // C.SRLI → srli rd', rd', shamt
                        2'b00: begin
                            // RV32: shamt[5] must be 0
                            if (w_q1_shamt[5]) begin
                                o_illegal = 1'b1;
                            end else begin
                                o_instr = {7'b0000000, w_q1_shamt[4:0], w_rs1_exp,
                                           3'b101, w_rs1_exp, 7'b0010011};
                            end
                        end

                        // C.SRAI → srai rd', rd', shamt
                        2'b01: begin
                            if (w_q1_shamt[5]) begin
                                o_illegal = 1'b1;
                            end else begin
                                o_instr = {7'b0100000, w_q1_shamt[4:0], w_rs1_exp,
                                           3'b101, w_rs1_exp, 7'b0010011};
                            end
                        end

                        // C.ANDI → andi rd', rd', imm
                        2'b10: begin
                            o_instr = {{6{w_q1_imm6[5]}}, w_q1_imm6, w_rs1_exp,
                                       3'b111, w_rs1_exp, 7'b0010011};
                        end

                        // Register-Register ops (C.SUB, C.XOR, C.OR, C.AND)
                        2'b11: begin
                            unique case (w_q1_funct2_lo)
                                // C.SUB → sub rd', rd', rs2'
                                2'b00: o_instr = {7'b0100000, w_rs2_exp, w_rs1_exp,
                                                  3'b000, w_rs1_exp, 7'b0110011};
                                // C.XOR → xor rd', rd', rs2'
                                2'b01: o_instr = {7'b0000000, w_rs2_exp, w_rs1_exp,
                                                  3'b100, w_rs1_exp, 7'b0110011};
                                // C.OR → or rd', rd', rs2'
                                2'b10: o_instr = {7'b0000000, w_rs2_exp, w_rs1_exp,
                                                  3'b110, w_rs1_exp, 7'b0110011};
                                // C.AND → and rd', rd', rs2'
                                2'b11: o_instr = {7'b0000000, w_rs2_exp, w_rs1_exp,
                                                  3'b111, w_rs1_exp, 7'b0110011};
                                default: o_illegal = 1'b1;
                            endcase
                        end

                        default: o_illegal = 1'b1;
                    endcase
                end

                // C.J → jal x0, offset
                3'b101: begin
                    o_instr = {w_q1_jimm[11], w_q1_jimm[10:1], w_q1_jimm[11],
                               {8{w_q1_jimm[11]}}, 5'd0, 7'b1101111};
                end

                // C.BEQZ → beq rs1', x0, offset
                3'b110: begin
                    // B-type encoding: imm[12|10:5] rs2 rs1 funct3 imm[4:1|11] opcode
                    o_instr = {{4{w_q1_bimm[8]}}, w_q1_bimm[7:5], 5'd0, w_rs1_exp,
                               3'b000, w_q1_bimm[4:1], w_q1_bimm[8], 7'b1100011};
                end

                // C.BNEZ → bne rs1', x0, offset
                3'b111: begin
                    o_instr = {{4{w_q1_bimm[8]}}, w_q1_bimm[7:5], 5'd0, w_rs1_exp,
                               3'b001, w_q1_bimm[4:1], w_q1_bimm[8], 7'b1100011};
                end

                default: o_illegal = 1'b1;
            endcase
        end

        // ===================================================================
        // Quadrant 2  (op = 2'b10)
        // ===================================================================
        2'b10: begin
            unique case (w_funct3)
                // C.SLLI → slli rd, rd, shamt
                3'b000: begin
                    if (w_q1_shamt[5] || w_rd_rs1 == 5'd0) begin
                        o_illegal = 1'b1;  // RV32: shamt[5]=1 reserved; rd=0 HINT
                    end else begin
                        o_instr = {7'b0000000, w_q1_shamt[4:0], w_rd_rs1,
                                   3'b001, w_rd_rs1, 7'b0010011};
                    end
                end

                // C.FLDSP — RV32DC — not supported
                3'b001: o_illegal = 1'b1;

                // C.LWSP → lw rd, offset(x2)
                3'b010: begin
                    if (w_rd_rs1 == 5'd0) begin
                        o_illegal = 1'b1;  // Reserved
                    end else begin
                        o_instr = {{4'd0, w_q2_lwsp_offset}, 5'd2, 3'b010,
                                   w_rd_rs1, 7'b0000011};
                    end
                end

                // C.FLWSP — RV32FC — not supported
                3'b011: o_illegal = 1'b1;

                // C.JR / C.MV / C.EBREAK / C.JALR / C.ADD
                3'b100: begin
                    if (i_cinstr[12] == 1'b0) begin
                        if (w_rs2 == 5'd0) begin
                            // C.JR → jalr x0, 0(rs1)
                            if (w_rd_rs1 == 5'd0) begin
                                o_illegal = 1'b1;  // Reserved
                            end else begin
                                o_instr = {12'd0, w_rd_rs1, 3'b000, 5'd0, 7'b1100111};
                            end
                        end else begin
                            // C.MV → add rd, x0, rs2
                            o_instr = {7'b0000000, w_rs2, 5'd0, 3'b000,
                                       w_rd_rs1, 7'b0110011};
                        end
                    end else begin
                        if (w_rs2 == 5'd0) begin
                            if (w_rd_rs1 == 5'd0) begin
                                // C.EBREAK → ebreak
                                o_instr = 32'h0010_0073;
                            end else begin
                                // C.JALR → jalr x1, 0(rs1)
                                o_instr = {12'd0, w_rd_rs1, 3'b000, 5'd1, 7'b1100111};
                            end
                        end else begin
                            // C.ADD → add rd, rd, rs2
                            o_instr = {7'b0000000, w_rs2, w_rd_rs1, 3'b000,
                                       w_rd_rs1, 7'b0110011};
                        end
                    end
                end

                // C.FSDSP — RV32DC — not supported
                3'b101: o_illegal = 1'b1;

                // C.SWSP → sw rs2, offset(x2)
                3'b110: begin
                    // S-type
                    o_instr = {{4'd0, w_q2_swsp_offset[7:5]}, w_rs2, 5'd2, 3'b010,
                               w_q2_swsp_offset[4:0], 7'b0100011};
                end

                // C.FSWSP — RV32FC — not supported
                3'b111: o_illegal = 1'b1;

                default: o_illegal = 1'b1;
            endcase
        end

        // ===================================================================
        // Quadrant 3 → 32-bit instructions; should never reach here
        // ===================================================================
        2'b11: begin
            o_illegal = 1'b1;
        end

        default: o_illegal = 1'b1;

        endcase
    end

endmodule : k10_compressed_decoder
