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
// K10 — Load / Store Unit  (LSU)
// ============================================================================
// Standalone unit that handles all data-memory bus transactions:
//
//   • Aligned loads / stores        — single bus access.
//   • Unaligned loads / stores      — transparently split into two
//     consecutive aligned bus accesses when the access crosses a
//     4-byte word boundary.
//   • Atomic (AMO / LR / SC)        — multi-cycle read-modify-write
//     sequences.  Atomics must be naturally aligned (word-aligned);
//     misalignment is detected by the wrapper (k10_memory).
//
// Bus protocol (simple valid/ready):
//   req + addr + we + wdata + wstrb  →  gnt  →  rvalid + rdata / err
//   The core holds `req` until `gnt`.  `rvalid` arrives in a later cycle.
//
// Sign extension on loads is performed internally so that the output
// `o_rdata` is the final value ready for the register file.
// ============================================================================

module k10_lsu
  import komandara_k10_pkg::*;
(
    input  logic        i_clk,
    input  logic        i_rst_n,

    // ---- Command interface (from MEM stage) ----
    input  logic        i_valid,       // Operation pending
    input  logic        i_read,        // Load
    input  logic        i_write,       // Store
    input  ls_size_e    i_size,        // Byte / Half / Word
    input  logic        i_is_atomic,   // AMO / LR / SC
    input  amo_op_e     i_amo_op,      // AMO operation type
    input  logic [31:0] i_addr,        // Effective address
    input  logic [31:0] i_wdata,       // Store data (rs2, forwarded)

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

    // ---- Result ----
    output logic [31:0] o_rdata,       // Sign-extended load result
    output logic        o_busy,        // Stall upstream
    output logic        o_err          // Bus error (valid when done)
);

    // =====================================================================
    // Address decomposition
    // =====================================================================
    logic [1:0]  w_offset;
    logic [31:0] w_addr_lo;       // Lower word-aligned address
    logic [31:0] w_addr_hi;       // Upper word-aligned address
    logic [4:0]  w_shift_amt;     // offset * 8

    assign w_offset    = i_addr[1:0];
    assign w_addr_lo   = {i_addr[31:2], 2'b00};
    assign w_addr_hi   = w_addr_lo + 32'd4;
    assign w_shift_amt = {w_offset, 3'b000};   // 0, 8, 16 or 24

    // =====================================================================
    // Boundary-crossing detection
    // =====================================================================
    //  Byte  — never crosses.
    //  Half  — crosses only when offset == 3  (bytes 3,4).
    //  Word  — crosses when offset != 0.
    // =====================================================================
    logic w_crosses;
    always_comb begin
        w_crosses = 1'b0;
        unique case (i_size)
            LS_BYTE, LS_BYTE_U: w_crosses = 1'b0;
            LS_HALF, LS_HALF_U: w_crosses = (w_offset == 2'b11);
            LS_WORD:            w_crosses = (w_offset != 2'b00);
            default:            w_crosses = 1'b0;
        endcase
    end

    logic w_is_mem_op;
    assign w_is_mem_op = i_valid && (i_read || i_write || i_is_atomic);

    // =====================================================================
    // Store-data preparation  (zero-extended, then shifted to byte lanes)
    // =====================================================================
    logic [31:0] w_wdata_raw;
    logic [3:0]  w_wstrb_raw;

    always_comb begin
        unique case (i_size)
            LS_BYTE, LS_BYTE_U: begin
                w_wdata_raw = {24'd0, i_wdata[7:0]};
                w_wstrb_raw = 4'b0001;
            end
            LS_HALF, LS_HALF_U: begin
                w_wdata_raw = {16'd0, i_wdata[15:0]};
                w_wstrb_raw = 4'b0011;
            end
            default: begin   // LS_WORD
                w_wdata_raw = i_wdata;
                w_wstrb_raw = 4'b1111;
            end
        endcase
    end

    // Shift into byte lanes — lower and upper 32-bit words
    logic [63:0] w_store_shifted;
    logic [7:0]  w_strb_shifted;

    assign w_store_shifted = {32'd0, w_wdata_raw} << w_shift_amt;
    assign w_strb_shifted  = {4'd0,  w_wstrb_raw} << w_offset;

    logic [31:0] w_lo_wdata, w_hi_wdata;
    logic [3:0]  w_lo_wstrb, w_hi_wstrb;

    assign w_lo_wdata = w_store_shifted[31:0];
    assign w_lo_wstrb = w_strb_shifted[3:0];
    assign w_hi_wdata = w_store_shifted[63:32];
    assign w_hi_wstrb = w_strb_shifted[7:4];

    // =====================================================================
    // FSM
    // =====================================================================
    typedef enum logic [2:0] {
        LSU_IDLE,
        LSU_ALIGNED,       // Single aligned (or non-crossing) access
        LSU_SPLIT_LO,      // First half of boundary-crossing access
        LSU_SPLIT_HI,      // Second half of boundary-crossing access
        LSU_AMO_READ,      // AMO / LR: read phase
        LSU_AMO_WRITE      // AMO / SC: write phase
    } lsu_state_e;

    lsu_state_e  r_state, w_state_next;
    logic        r_granted;         // Current bus request has been granted
    logic [31:0] r_lo_rdata;        // Captured lower-word (split) / AMO read data
    logic        r_err_acc;         // Accumulated error for split accesses

    // LR / SC reservation
    logic        r_reservation_valid;
    logic [31:0] r_reservation_addr;

    // =====================================================================
    // SC fail condition
    // =====================================================================
    logic w_sc_fail;
    assign w_sc_fail = (i_amo_op == AMO_SC) &&
                       (!r_reservation_valid ||
                        (r_reservation_addr != w_addr_lo));

    // =====================================================================
    // AMO modify result  (uses captured r_lo_rdata from AMO_READ)
    // =====================================================================
    logic [31:0] w_amo_result;

    always_comb begin
        w_amo_result = 32'd0;
        unique case (i_amo_op)
            AMO_SWAP: w_amo_result = i_wdata;
            AMO_ADD:  w_amo_result = r_lo_rdata + i_wdata;
            AMO_XOR:  w_amo_result = r_lo_rdata ^ i_wdata;
            AMO_AND:  w_amo_result = r_lo_rdata & i_wdata;
            AMO_OR:   w_amo_result = r_lo_rdata | i_wdata;
            AMO_MIN:  w_amo_result = ($signed(r_lo_rdata) < $signed(i_wdata))
                                     ? r_lo_rdata : i_wdata;
            AMO_MAX:  w_amo_result = ($signed(r_lo_rdata) > $signed(i_wdata))
                                     ? r_lo_rdata : i_wdata;
            AMO_MINU: w_amo_result = (r_lo_rdata < i_wdata)
                                     ? r_lo_rdata : i_wdata;
            AMO_MAXU: w_amo_result = (r_lo_rdata > i_wdata)
                                     ? r_lo_rdata : i_wdata;
            default:  w_amo_result = i_wdata;
        endcase
    end

    // =====================================================================
    // FSM — combinational
    // =====================================================================
    logic w_done;          // Operation completed this cycle

    always_comb begin
        w_state_next = r_state;
        o_dbus_req   = 1'b0;
        o_dbus_we    = 1'b0;
        o_dbus_addr  = w_addr_lo;
        o_dbus_wdata = w_lo_wdata;
        o_dbus_wstrb = w_lo_wstrb;
        w_done       = 1'b0;

        unique case (r_state)
            // =============================================================
            LSU_IDLE: begin
                if (w_is_mem_op) begin
                    if (i_is_atomic) begin
                        if (i_amo_op == AMO_SC) begin
                            if (w_sc_fail) begin
                                // SC fails immediately — no bus access
                                w_done = 1'b1;
                            end else begin
                                // SC succeeds — issue write
                                w_state_next = LSU_AMO_WRITE;
                                o_dbus_req   = 1'b1;
                                o_dbus_we    = 1'b1;
                                o_dbus_addr  = w_addr_lo;
                                o_dbus_wdata = i_wdata;
                                o_dbus_wstrb = 4'b1111;
                            end
                        end else begin
                            // LR or AMO*: read first
                            w_state_next = LSU_AMO_READ;
                            o_dbus_req   = 1'b1;
                            o_dbus_we    = 1'b0;
                            o_dbus_addr  = w_addr_lo;
                        end
                    end else if (w_crosses) begin
                        // Unaligned crossing: lower-word access first
                        w_state_next = LSU_SPLIT_LO;
                        o_dbus_req   = 1'b1;
                        o_dbus_we    = i_write;
                        o_dbus_addr  = w_addr_lo;
                        o_dbus_wdata = w_lo_wdata;
                        o_dbus_wstrb = w_lo_wstrb;
                    end else begin
                        // Aligned or non-crossing misaligned: single access
                        w_state_next = LSU_ALIGNED;
                        o_dbus_req   = 1'b1;
                        o_dbus_we    = i_write;
                        o_dbus_addr  = w_addr_lo;
                        o_dbus_wdata = w_lo_wdata;
                        o_dbus_wstrb = w_lo_wstrb;
                    end
                end
            end

            // =============================================================
            LSU_ALIGNED: begin
                if (!r_granted) begin
                    o_dbus_req   = 1'b1;
                    o_dbus_we    = i_write;
                    o_dbus_addr  = w_addr_lo;
                    o_dbus_wdata = w_lo_wdata;
                    o_dbus_wstrb = w_lo_wstrb;
                end
                if (i_dbus_rvalid) begin
                    w_state_next = LSU_IDLE;
                    w_done       = 1'b1;
                end
            end

            // =============================================================
            LSU_SPLIT_LO: begin
                if (!r_granted) begin
                    o_dbus_req   = 1'b1;
                    o_dbus_we    = i_write;
                    o_dbus_addr  = w_addr_lo;
                    o_dbus_wdata = w_lo_wdata;
                    o_dbus_wstrb = w_lo_wstrb;
                end
                if (i_dbus_rvalid) begin
                    // First half done → advance to upper word
                    w_state_next = LSU_SPLIT_HI;
                end
            end

            // =============================================================
            LSU_SPLIT_HI: begin
                if (!r_granted) begin
                    o_dbus_req   = 1'b1;
                    o_dbus_we    = i_write;
                    o_dbus_addr  = w_addr_hi;
                    o_dbus_wdata = w_hi_wdata;
                    o_dbus_wstrb = w_hi_wstrb;
                end
                if (i_dbus_rvalid) begin
                    w_state_next = LSU_IDLE;
                    w_done       = 1'b1;
                end
            end

            // =============================================================
            LSU_AMO_READ: begin
                if (!r_granted) begin
                    o_dbus_req  = 1'b1;
                    o_dbus_we   = 1'b0;
                    o_dbus_addr = w_addr_lo;
                end
                if (i_dbus_rvalid) begin
                    if (i_amo_op == AMO_LR) begin
                        // LR completes after the read
                        w_state_next = LSU_IDLE;
                        w_done       = 1'b1;
                    end else begin
                        // AMO*: proceed to write phase (next cycle)
                        w_state_next = LSU_AMO_WRITE;
                    end
                end
            end

            // =============================================================
            LSU_AMO_WRITE: begin
                if (!r_granted) begin
                    o_dbus_req   = 1'b1;
                    o_dbus_we    = 1'b1;
                    o_dbus_addr  = w_addr_lo;
                    o_dbus_wdata = (i_amo_op == AMO_SC) ? i_wdata : w_amo_result;
                    o_dbus_wstrb = 4'b1111;
                end
                if (i_dbus_rvalid) begin
                    w_state_next = LSU_IDLE;
                    w_done       = 1'b1;
                end
            end

            // =============================================================
            default: w_state_next = LSU_IDLE;
        endcase
    end

    // =====================================================================
    // FSM — sequential
    // =====================================================================
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state             <= LSU_IDLE;
            r_granted           <= 1'b0;
            r_lo_rdata          <= 32'd0;
            r_err_acc           <= 1'b0;
            r_reservation_valid <= 1'b0;
            r_reservation_addr  <= 32'd0;
        end else begin
            r_state <= w_state_next;

            // ----- Grant tracking -----
            // Priority: rvalid > gnt > state-change (clear)
            if (i_dbus_rvalid) begin
                r_granted <= 1'b0;
            end else if (i_dbus_gnt && o_dbus_req) begin
                r_granted <= 1'b1;
            end else if (r_state != w_state_next) begin
                // Entering a new state → need fresh grant
                r_granted <= 1'b0;
            end

            // ----- Capture lower-word / AMO read data -----
            if ((r_state == LSU_SPLIT_LO || r_state == LSU_AMO_READ) &&
                 i_dbus_rvalid) begin
                r_lo_rdata <= i_dbus_rdata;
            end

            // ----- Error accumulation for split accesses -----
            if (w_state_next == LSU_IDLE) begin
                r_err_acc <= 1'b0;
            end else if (r_state == LSU_SPLIT_LO && i_dbus_rvalid && i_dbus_err) begin
                r_err_acc <= 1'b1;
            end

            // ----- LR sets reservation -----
            if (r_state == LSU_AMO_READ && i_dbus_rvalid &&
                i_amo_op == AMO_LR) begin
                r_reservation_valid <= 1'b1;
                r_reservation_addr  <= w_addr_lo;
            end

            // ----- SC clears reservation (regardless of success) -----
            if (r_state == LSU_AMO_WRITE && i_dbus_rvalid &&
                i_amo_op == AMO_SC) begin
                r_reservation_valid <= 1'b0;
            end
            // SC-fail path (handled in IDLE, no bus) also clears
            if (r_state == LSU_IDLE && w_is_mem_op && i_is_atomic &&
                i_amo_op == AMO_SC && w_sc_fail) begin
                r_reservation_valid <= 1'b0;
            end

            // ----- Normal store to reservation address clears it -----
            if (w_is_mem_op && i_write && !i_is_atomic &&
                r_reservation_valid &&
                w_addr_lo == r_reservation_addr) begin
                r_reservation_valid <= 1'b0;
            end
        end
    end

    // =====================================================================
    // Read-data extraction + sign extension
    // =====================================================================
    //
    // For split (crossing) loads the two 32-bit words are concatenated:
    //   combined = { hi_word , lo_word }           (64 bits)
    // For single-word loads:
    //   combined = { 32'd0   , bus_rdata }
    //
    // The correct bytes are extracted by right-shifting:
    //   shifted = combined >> (offset * 8)
    //   result  = sign_extend( shifted[size-1:0] )
    //
    // =====================================================================
    logic [63:0] w_combined;
    logic [63:0] w_combined_shifted;
    logic [31:0] w_rdata_raw;

    always_comb begin
        if (r_state == LSU_SPLIT_HI) begin
            w_combined = {i_dbus_rdata, r_lo_rdata};
        end else begin
            w_combined = {32'd0, i_dbus_rdata};
        end
    end

    assign w_combined_shifted = w_combined >> w_shift_amt;
    assign w_rdata_raw        = w_combined_shifted[31:0];

    always_comb begin
        o_rdata = 32'd0;

        if (i_is_atomic) begin
            // --- Atomic result ---
            if (i_amo_op == AMO_SC) begin
                o_rdata = w_sc_fail ? 32'd1 : 32'd0;
            end else if (i_amo_op == AMO_LR) begin
                o_rdata = i_dbus_rdata;            // Directly from bus
            end else begin
                o_rdata = r_lo_rdata;              // Original value (AMO_READ)
            end
        end else begin
            // --- Normal load: extract + sign-extend ---
            unique case (i_size)
                LS_BYTE:   o_rdata = {{24{w_rdata_raw[7]}},  w_rdata_raw[7:0]};
                LS_BYTE_U: o_rdata = {24'd0, w_rdata_raw[7:0]};
                LS_HALF:   o_rdata = {{16{w_rdata_raw[15]}}, w_rdata_raw[15:0]};
                LS_HALF_U: o_rdata = {16'd0, w_rdata_raw[15:0]};
                LS_WORD:   o_rdata = w_rdata_raw;
                default:   o_rdata = w_rdata_raw;
            endcase
        end
    end

    // =====================================================================
    // Busy / Error
    // =====================================================================
    // busy: high while a memory operation is pending but not yet done.
    //       drops to 0 in the same cycle w_done asserts so the pipeline
    //       can capture the result and advance without re-starting the
    //       same access.
    // err : pulsed when the operation completes with an error.
    assign o_busy = w_is_mem_op && !w_done;
    assign o_err  = w_done && ((i_dbus_rvalid && i_dbus_err) || r_err_acc);

    // =====================================================================
    // Assertions (simulation only)
    // =====================================================================
    // synthesis translate_off
    // Inputs must remain stable while the LSU is busy (pipeline stalled).
    // If this fires, the pipeline flush/stall logic has a bug.
`ifdef VERILATOR
    /* verilator lint_off UNUSEDSIGNAL */
`endif
    // synthesis translate_on

endmodule : k10_lsu
