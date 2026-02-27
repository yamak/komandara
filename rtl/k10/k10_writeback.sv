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
// K10 — Writeback Stage  (WB)
// ============================================================================
// Selects the data to write back to the register file:
//   WB_ALU  — ALU / multiply–divide result
//   WB_MEM  — Load data
//   WB_PC4  — PC + 4 (or +2 for compressed)  for JAL/JALR
//   WB_CSR  — CSR read value
//
// Purely combinational; the register-file write port is driven by the core.
// ============================================================================

module k10_writeback
  import komandara_k10_pkg::*;
(
    // MEM/WB pipeline register values
    input  logic [31:0] i_alu_result,
    input  logic [31:0] i_mem_rdata,
    input  logic [31:0] i_csr_rdata,
    input  logic [31:0] i_pc,
    input  logic [4:0]  i_rd_addr,
    input  ctrl_t       i_ctrl,
    input  logic        i_valid,

    // Register-file write interface
    output logic        o_rf_wr_en,
    output logic [4:0]  o_rf_rd_addr,
    output logic [31:0] o_rf_rd_data
);

    // PC + 4/2 for link-register writes
    logic [31:0] w_pc_plus;
    assign w_pc_plus = i_pc + (i_ctrl.is_compressed ? 32'd2 : 32'd4);

    // -----------------------------------------------------------------------
    // Writeback mux
    // -----------------------------------------------------------------------
    always_comb begin
        o_rf_rd_data = 32'd0;

        unique case (i_ctrl.wb_sel)
            WB_ALU: o_rf_rd_data = i_alu_result;
            WB_MEM: o_rf_rd_data = i_mem_rdata;
            WB_PC4: o_rf_rd_data = w_pc_plus;
            WB_CSR: o_rf_rd_data = i_csr_rdata;
            default: o_rf_rd_data = 32'd0;
        endcase
    end

    assign o_rf_wr_en   = i_valid && i_ctrl.reg_write;
    assign o_rf_rd_addr = i_rd_addr;

endmodule : k10_writeback
