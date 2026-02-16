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
// K10 — Register File  (32 × 32-bit, 2R / 1W)
// ============================================================================
// Two asynchronous read ports (combinational), one synchronous write port.
// x0 is hardwired to zero — writes to x0 are silently ignored.
// ============================================================================

module k10_regfile
  import komandara_k10_pkg::*;
(
    input  logic        i_clk,
    input  logic        i_rst_n,

    // Read port A
    input  logic [4:0]  i_rs1_addr,
    output logic [31:0] o_rs1_data,

    // Read port B
    input  logic [4:0]  i_rs2_addr,
    output logic [31:0] o_rs2_data,

    // Write port
    input  logic        i_wr_en,
    input  logic [4:0]  i_rd_addr,
    input  logic [31:0] i_rd_data
);

    // -----------------------------------------------------------------------
    // Register array
    // -----------------------------------------------------------------------
    logic [31:0] r_regs [1:31];  // x1 .. x31 (skip x0)

    // -----------------------------------------------------------------------
    // Combinational read — with write-through for same-cycle forwarding
    // -----------------------------------------------------------------------
    always_comb begin
        // Port A
        if (i_rs1_addr == 5'd0) begin
            o_rs1_data = 32'd0;
        end else if (i_wr_en && (i_rd_addr == i_rs1_addr)) begin
            o_rs1_data = i_rd_data;   // write-through
        end else begin
            o_rs1_data = r_regs[i_rs1_addr];
        end

        // Port B
        if (i_rs2_addr == 5'd0) begin
            o_rs2_data = 32'd0;
        end else if (i_wr_en && (i_rd_addr == i_rs2_addr)) begin
            o_rs2_data = i_rd_data;   // write-through
        end else begin
            o_rs2_data = r_regs[i_rs2_addr];
        end
    end

    // -----------------------------------------------------------------------
    // Sequential write
    // -----------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (int i = 1; i < 32; i++) begin
                r_regs[i] <= 32'd0;
            end
        end else if (i_wr_en && (i_rd_addr != 5'd0)) begin
            r_regs[i_rd_addr] <= i_rd_data;
        end
    end

endmodule : k10_regfile
