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
// Komandara - AXI4-Lite Slave
// ============================================================================
// A fully-compliant AXI4-Lite slave with skid buffers on all input channels
// (AW, W, AR) for full throughput. Contains a simple register file for
// verification purposes.
//
// Shared infrastructure — not tied to any specific core version.
//
// Features:
//   - Skid buffers on AW, W, AR channels (break ready timing paths)
//   - Back-to-back write/read with zero bubble
//   - Independent read and write paths
//   - Byte-lane write strobes
// ============================================================================

module komandara_axi4lite_slave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int REG_COUNT  = 16   // Number of internal registers
)(
    input  logic                      clk_i,
    input  logic                      rst_ni,

    // ====================================================================
    // AXI4-Lite Slave Interface
    // ====================================================================

    // Write Address Channel
    input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr_i,
    input  logic [2:0]                s_axi_awprot_i,
    input  logic                      s_axi_awvalid_i,
    output logic                      s_axi_awready_o,

    // Write Data Channel
    input  logic [DATA_WIDTH-1:0]     s_axi_wdata_i,
    input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb_i,
    input  logic                      s_axi_wvalid_i,
    output logic                      s_axi_wready_o,

    // Write Response Channel
    output logic [1:0]                s_axi_bresp_o,
    output logic                      s_axi_bvalid_o,
    input  logic                      s_axi_bready_i,

    // Read Address Channel
    input  logic [ADDR_WIDTH-1:0]     s_axi_araddr_i,
    input  logic [2:0]                s_axi_arprot_i,
    input  logic                      s_axi_arvalid_i,
    output logic                      s_axi_arready_o,

    // Read Data Channel
    output logic [DATA_WIDTH-1:0]     s_axi_rdata_o,
    output logic [1:0]                s_axi_rresp_o,
    output logic                      s_axi_rvalid_o,
    input  logic                      s_axi_rready_i
);

    import komandara_axi4lite_pkg::*;

    // --------------------------------------------------------
    // Local parameters
    // --------------------------------------------------------
    localparam int STRB_WIDTH    = DATA_WIDTH / 8;
    localparam int REG_IDX_BITS  = $clog2(REG_COUNT);
    localparam int BYTE_OFF_BITS = $clog2(STRB_WIDTH);

    // --------------------------------------------------------
    // Skid-buffered channel signals
    // --------------------------------------------------------

    // Write Address Channel (post skid buffer)
    logic [ADDR_WIDTH+3-1:0] w_aw_skid_data;
    logic                    w_aw_skid_valid;
    logic                    w_aw_skid_ready;
    logic [ADDR_WIDTH-1:0]   w_aw_addr;
    logic [2:0]              w_aw_prot;

    // Write Data Channel (post skid buffer)
    logic [DATA_WIDTH+STRB_WIDTH-1:0] w_w_skid_data;
    logic                             w_w_skid_valid;
    logic                             w_w_skid_ready;
    logic [DATA_WIDTH-1:0]            w_w_data;
    logic [STRB_WIDTH-1:0]            w_w_strb;

    // Read Address Channel (post skid buffer)
    logic [ADDR_WIDTH+3-1:0] w_ar_skid_data;
    logic                    w_ar_skid_valid;
    logic                    w_ar_skid_ready;
    logic [ADDR_WIDTH-1:0]   w_ar_addr;
    logic [2:0]              w_ar_prot;

    // --------------------------------------------------------
    // Skid Buffers — Input Channels
    // --------------------------------------------------------

    // AW Skid Buffer
    komandara_skid_buffer #(
        .DATA_WIDTH (ADDR_WIDTH + 3)
    ) u_aw_skid (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .s_data_i  ({s_axi_awprot_i, s_axi_awaddr_i}),
        .s_valid_i (s_axi_awvalid_i),
        .s_ready_o (s_axi_awready_o),
        .m_data_o  (w_aw_skid_data),
        .m_valid_o (w_aw_skid_valid),
        .m_ready_i (w_aw_skid_ready)
    );
    assign {w_aw_prot, w_aw_addr} = w_aw_skid_data;

    // W Skid Buffer
    komandara_skid_buffer #(
        .DATA_WIDTH (DATA_WIDTH + STRB_WIDTH)
    ) u_w_skid (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .s_data_i  ({s_axi_wstrb_i, s_axi_wdata_i}),
        .s_valid_i (s_axi_wvalid_i),
        .s_ready_o (s_axi_wready_o),
        .m_data_o  (w_w_skid_data),
        .m_valid_o (w_w_skid_valid),
        .m_ready_i (w_w_skid_ready)
    );
    assign {w_w_strb, w_w_data} = w_w_skid_data;

    // AR Skid Buffer
    komandara_skid_buffer #(
        .DATA_WIDTH (ADDR_WIDTH + 3)
    ) u_ar_skid (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .s_data_i  ({s_axi_arprot_i, s_axi_araddr_i}),
        .s_valid_i (s_axi_arvalid_i),
        .s_ready_o (s_axi_arready_o),
        .m_data_o  (w_ar_skid_data),
        .m_valid_o (w_ar_skid_valid),
        .m_ready_i (w_ar_skid_ready)
    );
    assign {w_ar_prot, w_ar_addr} = w_ar_skid_data;

    // --------------------------------------------------------
    // Register File
    // --------------------------------------------------------
    logic [DATA_WIDTH-1:0] r_reg_file [REG_COUNT];

    // --------------------------------------------------------
    // Write Register Index
    // --------------------------------------------------------
    logic [REG_IDX_BITS-1:0] w_wr_reg_idx;
    assign w_wr_reg_idx = w_aw_addr[BYTE_OFF_BITS +: REG_IDX_BITS];

    // --------------------------------------------------------
    // Write Logic
    // --------------------------------------------------------
    // Write fires when both AW and W are available AND
    // B channel is free (or being consumed this cycle).
    logic w_wr_en;
    assign w_wr_en = w_aw_skid_valid && w_w_skid_valid
                   && (!s_axi_bvalid_o || s_axi_bready_i);

    // Consume both AW and W together
    assign w_aw_skid_ready = w_wr_en;
    assign w_w_skid_ready  = w_wr_en;

    // Register file write
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < REG_COUNT; i++) begin
                r_reg_file[i] <= '0;
            end
        end else if (w_wr_en) begin
            for (int b = 0; b < STRB_WIDTH; b++) begin
                if (w_w_strb[b]) begin
                    r_reg_file[w_wr_reg_idx][b*8 +: 8] <= w_w_data[b*8 +: 8];
                end
            end
        end
    end

    // --------------------------------------------------------
    // Write Response (B Channel)
    // --------------------------------------------------------
    // Registered output: bvalid asserted 1 cycle after wr_en.
    // Back-to-back: if bvalid && bready && wr_en, bvalid stays high
    // (wr_en's set overrides bready's clear — last NBA wins).
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s_axi_bvalid_o <= 1'b0;
            s_axi_bresp_o  <= 2'b00;
        end else begin
            if (s_axi_bvalid_o && s_axi_bready_i) begin
                s_axi_bvalid_o <= 1'b0;
            end
            if (w_wr_en) begin
                s_axi_bvalid_o <= 1'b1;
                s_axi_bresp_o  <= AXI_RESP_OKAY;
            end
        end
    end

    // --------------------------------------------------------
    // Read Register Index
    // --------------------------------------------------------
    logic [REG_IDX_BITS-1:0] w_rd_reg_idx;
    assign w_rd_reg_idx = w_ar_addr[BYTE_OFF_BITS +: REG_IDX_BITS];

    // --------------------------------------------------------
    // Read Logic
    // --------------------------------------------------------
    // Read fires when AR is available AND
    // R channel is free (or being consumed this cycle).
    logic w_rd_en;
    assign w_rd_en = w_ar_skid_valid && (!s_axi_rvalid_o || s_axi_rready_i);

    assign w_ar_skid_ready = w_rd_en;

    // Read Data (R Channel)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            s_axi_rvalid_o <= 1'b0;
            s_axi_rdata_o  <= '0;
            s_axi_rresp_o  <= 2'b00;
        end else begin
            if (s_axi_rvalid_o && s_axi_rready_i) begin
                s_axi_rvalid_o <= 1'b0;
            end
            if (w_rd_en) begin
                s_axi_rvalid_o <= 1'b1;
                s_axi_rresp_o  <= AXI_RESP_OKAY;
                s_axi_rdata_o  <= r_reg_file[w_rd_reg_idx];
            end
        end
    end

    // --------------------------------------------------------
    // Assertions
    // --------------------------------------------------------
    // synthesis translate_off

    // BVALID must not be deasserted without BREADY handshake
    property p_bvalid_stable;
        @(posedge clk_i) disable iff (!rst_ni)
        (s_axi_bvalid_o && !s_axi_bready_i) |=> s_axi_bvalid_o;
    endproperty
    a_bvalid_stable : assert property (p_bvalid_stable)
        else $error("[AXI_SLV] BVALID deasserted without BREADY");

    // RVALID must not be deasserted without RREADY handshake
    property p_rvalid_stable;
        @(posedge clk_i) disable iff (!rst_ni)
        (s_axi_rvalid_o && !s_axi_rready_i) |=> s_axi_rvalid_o;
    endproperty
    a_rvalid_stable : assert property (p_rvalid_stable)
        else $error("[AXI_SLV] RVALID deasserted without RREADY");

    // synthesis translate_on

endmodule
