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
// K10 — Arithmetic Logic Unit (ALU)
// ============================================================================
// Purely combinational.  Implements the base-I ALU operations plus a
// pass-through mode used for LUI / AUIPC.
// ============================================================================

module k10_alu
  import komandara_k10_pkg::*;
(
    input  alu_op_e     i_op,
    input  logic [31:0] i_a,
    input  logic [31:0] i_b,
    output logic [31:0] o_result
);

    always_comb begin
        o_result = 32'd0;  // default

        unique case (i_op)
            ALU_ADD:    o_result = i_a + i_b;
            ALU_SUB:    o_result = i_a - i_b;
            ALU_SLL:    o_result = i_a << i_b[4:0];
            ALU_SLT:    o_result = {31'd0, $signed(i_a) < $signed(i_b)};
            ALU_SLTU:   o_result = {31'd0, i_a < i_b};
            ALU_XOR:    o_result = i_a ^ i_b;
            ALU_SRL:    o_result = i_a >> i_b[4:0];
            ALU_SRA:    o_result = $unsigned($signed(i_a) >>> i_b[4:0]);
            ALU_OR:     o_result = i_a | i_b;
            ALU_AND:    o_result = i_a & i_b;
            ALU_PASS_B: o_result = i_b;
            default:    o_result = 32'd0;
        endcase
    end

endmodule : k10_alu
