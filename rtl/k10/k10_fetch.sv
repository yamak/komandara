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
// K10 — Instruction Fetch Stage  (IF)
// ============================================================================
// Manages the program counter and fetches instructions over a simple bus.
// Includes an instruction realignment buffer for the C (compressed) extension
// so that 16-bit and 32-bit instructions are correctly extracted regardless
// of half-word alignment.
//
// Bus interface:  simple valid/ready request–response.
//   Request:  o_ibus_req / i_ibus_gnt
//   Response: i_ibus_rvalid / i_ibus_rdata
//
// The fetch stage always requests 32-bit aligned reads.  A small buffer
// (one halfword) holds any residual data from the previous fetch so that
// instructions that span two aligned words can be reconstructed.
// ============================================================================

module k10_fetch
  import komandara_k10_pkg::*;
#(
    parameter logic [31:0] BOOT_ADDR = 32'h0000_0000
)(
    input  logic        i_clk,
    input  logic        i_rst_n,

    // Pipeline control  (from hazard unit)
    input  logic        i_stall,
    input  logic        i_flush,

    // Redirect PC
    input  logic        i_pc_set,
    input  logic [31:0] i_pc_target,

    // ---- Instruction bus (to AXI adapter) ----
    output logic        o_ibus_req,
    output logic [31:0] o_ibus_addr,
    input  logic        i_ibus_gnt,
    input  logic        i_ibus_rvalid,
    input  logic [31:0] i_ibus_rdata,
    input  logic        i_ibus_err,

    // ---- Output to IF/ID register ----
    output logic [31:0] o_pc,
    output logic [31:0] o_instr,
    output logic        o_is_compressed,
    output logic        o_valid,
    output logic        o_ibus_err,
    output logic        o_busy              // fetch is still waiting for data
);

    // -----------------------------------------------------------------------
    // PC register
    // -----------------------------------------------------------------------
    logic [31:0] r_pc;
    logic [31:0] w_pc_next;

    // -----------------------------------------------------------------------
    // Instruction alignment buffer
    // -----------------------------------------------------------------------
    // After a 32-bit aligned fetch, the upper halfword may hold the start
    // of the next instruction.  We keep it here.
    logic [15:0] r_buf_data;
    logic        r_buf_valid;

    // Fetch request tracking
    logic        r_fetch_pending;   // request issued, waiting for response
    logic        r_suppress_rsp;    // next rvalid is stale (from pre-redirect)

    // -----------------------------------------------------------------------
    // Derived signals
    // -----------------------------------------------------------------------
    logic [31:0] w_fetch_addr;       // word-aligned fetch address
    logic        w_have_data;        // we have enough data to output an instr

    // Current instruction data (from buffer + fetched word)
    logic [31:0] w_raw_data;         // 32 bits at current PC
    logic        w_is_compressed;    // instruction is 16-bit?
    logic        w_need_second_half; // 32-bit instr spans two words

    // Word-aligned fetch address
    assign w_fetch_addr = {r_pc[31:2], 2'b00};

    // Suppress stale rvalid: treat suppressed rvalid as if it didn't happen.
    logic w_rvalid_eff;
    assign w_rvalid_eff = i_ibus_rvalid && !r_suppress_rsp;

    // -----------------------------------------------------------------------
    // Determine what data we have available
    // -----------------------------------------------------------------------
    always_comb begin
        w_raw_data         = 32'd0;
        w_is_compressed    = 1'b0;
        w_have_data        = 1'b0;
        w_need_second_half = 1'b0;

        if (r_pc[1] == 1'b0) begin
            // PC is word-aligned
            if (r_buf_valid && !r_fetch_pending) begin
                // We just got redirected, buf_valid is stale from old stream
                // Wait for fresh fetch
                w_have_data = 1'b0;
            end else if (w_rvalid_eff) begin
                // Fresh data just arrived
                w_raw_data      = i_ibus_rdata;
                w_is_compressed = (i_ibus_rdata[1:0] != 2'b11);
                w_have_data     = 1'b1;
            end else if (r_buf_valid) begin
                // Buffered upper half from previous fetch could be
                // a compressed instruction or the lower half of a 32-bit
                // We need another fetch for a 32-bit instruction at
                // word-aligned PC, so this shouldn't happen with proper
                // buffer management.
                w_have_data = 1'b0;
            end
        end else begin
            // PC is halfword-aligned (PC[1]=1)
            if (r_buf_valid) begin
                // Upper halfword from previous fetch
                w_is_compressed = (r_buf_data[1:0] != 2'b11);
                if (w_is_compressed) begin
                    // 16-bit instruction — we have it in the buffer
                    w_raw_data  = {16'd0, r_buf_data};
                    w_have_data = 1'b1;
                end else begin
                    // 32-bit instruction spanning two words
                    if (w_rvalid_eff) begin
                        w_raw_data  = {i_ibus_rdata[15:0], r_buf_data};
                        w_have_data = 1'b1;
                    end else begin
                        w_need_second_half = 1'b1;
                        w_have_data        = 1'b0;
                    end
                end
            end else if (w_rvalid_eff) begin
                // No buffer — use upper half of fetched word
                w_is_compressed = (i_ibus_rdata[17:16] != 2'b11);
                if (w_is_compressed) begin
                    w_raw_data  = {16'd0, i_ibus_rdata[31:16]};
                    w_have_data = 1'b1;
                end else begin
                    // Need another word for the lower half
                    w_need_second_half = 1'b1;
                    w_have_data        = 1'b0;
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // Instruction bus request
    // -----------------------------------------------------------------------
    // Issue a fetch when we don't have valid data and aren't already waiting.
    // NOTE: i_stall is intentionally NOT checked here.  The stall prevents PC
    // and buffer from advancing (see the sequential block) but the bus must be
    // free to issue requests — otherwise a deadlock occurs because the hazard
    // unit stalls IF when fetch_busy is high, and fetch_busy stays high until
    // data arrives.
    always_comb begin
        o_ibus_req  = 1'b0;
        o_ibus_addr = w_fetch_addr;

        if (i_flush || i_pc_set) begin
            // After redirect, need to fetch from new PC
            o_ibus_req  = !r_fetch_pending;
            o_ibus_addr = {(i_pc_set ? i_pc_target[31:2] : r_pc[31:2]), 2'b00};
        end else if (w_need_second_half && !r_fetch_pending) begin
            // 32-bit instruction spans two words — fetch the next word
            // NOTE: This must come BEFORE the general !w_have_data check
            // because w_need_second_half implies !w_have_data, and we need
            // w_fetch_addr + 4 (the next word) rather than w_fetch_addr.
            o_ibus_req  = 1'b1;
            o_ibus_addr = w_fetch_addr + 32'd4;
        end else if (!w_have_data && !r_fetch_pending) begin
            o_ibus_req  = 1'b1;
            o_ibus_addr = w_fetch_addr;
        end
    end

    // -----------------------------------------------------------------------
    // Next PC
    // -----------------------------------------------------------------------
    always_comb begin
        w_pc_next = r_pc;

        if (i_pc_set) begin
            w_pc_next = i_pc_target;
        end else if (w_have_data && !i_stall) begin
            w_pc_next = r_pc + (w_is_compressed ? 32'd2 : 32'd4);
        end
    end

    // -----------------------------------------------------------------------
    // Outputs
    // -----------------------------------------------------------------------
    assign o_pc            = r_pc;
    assign o_instr         = w_raw_data;
    assign o_is_compressed = w_is_compressed;
    assign o_valid         = w_have_data && !i_flush && !i_pc_set;
    assign o_ibus_err      = i_ibus_rvalid && i_ibus_err;
    assign o_busy          = !w_have_data && !i_flush;

    // -----------------------------------------------------------------------
    // Sequential: PC, buffer, fetch-pending
    // -----------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_pc            <= BOOT_ADDR;
            r_buf_data      <= 16'd0;
            r_buf_valid     <= 1'b0;
            r_fetch_pending <= 1'b0;
            r_suppress_rsp  <= 1'b0;
        end else begin
            // ---- PC ----
            if (i_pc_set) begin
                r_pc <= i_pc_target;
            end else if (w_have_data && !i_stall) begin
                r_pc <= w_pc_next;
            end

            // ---- Stale response suppression ----
            // When a redirect occurs while a fetch is pending, the
            // in-flight response is stale.  Set r_suppress_rsp so
            // the next rvalid is ignored.
            if ((i_pc_set || i_flush) && r_fetch_pending) begin
                r_suppress_rsp <= 1'b1;
            end else if (i_ibus_rvalid && r_suppress_rsp) begin
                r_suppress_rsp <= 1'b0;
            end

            // ---- Fetch pending tracking ----
            if (o_ibus_req && i_ibus_gnt) begin
                r_fetch_pending <= 1'b1;
            end
            if (i_ibus_rvalid) begin
                r_fetch_pending <= 1'b0;
            end

            // ---- Buffer management ----
            if (i_pc_set || i_flush) begin
                // Invalidate buffer on redirect
                r_buf_valid <= 1'b0;
                r_buf_data  <= 16'd0;
            end else if (w_have_data && !i_stall) begin
                if (r_pc[1] == 1'b0) begin
                    // Word-aligned PC
                    if (w_is_compressed) begin
                        // Used lower 16 bits; buffer upper 16 bits
                        r_buf_valid <= w_rvalid_eff;
                        r_buf_data  <= w_rvalid_eff ? i_ibus_rdata[31:16] : 16'd0;
                    end else begin
                        // Used full 32 bits; no leftover
                        r_buf_valid <= 1'b0;
                    end
                end else begin
                    // Halfword-aligned PC
                    if (w_is_compressed) begin
                        // Used buffered 16 bits; nothing to save (fetch not consumed)
                        r_buf_valid <= 1'b0;
                    end else begin
                        // Used buffer + lower 16 of new fetch; save upper 16
                        r_buf_valid <= w_rvalid_eff;
                        r_buf_data  <= w_rvalid_eff ? i_ibus_rdata[31:16] : 16'd0;
                    end
                end
            end else if (w_rvalid_eff && !w_have_data) begin
                // Data arrived but we can't output yet (e.g. need second word)
                // Buffer the relevant halfword for the next fetch.
                if (r_pc[1] == 1'b0) begin
                    // Word-aligned: buffer upper half for next instruction
                    r_buf_valid <= 1'b1;
                    r_buf_data  <= i_ibus_rdata[31:16];
                end else begin
                    // Halfword-aligned: the upper half of the fetched word is
                    // the start of a 32-bit instruction at PC.  Save it so
                    // that the next fetch (of the following word) can combine
                    // it to form the full 32-bit instruction.
                    r_buf_valid <= 1'b1;
                    r_buf_data  <= i_ibus_rdata[31:16];
                end
            end
        end
    end

endmodule : k10_fetch
