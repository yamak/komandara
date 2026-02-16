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
// Komandara — Simple Bus → AXI4-Lite Master Bridge
// ============================================================================
// Converts the simple request/response bus interface used by the K10 core
// into an AXI4-Lite master interface via komandara_axi4lite_master.
//
// Core bus:   req/gnt + rvalid/rdata  (1-cycle handshake, multi-cycle response)
// AXI4-Lite:  Full AW/W/B and AR/R channels.
//
// Shared infrastructure — not tied to any specific core version.
// ============================================================================

module komandara_bus2axi4lite #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input  logic                       i_clk,
    input  logic                       i_rst_n,

    // ==== Simple bus (from core) ====
    input  logic                       i_req,
    input  logic                       i_we,
    input  logic [ADDR_WIDTH-1:0]      i_addr,
    input  logic [DATA_WIDTH-1:0]      i_wdata,
    input  logic [(DATA_WIDTH/8)-1:0]  i_wstrb,
    output logic                       o_gnt,
    output logic                       o_rvalid,
    output logic [DATA_WIDTH-1:0]      o_rdata,
    output logic                       o_err,

    // ==== AXI4-Lite Master Interface ====
    // Write Address
    output logic [ADDR_WIDTH-1:0]      m_axi_awaddr,
    output logic [2:0]                 m_axi_awprot,
    output logic                       m_axi_awvalid,
    input  logic                       m_axi_awready,
    // Write Data
    output logic [DATA_WIDTH-1:0]      m_axi_wdata,
    output logic [(DATA_WIDTH/8)-1:0]  m_axi_wstrb,
    output logic                       m_axi_wvalid,
    input  logic                       m_axi_wready,
    // Write Response
    input  logic [1:0]                 m_axi_bresp,
    input  logic                       m_axi_bvalid,
    output logic                       m_axi_bready,
    // Read Address
    output logic [ADDR_WIDTH-1:0]      m_axi_araddr,
    output logic [2:0]                 m_axi_arprot,
    output logic                       m_axi_arvalid,
    input  logic                       m_axi_arready,
    // Read Data
    input  logic [DATA_WIDTH-1:0]      m_axi_rdata,
    input  logic [1:0]                 m_axi_rresp,
    input  logic                       m_axi_rvalid,
    output logic                       m_axi_rready
);

    // -----------------------------------------------------------------------
    // State machine
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_RSP
    } state_e;

    state_e r_state, w_state_next;

    // Note: r_we removed (unused at present; the master module handles
    //       write-enable from cmd_we directly).

    // -----------------------------------------------------------------------
    // Command → AXI4-Lite master module
    // -----------------------------------------------------------------------
    logic        w_cmd_valid;
    logic        w_cmd_ready;

    logic        w_rsp_valid;
    logic [DATA_WIDTH-1:0] w_rsp_rdata;
    logic [1:0]  w_rsp_resp;

    komandara_axi4lite_master #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_axi_master (
        .clk_i            (i_clk),
        .rst_ni           (i_rst_n),
        // Command
        .cmd_valid_i      (w_cmd_valid),
        .cmd_ready_o      (w_cmd_ready),
        .cmd_write_i      (i_we),
        .cmd_addr_i       (i_addr),
        .cmd_wdata_i      (i_wdata),
        .cmd_wstrb_i      (i_wstrb),
        .cmd_prot_i       (3'b000),
        // Response
        .rsp_valid_o      (w_rsp_valid),
        .rsp_ready_i      (1'b1),      // Always accept responses
        .rsp_rdata_o      (w_rsp_rdata),
        .rsp_resp_o       (w_rsp_resp),
        // AXI4-Lite
        .m_axi_awaddr_o   (m_axi_awaddr),
        .m_axi_awprot_o   (m_axi_awprot),
        .m_axi_awvalid_o  (m_axi_awvalid),
        .m_axi_awready_i  (m_axi_awready),
        .m_axi_wdata_o    (m_axi_wdata),
        .m_axi_wstrb_o    (m_axi_wstrb),
        .m_axi_wvalid_o   (m_axi_wvalid),
        .m_axi_wready_i   (m_axi_wready),
        .m_axi_bresp_i    (m_axi_bresp),
        .m_axi_bvalid_i   (m_axi_bvalid),
        .m_axi_bready_o   (m_axi_bready),
        .m_axi_araddr_o   (m_axi_araddr),
        .m_axi_arprot_o   (m_axi_arprot),
        .m_axi_arvalid_o  (m_axi_arvalid),
        .m_axi_arready_i  (m_axi_arready),
        .m_axi_rdata_i    (m_axi_rdata),
        .m_axi_rresp_i    (m_axi_rresp),
        .m_axi_rvalid_i   (m_axi_rvalid),
        .m_axi_rready_o   (m_axi_rready)
    );

    // -----------------------------------------------------------------------
    // FSM — combinational
    // -----------------------------------------------------------------------
    always_comb begin
        w_state_next = r_state;
        w_cmd_valid  = 1'b0;
        o_gnt        = 1'b0;
        o_rvalid     = 1'b0;
        o_rdata      = w_rsp_rdata;
        o_err        = 1'b0;

        unique case (r_state)
            ST_IDLE: begin
                if (i_req) begin
                    w_cmd_valid = 1'b1;
                    if (w_cmd_ready) begin
                        o_gnt        = 1'b1;
                        w_state_next = ST_WAIT_RSP;
                    end
                end
            end

            ST_WAIT_RSP: begin
                if (w_rsp_valid) begin
                    o_rvalid     = 1'b1;
                    o_rdata      = w_rsp_rdata;
                    o_err        = (w_rsp_resp != 2'b00);
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
            r_state <= ST_IDLE;
        end else begin
            r_state <= w_state_next;
        end
    end

endmodule : komandara_bus2axi4lite
