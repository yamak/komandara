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
// K10 — Memory Stage  (MEM)
// ============================================================================
// Thin pipeline-stage wrapper around the Load/Store Unit (k10_lsu).
//
// Responsibilities kept here:
//   • AMO misalignment check — atomics MUST be word-aligned per the
//     RISC-V spec; if not, an exception is raised and the LSU is not
//     invoked.
//   • Routing pipeline-register fields to the LSU ports and collecting
//     the results.
//
// All bus logic (aligned, unaligned split, AMO read-modify-write,
// sign extension) is handled inside the LSU.
// ============================================================================

module k10_memory
  import komandara_k10_pkg::*;
(
    input  logic        i_clk,
    input  logic        i_rst_n,

    // EX/MEM pipeline register values
    input  logic [31:0] i_alu_result,   // Effective address
    input  logic [31:0] i_rs2_data,     // Store data (forwarded)
    input  ctrl_t       i_ctrl,
    input  logic        i_valid,        // Stage active

    // ---- Data bus ----
    output logic        o_dbus_req,
    output logic        o_dbus_we,
    output logic [31:0] o_dbus_addr,
    output logic [31:0] o_dbus_wdata,
    output logic [3:0]  o_dbus_wstrb,
    input  logic        i_dbus_gnt,
    input  logic        i_dbus_rvalid,
    input  logic [31:0] i_dbus_rdata,
    input  logic        i_dbus_err,

    // Outputs
    output logic [31:0] o_mem_rdata,    // Sign-extended load data
    output logic        o_busy,         // Stage still processing (stall upstream)
    output logic        o_mem_err,

    // Misalignment exception outputs  (AMO only — normal misaligned
    // loads/stores are handled transparently by the LSU)
    output logic        o_misalign_load,
    output logic        o_misalign_store
);

    // -----------------------------------------------------------------------
    // AMO misalignment check  (atomics MUST be word-aligned)
    // -----------------------------------------------------------------------
    logic w_amo_misalign;
    assign w_amo_misalign = i_valid && i_ctrl.is_atomic &&
                            (i_alu_result[1:0] != 2'b00);

    // LR → load-address-misaligned; SC / AMO* → store-address-misaligned
    assign o_misalign_load  = w_amo_misalign && (i_ctrl.amo_op == AMO_LR);
    assign o_misalign_store = w_amo_misalign && (i_ctrl.amo_op != AMO_LR);

    // Suppress the LSU when the AMO is misaligned (exception path instead)
    logic w_lsu_valid;
    assign w_lsu_valid = i_valid && !w_amo_misalign;

    // -----------------------------------------------------------------------
    // LSU instance
    // -----------------------------------------------------------------------
    k10_lsu u_lsu (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),

        .i_valid       (w_lsu_valid),
        .i_read        (i_ctrl.mem_read),
        .i_write       (i_ctrl.mem_write),
        .i_size        (i_ctrl.mem_size),
        .i_is_atomic   (i_ctrl.is_atomic),
        .i_amo_op      (i_ctrl.amo_op),
        .i_addr        (i_alu_result),
        .i_wdata       (i_rs2_data),

        .o_dbus_req    (o_dbus_req),
        .o_dbus_we     (o_dbus_we),
        .o_dbus_addr   (o_dbus_addr),
        .o_dbus_wdata  (o_dbus_wdata),
        .o_dbus_wstrb  (o_dbus_wstrb),
        .i_dbus_gnt    (i_dbus_gnt),
        .i_dbus_rvalid (i_dbus_rvalid),
        .i_dbus_rdata  (i_dbus_rdata),
        .i_dbus_err    (i_dbus_err),

        .o_rdata       (o_mem_rdata),
        .o_busy        (o_busy),
        .o_err         (o_mem_err)
    );

endmodule : k10_memory
