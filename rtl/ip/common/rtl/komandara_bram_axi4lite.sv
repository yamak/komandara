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
// Komandara — BRAM with AXI4-Lite Slave Interface
// ============================================================================
// Wraps komandara_bram with an AXI4-Lite slave interface for use as a
// memory block in the SoC interconnect.
//
// Parameters:
//   MEM_ADDR_WIDTH — Determines memory depth: 2^MEM_ADDR_WIDTH words.
//   AXI_ADDR_WIDTH — AXI address width (typically 32).
//   AXI_DATA_WIDTH — AXI data width (typically 32).
//   INIT_FILE      — Hex file for BRAM initialisation.
//
// Shared infrastructure — not tied to any specific core version.
// ============================================================================

module komandara_bram_axi4lite #(
    parameter int MEM_ADDR_WIDTH = 14,   // 2^14 words = 64 KB
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter     INIT_FILE      = ""
)(
    input  logic                          i_clk,
    input  logic                          i_rst_n,

    // AXI4-Lite Slave Interface
    // Write Address
    input  logic [AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  logic [2:0]                    s_axi_awprot,
    input  logic                          s_axi_awvalid,
    output logic                          s_axi_awready,
    // Write Data
    input  logic [AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  logic [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic                          s_axi_wvalid,
    output logic                          s_axi_wready,
    // Write Response
    output logic [1:0]                    s_axi_bresp,
    output logic                          s_axi_bvalid,
    input  logic                          s_axi_bready,
    // Read Address
    input  logic [AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  logic [2:0]                    s_axi_arprot,
    input  logic                          s_axi_arvalid,
    output logic                          s_axi_arready,
    // Read Data
    output logic [AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output logic [1:0]                    s_axi_rresp,
    output logic                          s_axi_rvalid,
    input  logic                          s_axi_rready
);

    localparam int BYTES = AXI_DATA_WIDTH / 8;

    // -----------------------------------------------------------------------
    // State machine for AXI4-Lite slave protocol
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WR_DATA,      // Waiting for write data (AW arrived first)
        ST_WR_ADDR,      // Waiting for write address (W arrived first)
        ST_WR_RESP,      // Sending write response
        ST_RD_DATA       // Reading from BRAM, sending read response
    } state_e;

    state_e r_state, w_state_next;

    logic [MEM_ADDR_WIDTH-1:0] r_addr;
    logic [AXI_DATA_WIDTH-1:0] r_wdata;
    logic [(AXI_DATA_WIDTH/8)-1:0] r_wstrb;

    // -----------------------------------------------------------------------
    // BRAM instance
    // -----------------------------------------------------------------------
    logic                         w_bram_req;
    logic                         w_bram_we;
    logic [MEM_ADDR_WIDTH-1:0]    w_bram_addr;
    logic [AXI_DATA_WIDTH-1:0]    w_bram_wdata;
    logic [(AXI_DATA_WIDTH/8)-1:0] w_bram_wstrb;
    logic                         w_bram_rvalid;
    logic [AXI_DATA_WIDTH-1:0]    w_bram_rdata;

    komandara_bram #(
        .ADDR_WIDTH (MEM_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .INIT_FILE  (INIT_FILE)
    ) u_bram (
        .i_clk    (i_clk),
        .i_req    (w_bram_req),
        .i_we     (w_bram_we),
        .i_addr   (w_bram_addr),
        .i_wdata  (w_bram_wdata),
        .i_wstrb  (w_bram_wstrb),
        .o_rvalid (w_bram_rvalid),
        .o_rdata  (w_bram_rdata)
    );

    // Address mapping: AXI byte address → BRAM word address
    // Drop lower 2 bits (word-aligned) and mask to MEM_ADDR_WIDTH
    logic [MEM_ADDR_WIDTH-1:0] w_aw_word_addr;
    logic [MEM_ADDR_WIDTH-1:0] w_ar_word_addr;
    assign w_aw_word_addr = s_axi_awaddr[MEM_ADDR_WIDTH+1:2];
    assign w_ar_word_addr = s_axi_araddr[MEM_ADDR_WIDTH+1:2];

    // -----------------------------------------------------------------------
    // Read response register
    // -----------------------------------------------------------------------
    logic                         r_rd_pending;
    logic [AXI_DATA_WIDTH-1:0]    r_rd_data;

    // -----------------------------------------------------------------------
    // FSM — combinational
    // -----------------------------------------------------------------------
    always_comb begin
        w_state_next     = r_state;
        w_bram_req       = 1'b0;
        w_bram_we        = 1'b0;
        w_bram_addr      = r_addr;
        w_bram_wdata     = r_wdata;
        w_bram_wstrb     = r_wstrb;

        s_axi_awready    = 1'b0;
        s_axi_wready     = 1'b0;
        s_axi_bresp      = 2'b00;
        s_axi_bvalid     = 1'b0;
        s_axi_arready    = 1'b0;
        s_axi_rdata      = r_rd_data;
        s_axi_rresp      = 2'b00;
        s_axi_rvalid     = 1'b0;

        unique case (r_state)
            ST_IDLE: begin
                // Prioritize writes over reads
                if (s_axi_awvalid && s_axi_wvalid) begin
                    // Both AW and W arrive simultaneously
                    s_axi_awready = 1'b1;
                    s_axi_wready  = 1'b1;
                    w_bram_req    = 1'b1;
                    w_bram_we     = 1'b1;
                    w_bram_addr   = w_aw_word_addr;
                    w_bram_wdata  = s_axi_wdata;
                    w_bram_wstrb  = s_axi_wstrb;
                    w_state_next  = ST_WR_RESP;
                end else if (s_axi_awvalid) begin
                    s_axi_awready = 1'b1;
                    w_state_next  = ST_WR_DATA;
                end else if (s_axi_wvalid) begin
                    s_axi_wready  = 1'b1;
                    w_state_next  = ST_WR_ADDR;
                end else if (s_axi_arvalid) begin
                    s_axi_arready = 1'b1;
                    w_bram_req    = 1'b1;
                    w_bram_we     = 1'b0;
                    w_bram_addr   = w_ar_word_addr;
                    w_state_next  = ST_RD_DATA;
                end
            end

            ST_WR_DATA: begin
                // AW arrived, waiting for W
                if (s_axi_wvalid) begin
                    s_axi_wready  = 1'b1;
                    w_bram_req    = 1'b1;
                    w_bram_we     = 1'b1;
                    w_bram_addr   = r_addr;
                    w_bram_wdata  = s_axi_wdata;
                    w_bram_wstrb  = s_axi_wstrb;
                    w_state_next  = ST_WR_RESP;
                end
            end

            ST_WR_ADDR: begin
                // W arrived, waiting for AW
                if (s_axi_awvalid) begin
                    s_axi_awready = 1'b1;
                    w_bram_req    = 1'b1;
                    w_bram_we     = 1'b1;
                    w_bram_addr   = w_aw_word_addr;
                    w_bram_wdata  = r_wdata;
                    w_bram_wstrb  = r_wstrb;
                    w_state_next  = ST_WR_RESP;
                end
            end

            ST_WR_RESP: begin
                // Send write response
                s_axi_bvalid = 1'b1;
                s_axi_bresp  = 2'b00;  // OKAY
                if (s_axi_bready) begin
                    w_state_next = ST_IDLE;
                end
            end

            ST_RD_DATA: begin
                // Wait for BRAM read data (1 cycle latency)
                if (r_rd_pending) begin
                    s_axi_rvalid = 1'b1;
                    s_axi_rdata  = r_rd_data;
                    s_axi_rresp  = 2'b00;  // OKAY
                    if (s_axi_rready) begin
                        w_state_next = ST_IDLE;
                    end
                end
            end

            default: w_state_next = ST_IDLE;
        endcase
    end

    // -----------------------------------------------------------------------
    // FSM — sequential
    // -----------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state      <= ST_IDLE;
            r_addr       <= '0;
            r_wdata      <= '0;
            r_wstrb      <= '0;
            r_rd_pending <= 1'b0;
            r_rd_data    <= '0;
        end else begin
            r_state <= w_state_next;

            // Latch address on AW accept
            if (r_state == ST_IDLE && s_axi_awvalid) begin
                r_addr <= w_aw_word_addr;
            end else if (r_state == ST_WR_ADDR && s_axi_awvalid) begin
                r_addr <= w_aw_word_addr;
            end

            // Latch write data on W accept (when AW arrives first)
            if (r_state == ST_IDLE && s_axi_wvalid && !s_axi_awvalid) begin
                r_wdata <= s_axi_wdata;
                r_wstrb <= s_axi_wstrb;
            end

            // Latch read address on AR accept
            if (r_state == ST_IDLE && s_axi_arvalid && !s_axi_awvalid && !s_axi_wvalid) begin
                r_addr <= w_ar_word_addr;
            end

            // Capture BRAM read data
            if (w_bram_rvalid) begin
                r_rd_data    <= w_bram_rdata;
                r_rd_pending <= 1'b1;
            end
            if (r_state == ST_RD_DATA && s_axi_rvalid && s_axi_rready) begin
                r_rd_pending <= 1'b0;
            end
            if (r_state == ST_IDLE) begin
                r_rd_pending <= 1'b0;
            end
        end
    end

endmodule : komandara_bram_axi4lite
