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
// Komandara - AXI4-Lite Master
// ============================================================================
// A fully-compliant AXI4-Lite master with skid buffers on response channels
// (B, R) for full throughput. Accepts simple read/write commands and drives
// AXI4-Lite transactions.
//
// Shared infrastructure — not tied to any specific core version.
//
// Features:
//   - Skid buffers on B and R channels (always accept responses promptly)
//   - Clean state machine for request phase (AW/W/AR)
//   - Independent AW and W acceptance tracking
//   - Simple command/response interface for upstream logic
// ============================================================================

module komandara_axi4lite_master #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    input  logic                      clk_i,
    input  logic                      rst_ni,

    // ====================================================================
    // Command Interface (Upstream)
    // ====================================================================
    input  logic                      cmd_valid_i,
    output logic                      cmd_ready_o,
    input  logic                      cmd_write_i,    // 1 = write, 0 = read
    input  logic [ADDR_WIDTH-1:0]     cmd_addr_i,
    input  logic [DATA_WIDTH-1:0]     cmd_wdata_i,
    input  logic [(DATA_WIDTH/8)-1:0] cmd_wstrb_i,
    input  logic [2:0]                cmd_prot_i,

    // ====================================================================
    // Response Interface (Upstream)
    // ====================================================================
    output logic                      rsp_valid_o,
    input  logic                      rsp_ready_i,
    output logic [DATA_WIDTH-1:0]     rsp_rdata_o,
    output logic [1:0]                rsp_resp_o,

    // ====================================================================
    // AXI4-Lite Master Interface (Downstream)
    // ====================================================================

    // Write Address Channel
    output logic [ADDR_WIDTH-1:0]     m_axi_awaddr_o,
    output logic [2:0]                m_axi_awprot_o,
    output logic                      m_axi_awvalid_o,
    input  logic                      m_axi_awready_i,

    // Write Data Channel
    output logic [DATA_WIDTH-1:0]     m_axi_wdata_o,
    output logic [(DATA_WIDTH/8)-1:0] m_axi_wstrb_o,
    output logic                      m_axi_wvalid_o,
    input  logic                      m_axi_wready_i,

    // Write Response Channel
    input  logic [1:0]                m_axi_bresp_i,
    input  logic                      m_axi_bvalid_i,
    output logic                      m_axi_bready_o,

    // Read Address Channel
    output logic [ADDR_WIDTH-1:0]     m_axi_araddr_o,
    output logic [2:0]                m_axi_arprot_o,
    output logic                      m_axi_arvalid_o,
    input  logic                      m_axi_arready_i,

    // Read Data Channel
    input  logic [DATA_WIDTH-1:0]     m_axi_rdata_i,
    input  logic [1:0]                m_axi_rresp_i,
    input  logic                      m_axi_rvalid_i,
    output logic                      m_axi_rready_o
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // ====================================================================
    // Request Phase — State Machine
    // ====================================================================
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WR_ADDR_DATA,   // Both AW and W asserted, waiting for acceptance
        ST_WR_ADDR_ONLY,   // Only AW pending (W already accepted)
        ST_WR_DATA_ONLY,   // Only W  pending (AW already accepted)
        ST_RD_ADDR          // AR asserted, waiting for acceptance
    } state_e;

    state_e r_state, w_state_next;

    // ====================================================================
    // Response Pending Tracking
    // ====================================================================
    logic r_rsp_pending;
    logic r_rsp_is_write;

    // ====================================================================
    // Command Acceptance
    // ====================================================================
    assign cmd_ready_o = (r_state == ST_IDLE) && !r_rsp_pending;
    logic w_cmd_accept;
    assign w_cmd_accept = cmd_valid_i && cmd_ready_o;

    // ====================================================================
    // Registered Command Data
    // ====================================================================
    logic [ADDR_WIDTH-1:0]     r_cmd_addr;
    logic [DATA_WIDTH-1:0]     r_cmd_wdata;
    logic [STRB_WIDTH-1:0]     r_cmd_wstrb;
    logic [2:0]                r_cmd_prot;

    always_ff @(posedge clk_i) begin
        if (w_cmd_accept) begin
            r_cmd_addr  <= cmd_addr_i;
            r_cmd_wdata <= cmd_wdata_i;
            r_cmd_wstrb <= cmd_wstrb_i;
            r_cmd_prot  <= cmd_prot_i;
        end
    end

    // ====================================================================
    // AXI Request Channel Outputs
    // ====================================================================
    assign m_axi_awaddr_o  = r_cmd_addr;
    assign m_axi_awprot_o  = r_cmd_prot;
    assign m_axi_awvalid_o = (r_state == ST_WR_ADDR_DATA) || (r_state == ST_WR_ADDR_ONLY);

    assign m_axi_wdata_o   = r_cmd_wdata;
    assign m_axi_wstrb_o   = r_cmd_wstrb;
    assign m_axi_wvalid_o  = (r_state == ST_WR_ADDR_DATA) || (r_state == ST_WR_DATA_ONLY);

    assign m_axi_araddr_o  = r_cmd_addr;
    assign m_axi_arprot_o  = r_cmd_prot;
    assign m_axi_arvalid_o = (r_state == ST_RD_ADDR);

    // ====================================================================
    // State Machine — Combinational Next State
    // ====================================================================
    always_comb begin
        w_state_next = r_state;

        case (r_state)
            ST_IDLE: begin
                if (w_cmd_accept && cmd_write_i)
                    w_state_next = ST_WR_ADDR_DATA;
                else if (w_cmd_accept && !cmd_write_i)
                    w_state_next = ST_RD_ADDR;
            end

            ST_WR_ADDR_DATA: begin
                case ({m_axi_awready_i, m_axi_wready_i})
                    2'b11:   w_state_next = ST_IDLE;
                    2'b10:   w_state_next = ST_WR_DATA_ONLY;
                    2'b01:   w_state_next = ST_WR_ADDR_ONLY;
                    default: w_state_next = ST_WR_ADDR_DATA;
                endcase
            end

            ST_WR_ADDR_ONLY: begin
                if (m_axi_awready_i) w_state_next = ST_IDLE;
            end

            ST_WR_DATA_ONLY: begin
                if (m_axi_wready_i) w_state_next = ST_IDLE;
            end

            ST_RD_ADDR: begin
                if (m_axi_arready_i) w_state_next = ST_IDLE;
            end

            default: w_state_next = ST_IDLE;
        endcase
    end

    // State register
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            r_state <= ST_IDLE;
        else
            r_state <= w_state_next;
    end

    // ====================================================================
    // Response Pending Register
    // ====================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_rsp_pending  <= 1'b0;
            r_rsp_is_write <= 1'b0;
        end else begin
            // Clear on response delivery (consumer handshake)
            if (rsp_valid_o && rsp_ready_i)
                r_rsp_pending <= 1'b0;
            // Set on new command acceptance (wins over clear if both — but
            // they cannot fire simultaneously: cmd_ready requires !rsp_pending)
            if (w_cmd_accept) begin
                r_rsp_pending  <= 1'b1;
                r_rsp_is_write <= cmd_write_i;
            end
        end
    end

    // ====================================================================
    // B Channel — Skid Buffer
    // ====================================================================
    logic [1:0] w_b_buf_resp;
    logic       w_b_buf_valid;
    logic       w_b_buf_ready;
    logic       w_b_skid_s_ready;

    komandara_skid_buffer #(
        .DATA_WIDTH (2)
    ) u_b_skid (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .s_data_i  (m_axi_bresp_i),
        .s_valid_i (m_axi_bvalid_i),
        .s_ready_o (w_b_skid_s_ready),
        .m_data_o  (w_b_buf_resp),
        .m_valid_o (w_b_buf_valid),
        .m_ready_i (w_b_buf_ready)
    );

    assign m_axi_bready_o = w_b_skid_s_ready;

    // ====================================================================
    // R Channel — Skid Buffer
    // ====================================================================
    logic [DATA_WIDTH+2-1:0] w_r_buf_data;
    logic                    w_r_buf_valid;
    logic                    w_r_buf_ready;
    logic                    w_r_skid_s_ready;

    komandara_skid_buffer #(
        .DATA_WIDTH (DATA_WIDTH + 2)
    ) u_r_skid (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .s_data_i  ({m_axi_rresp_i, m_axi_rdata_i}),
        .s_valid_i (m_axi_rvalid_i),
        .s_ready_o (w_r_skid_s_ready),
        .m_data_o  (w_r_buf_data),
        .m_valid_o (w_r_buf_valid),
        .m_ready_i (w_r_buf_ready)
    );

    assign m_axi_rready_o = w_r_skid_s_ready;

    // Unpack R skid buffer output
    logic [1:0]            w_r_buf_resp;
    logic [DATA_WIDTH-1:0] w_r_buf_rdata;
    assign w_r_buf_resp  = w_r_buf_data[DATA_WIDTH +: 2];
    assign w_r_buf_rdata = w_r_buf_data[DATA_WIDTH-1:0];

    // ====================================================================
    // Response Output Mux
    // ====================================================================
    assign rsp_valid_o = r_rsp_pending
                       && (r_rsp_is_write ? w_b_buf_valid : w_r_buf_valid);

    assign rsp_resp_o  = r_rsp_is_write ? w_b_buf_resp  : w_r_buf_resp;
    assign rsp_rdata_o = w_r_buf_rdata;

    // Consume from the appropriate skid buffer
    assign w_b_buf_ready = rsp_ready_i && r_rsp_pending &&  r_rsp_is_write;
    assign w_r_buf_ready = rsp_ready_i && r_rsp_pending && !r_rsp_is_write;

    // ====================================================================
    // Assertions
    // ====================================================================
    // synthesis translate_off

    // AWVALID stability: once asserted, must stay until AWREADY
    property p_awvalid_stable;
        @(posedge clk_i) disable iff (!rst_ni)
        (m_axi_awvalid_o && !m_axi_awready_i) |=> m_axi_awvalid_o;
    endproperty
    a_awvalid_stable : assert property (p_awvalid_stable)
        else $error("[AXI_MST] AWVALID deasserted without AWREADY");

    // WVALID stability
    property p_wvalid_stable;
        @(posedge clk_i) disable iff (!rst_ni)
        (m_axi_wvalid_o && !m_axi_wready_i) |=> m_axi_wvalid_o;
    endproperty
    a_wvalid_stable : assert property (p_wvalid_stable)
        else $error("[AXI_MST] WVALID deasserted without WREADY");

    // ARVALID stability
    property p_arvalid_stable;
        @(posedge clk_i) disable iff (!rst_ni)
        (m_axi_arvalid_o && !m_axi_arready_i) |=> m_axi_arvalid_o;
    endproperty
    a_arvalid_stable : assert property (p_arvalid_stable)
        else $error("[AXI_MST] ARVALID deasserted without ARREADY");

    // synthesis translate_on

endmodule
