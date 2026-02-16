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
// Komandara — AXI4 Full Master (burst-capable)
// ============================================================================
// Separate write-command/data and read-command/data interfaces.
// Single outstanding transaction per channel.
// Skid buffers on B and R response channels.
// ============================================================================

module komandara_axi4_master #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4
)(
    input  logic clk_i,
    input  logic rst_ni,

    // ====== Write Command (upstream) ======
    input  logic                      wr_cmd_valid_i,
    output logic                      wr_cmd_ready_o,
    input  logic [ID_WIDTH-1:0]       wr_cmd_id_i,
    input  logic [ADDR_WIDTH-1:0]     wr_cmd_addr_i,
    input  logic [7:0]                wr_cmd_len_i,
    input  logic [2:0]                wr_cmd_size_i,
    input  logic [1:0]                wr_cmd_burst_i,

    // ====== Write Data stream (upstream) ======
    input  logic                      wr_data_valid_i,
    output logic                      wr_data_ready_o,
    input  logic [DATA_WIDTH-1:0]     wr_data_i,
    input  logic [(DATA_WIDTH/8)-1:0] wr_strb_i,
    input  logic                      wr_last_i,

    // ====== Write Response (upstream) ======
    output logic                      wr_rsp_valid_o,
    input  logic                      wr_rsp_ready_i,
    output logic [1:0]                wr_rsp_resp_o,
    output logic [ID_WIDTH-1:0]       wr_rsp_id_o,

    // ====== Read Command (upstream) ======
    input  logic                      rd_cmd_valid_i,
    output logic                      rd_cmd_ready_o,
    input  logic [ID_WIDTH-1:0]       rd_cmd_id_i,
    input  logic [ADDR_WIDTH-1:0]     rd_cmd_addr_i,
    input  logic [7:0]                rd_cmd_len_i,
    input  logic [2:0]                rd_cmd_size_i,
    input  logic [1:0]                rd_cmd_burst_i,

    // ====== Read Data stream (upstream) ======
    output logic                      rd_data_valid_o,
    input  logic                      rd_data_ready_i,
    output logic [DATA_WIDTH-1:0]     rd_data_o,
    output logic [1:0]                rd_resp_o,
    output logic                      rd_last_o,
    output logic [ID_WIDTH-1:0]       rd_id_o,

    // ====== AXI4 Master Interface ======
    output logic [ID_WIDTH-1:0]       m_axi_awid_o,
    output logic [ADDR_WIDTH-1:0]     m_axi_awaddr_o,
    output logic [7:0]                m_axi_awlen_o,
    output logic [2:0]                m_axi_awsize_o,
    output logic [1:0]                m_axi_awburst_o,
    output logic                      m_axi_awvalid_o,
    input  logic                      m_axi_awready_i,

    output logic [DATA_WIDTH-1:0]     m_axi_wdata_o,
    output logic [(DATA_WIDTH/8)-1:0] m_axi_wstrb_o,
    output logic                      m_axi_wlast_o,
    output logic                      m_axi_wvalid_o,
    input  logic                      m_axi_wready_i,

    input  logic [ID_WIDTH-1:0]       m_axi_bid_i,
    input  logic [1:0]                m_axi_bresp_i,
    input  logic                      m_axi_bvalid_i,
    output logic                      m_axi_bready_o,

    output logic [ID_WIDTH-1:0]       m_axi_arid_o,
    output logic [ADDR_WIDTH-1:0]     m_axi_araddr_o,
    output logic [7:0]                m_axi_arlen_o,
    output logic [2:0]                m_axi_arsize_o,
    output logic [1:0]                m_axi_arburst_o,
    output logic                      m_axi_arvalid_o,
    input  logic                      m_axi_arready_i,

    input  logic [ID_WIDTH-1:0]       m_axi_rid_i,
    input  logic [DATA_WIDTH-1:0]     m_axi_rdata_i,
    input  logic [1:0]                m_axi_rresp_i,
    input  logic                      m_axi_rlast_i,
    input  logic                      m_axi_rvalid_i,
    output logic                      m_axi_rready_o
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // ====================================================================
    // Write Path
    // ====================================================================
    typedef enum logic [1:0] {WR_IDLE, WR_AW, WR_DATA, WR_RESP} wr_state_e;
    wr_state_e r_wr_state;

    logic r_wr_rsp_pending;

    assign wr_cmd_ready_o  = (r_wr_state == WR_IDLE) && !r_wr_rsp_pending;
    assign wr_data_ready_o = (r_wr_state == WR_DATA) && m_axi_wready_i;

    // AW outputs — registered
    logic [ID_WIDTH-1:0]   r_aw_id;
    logic [ADDR_WIDTH-1:0] r_aw_addr;
    logic [7:0]            r_aw_len;
    logic [2:0]            r_aw_size;
    logic [1:0]            r_aw_burst;

    assign m_axi_awid_o    = r_aw_id;
    assign m_axi_awaddr_o  = r_aw_addr;
    assign m_axi_awlen_o   = r_aw_len;
    assign m_axi_awsize_o  = r_aw_size;
    assign m_axi_awburst_o = r_aw_burst;
    assign m_axi_awvalid_o = (r_wr_state == WR_AW);

    // W outputs — pass-through from upstream
    assign m_axi_wdata_o  = wr_data_i;
    assign m_axi_wstrb_o  = wr_strb_i;
    assign m_axi_wlast_o  = wr_last_i;
    assign m_axi_wvalid_o = (r_wr_state == WR_DATA) && wr_data_valid_i;

    // B channel — skid buffer
    logic [ID_WIDTH+2-1:0] w_b_buf_data;
    logic                  w_b_buf_valid, w_b_buf_ready, w_b_skid_rdy;

    komandara_skid_buffer #(.DATA_WIDTH(ID_WIDTH + 2)) u_b_skid (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_data_i  ({m_axi_bid_i, m_axi_bresp_i}),
        .s_valid_i (m_axi_bvalid_i),
        .s_ready_o (w_b_skid_rdy),
        .m_data_o  (w_b_buf_data),
        .m_valid_o (w_b_buf_valid),
        .m_ready_i (w_b_buf_ready)
    );
    assign m_axi_bready_o = w_b_skid_rdy;

    assign wr_rsp_valid_o = w_b_buf_valid && r_wr_rsp_pending;
    assign wr_rsp_id_o    = w_b_buf_data[2 +: ID_WIDTH];
    assign wr_rsp_resp_o  = w_b_buf_data[1:0];
    assign w_b_buf_ready  = wr_rsp_ready_i && r_wr_rsp_pending;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_wr_state       <= WR_IDLE;
            r_wr_rsp_pending <= 1'b0;
        end else begin
            if (wr_rsp_valid_o && wr_rsp_ready_i)
                r_wr_rsp_pending <= 1'b0;

            case (r_wr_state)
                WR_IDLE: begin
                    if (wr_cmd_valid_i && wr_cmd_ready_o) begin
                        r_aw_id    <= wr_cmd_id_i;
                        r_aw_addr  <= wr_cmd_addr_i;
                        r_aw_len   <= wr_cmd_len_i;
                        r_aw_size  <= wr_cmd_size_i;
                        r_aw_burst <= wr_cmd_burst_i;
                        r_wr_state <= WR_AW;
                        r_wr_rsp_pending <= 1'b1;
                    end
                end
                WR_AW: begin
                    if (m_axi_awvalid_o && m_axi_awready_i)
                        r_wr_state <= WR_DATA;
                end
                WR_DATA: begin
                    if (m_axi_wvalid_o && m_axi_wready_i && wr_last_i)
                        r_wr_state <= WR_IDLE;
                end
                default: r_wr_state <= WR_IDLE;
            endcase
        end
    end

    // ====================================================================
    // Read Path
    // ====================================================================
    typedef enum logic [1:0] {RD_IDLE, RD_AR, RD_DATA} rd_state_e;
    rd_state_e r_rd_state;

    logic r_rd_rsp_pending;

    assign rd_cmd_ready_o = (r_rd_state == RD_IDLE) && !r_rd_rsp_pending;

    // AR outputs — registered
    logic [ID_WIDTH-1:0]   r_ar_id;
    logic [ADDR_WIDTH-1:0] r_ar_addr;
    logic [7:0]            r_ar_len;
    logic [2:0]            r_ar_size;
    logic [1:0]            r_ar_burst;

    assign m_axi_arid_o    = r_ar_id;
    assign m_axi_araddr_o  = r_ar_addr;
    assign m_axi_arlen_o   = r_ar_len;
    assign m_axi_arsize_o  = r_ar_size;
    assign m_axi_arburst_o = r_ar_burst;
    assign m_axi_arvalid_o = (r_rd_state == RD_AR);

    // R channel — skid buffer
    localparam int R_BUF_W = ID_WIDTH + DATA_WIDTH + 2 + 1; // id+data+resp+last
    logic [R_BUF_W-1:0] w_r_buf_data;
    logic                w_r_buf_valid, w_r_buf_ready, w_r_skid_rdy;

    komandara_skid_buffer #(.DATA_WIDTH(R_BUF_W)) u_r_skid (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .s_data_i  ({m_axi_rid_i, m_axi_rlast_i, m_axi_rresp_i, m_axi_rdata_i}),
        .s_valid_i (m_axi_rvalid_i),
        .s_ready_o (w_r_skid_rdy),
        .m_data_o  (w_r_buf_data),
        .m_valid_o (w_r_buf_valid),
        .m_ready_i (w_r_buf_ready)
    );
    assign m_axi_rready_o = w_r_skid_rdy;

    assign rd_data_valid_o = w_r_buf_valid && r_rd_rsp_pending;
    assign rd_data_o       = w_r_buf_data[DATA_WIDTH-1:0];
    assign rd_resp_o       = w_r_buf_data[DATA_WIDTH +: 2];
    assign rd_last_o       = w_r_buf_data[DATA_WIDTH+2];
    assign rd_id_o         = w_r_buf_data[DATA_WIDTH+3 +: ID_WIDTH];
    assign w_r_buf_ready   = rd_data_ready_i && r_rd_rsp_pending;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_rd_state       <= RD_IDLE;
            r_rd_rsp_pending <= 1'b0;
        end else begin
            // Clear pending on last beat consumed
            if (rd_data_valid_o && rd_data_ready_i && rd_last_o)
                r_rd_rsp_pending <= 1'b0;

            case (r_rd_state)
                RD_IDLE: begin
                    if (rd_cmd_valid_i && rd_cmd_ready_o) begin
                        r_ar_id    <= rd_cmd_id_i;
                        r_ar_addr  <= rd_cmd_addr_i;
                        r_ar_len   <= rd_cmd_len_i;
                        r_ar_size  <= rd_cmd_size_i;
                        r_ar_burst <= rd_cmd_burst_i;
                        r_rd_state <= RD_AR;
                        r_rd_rsp_pending <= 1'b1;
                    end
                end
                RD_AR: begin
                    if (m_axi_arvalid_o && m_axi_arready_i)
                        r_rd_state <= RD_DATA;
                end
                RD_DATA: begin
                    if (rd_data_valid_o && rd_data_ready_i && rd_last_o)
                        r_rd_state <= RD_IDLE;
                end
                default: r_rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
