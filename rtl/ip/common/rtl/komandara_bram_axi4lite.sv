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
// Komandara — BRAM with AXI4-Lite Slave Interface & OBI Native Port
// ============================================================================
// Wraps komandara_bram. Port A is exposed as Native/OBI for Instruction Fetch.
// Port B is wrapped with an AXI4-Lite slave interface for the SoC interconnect.
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

    // Native (OBI-like) Port A (Instruction Fetch)
    input  logic                          s_obi_a_req,
    input  logic                          s_obi_a_we,
    input  logic [AXI_ADDR_WIDTH-1:0]     s_obi_a_addr,
    input  logic [AXI_DATA_WIDTH-1:0]     s_obi_a_wdata,
    input  logic [(AXI_DATA_WIDTH/8)-1:0] s_obi_a_wstrb,
    output logic                          s_obi_a_gnt,
    output logic                          s_obi_a_rvalid,
    output logic [AXI_DATA_WIDTH-1:0]     s_obi_a_rdata,
    output logic                          s_obi_a_err,

    // Native (OBI-like) Port B (Data Bus)
    input  logic                          s_obi_b_req,
    input  logic                          s_obi_b_we,
    input  logic [AXI_ADDR_WIDTH-1:0]     s_obi_b_addr,
    input  logic [AXI_DATA_WIDTH-1:0]     s_obi_b_wdata,
    input  logic [(AXI_DATA_WIDTH/8)-1:0] s_obi_b_wstrb,
    output logic                          s_obi_b_gnt,
    output logic                          s_obi_b_rvalid,
    output logic [AXI_DATA_WIDTH-1:0]     s_obi_b_rdata,
    output logic                          s_obi_b_err,

    // AXI4-Lite Slave Interface Port B (Data Bus)
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
    // Native Port A Mapping (Instruction Fetch)
    // -----------------------------------------------------------------------
    // 1-cycle always ready for OBI
    assign s_obi_a_gnt = s_obi_a_req;
    assign s_obi_a_err = 1'b0;

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
    // BRAM instance (True Dual Port)
    // -----------------------------------------------------------------------
    logic                         w_bram_req_a, w_bram_req_b;
    logic                         w_bram_we_a, w_bram_we_b;
    logic [MEM_ADDR_WIDTH-1:0]    w_bram_addr_a, w_bram_addr_b;
    logic [AXI_DATA_WIDTH-1:0]    w_bram_wdata_a, w_bram_wdata_b;
    logic [(AXI_DATA_WIDTH/8)-1:0] w_bram_wstrb_a, w_bram_wstrb_b;
    logic                         w_bram_rvalid_a, w_bram_rvalid_b;
    logic [AXI_DATA_WIDTH-1:0]    w_bram_rdata_a, w_bram_rdata_b;

    // Bind Port A to OBI Native Bus A
    assign w_bram_req_a   = s_obi_a_req;
    assign w_bram_we_a    = s_obi_a_we;
    assign w_bram_addr_a  = s_obi_a_addr[MEM_ADDR_WIDTH+1:2]; // Word mapping
    assign w_bram_wdata_a = s_obi_a_wdata;
    assign w_bram_wstrb_a = s_obi_a_wstrb;
    assign s_obi_a_rvalid = w_bram_rvalid_a;
    assign s_obi_a_rdata  = w_bram_rdata_a;

    komandara_bram #(
        .ADDR_WIDTH (MEM_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .INIT_FILE  (INIT_FILE)
    ) u_bram (
        .i_clk      (i_clk),
        
        .i_req_a    (w_bram_req_a),
        .i_we_a     (w_bram_we_a),
        .i_addr_a   (w_bram_addr_a),
        .i_wdata_a  (w_bram_wdata_a),
        .i_wstrb_a  (w_bram_wstrb_a),
        .o_rvalid_a (w_bram_rvalid_a),
        .o_rdata_a  (w_bram_rdata_a),
        
        .i_req_b    (w_bram_req_b),
        .i_we_b     (w_bram_we_b),
        .i_addr_b   (w_bram_addr_b),
        .i_wdata_b  (w_bram_wdata_b),
        .i_wstrb_b  (w_bram_wstrb_b),
        .o_rvalid_b (w_bram_rvalid_b),
        .o_rdata_b  (w_bram_rdata_b)
    );

    // Address mapping: AXI byte address → BRAM Port B word address
    logic [MEM_ADDR_WIDTH-1:0] w_aw_word_addr;
    logic [MEM_ADDR_WIDTH-1:0] w_ar_word_addr;
    assign w_aw_word_addr = s_axi_awaddr[MEM_ADDR_WIDTH+1:2];
    assign w_ar_word_addr = s_axi_araddr[MEM_ADDR_WIDTH+1:2];

    // -----------------------------------------------------------------------
    // Port B Read Path Skid Buffer (Hides 1-cycle latency)
    // -----------------------------------------------------------------------
    logic w_skid_ready; // Ignored tracking since we single-issue ARs
    logic w_axi_internal_rvalid;

    komandara_skid_buffer #(
        .DATA_WIDTH (AXI_DATA_WIDTH)
    ) u_rd_skid (
        .clk_i     (i_clk),
        .rst_ni    (i_rst_n),
        .s_data_i  (w_bram_rdata_b),
        .s_valid_i (w_axi_internal_rvalid && (r_state == ST_RD_DATA)), // Only valid for reads initiated by AXI
        .s_ready_o (w_skid_ready),
        .m_data_o  (s_axi_rdata),
        .m_valid_o (s_axi_rvalid),
        .m_ready_i (s_axi_rready)
    );
    assign s_axi_rresp = 2'b00; // OKAY always

    // -----------------------------------------------------------------------
    // Port B Arbitration (OBI > AXI)
    // -----------------------------------------------------------------------
    logic w_axi_req_b, w_axi_we_b;
    logic [MEM_ADDR_WIDTH-1:0] w_axi_addr_b;
    logic [AXI_DATA_WIDTH-1:0] w_axi_wdata_b;
    logic [(AXI_DATA_WIDTH/8)-1:0] w_axi_wstrb_b;

    // Track previous cycle source to route RVALID correctly
    // 0 = OBI B, 1 = AXI
    logic r_port_b_src;

    always_comb begin
        // Default to AXI assignments
        w_bram_req_b   = w_axi_req_b;
        w_bram_we_b    = w_axi_we_b;
        w_bram_addr_b  = w_axi_addr_b;
        w_bram_wdata_b = w_axi_wdata_b;
        w_bram_wstrb_b = w_axi_wstrb_b;
        
        // Strict Priority: OBI B overrides AXI
        if (s_obi_b_req) begin
            w_bram_req_b   = s_obi_b_req;
            w_bram_we_b    = s_obi_b_we;
            w_bram_addr_b  = s_obi_b_addr[MEM_ADDR_WIDTH+1:2];
            w_bram_wdata_b = s_obi_b_wdata;
            w_bram_wstrb_b = s_obi_b_wstrb;
        end
    end

    // OBI GNT immediately if it requests
    assign s_obi_b_gnt = s_obi_b_req;
    assign s_obi_b_err = 1'b0;

    // Route RVALID to the correct source based on the previous cycle's winner
    assign s_obi_b_rvalid        = (r_port_b_src == 1'b0) ? w_bram_rvalid_b : 1'b0;
    assign w_axi_internal_rvalid = (r_port_b_src == 1'b1) ? w_bram_rvalid_b : 1'b0;
    assign s_obi_b_rdata         = w_bram_rdata_b;

    // -----------------------------------------------------------------------
    // FSM — combinational
    // -----------------------------------------------------------------------
    always_comb begin
        w_state_next       = r_state;
        w_axi_req_b        = 1'b0;
        w_axi_we_b         = 1'b0;
        w_axi_addr_b       = r_addr;
        w_axi_wdata_b      = r_wdata;
        w_axi_wstrb_b      = r_wstrb;

        s_axi_awready      = 1'b0;
        s_axi_wready       = 1'b0;
        s_axi_bresp        = 2'b00;
        s_axi_bvalid       = 1'b0;
        s_axi_arready      = 1'b0;

        unique case (r_state)
            ST_IDLE: begin
                // Prioritize writes over reads
                if (s_axi_awvalid && s_axi_wvalid) begin
                    // Both AW and W arrive simultaneously. Delay ready if OBI is dominating port.
                    if (!s_obi_b_req) begin
                        s_axi_awready = 1'b1;
                        s_axi_wready  = 1'b1;
                        w_axi_req_b   = 1'b1;
                        w_axi_we_b    = 1'b1;
                        w_axi_addr_b  = w_aw_word_addr;
                        w_axi_wdata_b = s_axi_wdata;
                        w_axi_wstrb_b = s_axi_wstrb;
                        w_state_next  = ST_WR_RESP;
                    end
                end else if (s_axi_awvalid) begin
                    s_axi_awready = 1'b1;
                    w_state_next  = ST_WR_DATA;
                end else if (s_axi_wvalid) begin
                    s_axi_wready  = 1'b1;
                    w_state_next  = ST_WR_ADDR;
                end else if (s_axi_arvalid) begin
                    if (!s_obi_b_req) begin
                        s_axi_arready = 1'b1;
                        w_axi_req_b   = 1'b1;
                        w_axi_we_b    = 1'b0;
                        w_axi_addr_b  = w_ar_word_addr;
                        w_state_next  = ST_RD_DATA;
                    end
                end
            end

            ST_WR_DATA: begin
                // AW arrived, waiting for W
                if (s_axi_wvalid) begin
                    if (!s_obi_b_req) begin
                        s_axi_wready  = 1'b1;
                        w_axi_req_b   = 1'b1;
                        w_axi_we_b    = 1'b1;
                        w_axi_addr_b  = r_addr;
                        w_axi_wdata_b = s_axi_wdata;
                        w_axi_wstrb_b = s_axi_wstrb;
                        w_state_next  = ST_WR_RESP;
                    end
                end
            end

            ST_WR_ADDR: begin
                // W arrived, waiting for AW
                if (s_axi_awvalid) begin
                    if (!s_obi_b_req) begin
                        s_axi_awready = 1'b1;
                        w_axi_req_b   = 1'b1;
                        w_axi_we_b    = 1'b1;
                        w_axi_addr_b  = w_aw_word_addr;
                        w_axi_wdata_b = r_wdata;
                        w_axi_wstrb_b = r_wstrb;
                        w_state_next  = ST_WR_RESP;
                    end
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
                // The skid buffer receives the 1-cycle latency pulse and outputs it.
                // Complete handshake independently of the physical latency wait step.
                if (s_axi_rvalid && s_axi_rready) begin
                    w_state_next = ST_IDLE;
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
            r_port_b_src <= 1'b0;
        end else begin
            r_state <= w_state_next;
            
            // Latch Port B Request SRC to route RVALID properly next cycle
            // s_obi_b_req ALWAYS takes priority, even if AXI wanted to go.
            if (s_obi_b_req) begin
                r_port_b_src <= 1'b0; // 0 = OBI B
            end else if (w_axi_req_b) begin
                r_port_b_src <= 1'b1; // 1 = AXI
            end


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

            // Latch read address on AR accept just in case
            if (r_state == ST_IDLE && s_axi_arvalid && !s_axi_awvalid && !s_axi_wvalid) begin
                r_addr <= w_ar_word_addr;
            end
        end
    end

endmodule : komandara_bram_axi4lite
