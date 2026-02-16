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
// Standalone testbench wrapper for k10_mul_div
// ============================================================================

module tb_mul_div
  import komandara_k10_pkg::*;
(
    input  logic        i_clk,
    input  logic        i_rst_n,

    input  logic        i_start,
    input  logic [2:0]  i_op,       // md_op_e as 3-bit logic for Verilator
    input  logic [31:0] i_a,
    input  logic [31:0] i_b,

    output logic        o_busy,
    output logic        o_done,
    output logic [31:0] o_result
);

    k10_mul_div u_dut (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_start  (i_start),
        .i_op     (md_op_e'(i_op)),
        .i_a      (i_a),
        .i_b      (i_b),
        .o_busy   (o_busy),
        .o_done   (o_done),
        .o_result (o_result)
    );

endmodule : tb_mul_div
