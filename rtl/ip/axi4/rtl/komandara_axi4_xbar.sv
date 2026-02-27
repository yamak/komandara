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
// Komandara — AXI4 Full Crossbar (N Masters × N Slaves)
// ============================================================================
// Parametric crossbar with burst support.
//   - ROUND_ROBIN = 1 : fair round-robin
//   - ROUND_ROBIN = 0 : fixed priority (lower idx = higher)
//   - Independent write and read paths per slave
//   - Write grant held until B response
//   - Read grant held until RLAST
// ============================================================================

module komandara_axi4_xbar #(
    parameter int N_MASTERS   = 2,
    parameter int N_SLAVES    = 2,
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int ID_WIDTH    = 4,
    parameter bit ROUND_ROBIN = 1'b1,
    parameter bit [N_SLAVES*ADDR_WIDTH-1:0] SLAVE_ADDR_BASE = '0,
    parameter bit [N_SLAVES*ADDR_WIDTH-1:0] SLAVE_ADDR_MASK = '0
)(
    input  logic clk_i,
    input  logic rst_ni,

    // === Master-side slave ports (from external masters) ===
    input  logic [N_MASTERS-1:0][ID_WIDTH-1:0]       s_axi_awid_i,
    input  logic [N_MASTERS-1:0][ADDR_WIDTH-1:0]     s_axi_awaddr_i,
    input  logic [N_MASTERS-1:0][7:0]                s_axi_awlen_i,
    input  logic [N_MASTERS-1:0][2:0]                s_axi_awsize_i,
    input  logic [N_MASTERS-1:0][1:0]                s_axi_awburst_i,
    input  logic [N_MASTERS-1:0]                     s_axi_awvalid_i,
    output logic [N_MASTERS-1:0]                     s_axi_awready_o,

    input  logic [N_MASTERS-1:0][DATA_WIDTH-1:0]     s_axi_wdata_i,
    input  logic [N_MASTERS-1:0][(DATA_WIDTH/8)-1:0] s_axi_wstrb_i,
    input  logic [N_MASTERS-1:0]                     s_axi_wlast_i,
    input  logic [N_MASTERS-1:0]                     s_axi_wvalid_i,
    output logic [N_MASTERS-1:0]                     s_axi_wready_o,

    output logic [N_MASTERS-1:0][ID_WIDTH-1:0]       s_axi_bid_o,
    output logic [N_MASTERS-1:0][1:0]                s_axi_bresp_o,
    output logic [N_MASTERS-1:0]                     s_axi_bvalid_o,
    input  logic [N_MASTERS-1:0]                     s_axi_bready_i,

    input  logic [N_MASTERS-1:0][ID_WIDTH-1:0]       s_axi_arid_i,
    input  logic [N_MASTERS-1:0][ADDR_WIDTH-1:0]     s_axi_araddr_i,
    input  logic [N_MASTERS-1:0][7:0]                s_axi_arlen_i,
    input  logic [N_MASTERS-1:0][2:0]                s_axi_arsize_i,
    input  logic [N_MASTERS-1:0][1:0]                s_axi_arburst_i,
    input  logic [N_MASTERS-1:0]                     s_axi_arvalid_i,
    output logic [N_MASTERS-1:0]                     s_axi_arready_o,

    output logic [N_MASTERS-1:0][ID_WIDTH-1:0]       s_axi_rid_o,
    output logic [N_MASTERS-1:0][DATA_WIDTH-1:0]     s_axi_rdata_o,
    output logic [N_MASTERS-1:0][1:0]                s_axi_rresp_o,
    output logic [N_MASTERS-1:0]                     s_axi_rlast_o,
    output logic [N_MASTERS-1:0]                     s_axi_rvalid_o,
    input  logic [N_MASTERS-1:0]                     s_axi_rready_i,

    // === Slave-side master ports (to external slaves) ===
    output logic [N_SLAVES-1:0][ID_WIDTH-1:0]        m_axi_awid_o,
    output logic [N_SLAVES-1:0][ADDR_WIDTH-1:0]      m_axi_awaddr_o,
    output logic [N_SLAVES-1:0][7:0]                 m_axi_awlen_o,
    output logic [N_SLAVES-1:0][2:0]                 m_axi_awsize_o,
    output logic [N_SLAVES-1:0][1:0]                 m_axi_awburst_o,
    output logic [N_SLAVES-1:0]                      m_axi_awvalid_o,
    input  logic [N_SLAVES-1:0]                      m_axi_awready_i,

    output logic [N_SLAVES-1:0][DATA_WIDTH-1:0]      m_axi_wdata_o,
    output logic [N_SLAVES-1:0][(DATA_WIDTH/8)-1:0]  m_axi_wstrb_o,
    output logic [N_SLAVES-1:0]                      m_axi_wlast_o,
    output logic [N_SLAVES-1:0]                      m_axi_wvalid_o,
    input  logic [N_SLAVES-1:0]                      m_axi_wready_i,

    input  logic [N_SLAVES-1:0][ID_WIDTH-1:0]        m_axi_bid_i,
    input  logic [N_SLAVES-1:0][1:0]                 m_axi_bresp_i,
    input  logic [N_SLAVES-1:0]                      m_axi_bvalid_i,
    output logic [N_SLAVES-1:0]                      m_axi_bready_o,

    output logic [N_SLAVES-1:0][ID_WIDTH-1:0]        m_axi_arid_o,
    output logic [N_SLAVES-1:0][ADDR_WIDTH-1:0]      m_axi_araddr_o,
    output logic [N_SLAVES-1:0][7:0]                 m_axi_arlen_o,
    output logic [N_SLAVES-1:0][2:0]                 m_axi_arsize_o,
    output logic [N_SLAVES-1:0][1:0]                 m_axi_arburst_o,
    output logic [N_SLAVES-1:0]                      m_axi_arvalid_o,
    input  logic [N_SLAVES-1:0]                      m_axi_arready_i,

    input  logic [N_SLAVES-1:0][ID_WIDTH-1:0]        m_axi_rid_i,
    input  logic [N_SLAVES-1:0][DATA_WIDTH-1:0]      m_axi_rdata_i,
    input  logic [N_SLAVES-1:0][1:0]                 m_axi_rresp_i,
    input  logic [N_SLAVES-1:0]                      m_axi_rlast_i,
    input  logic [N_SLAVES-1:0]                      m_axi_rvalid_i,
    output logic [N_SLAVES-1:0]                      m_axi_rready_o
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    localparam int M_IDX_W    = (N_MASTERS > 1) ? $clog2(N_MASTERS) : 1;
    localparam int S_IDX_W    = (N_SLAVES  > 1) ? $clog2(N_SLAVES)  : 1;

    // ================================================================
    // Address Decode
    // ================================================================
    logic [ADDR_WIDTH-1:0] w_slv_base [N_SLAVES];
    logic [ADDR_WIDTH-1:0] w_slv_mask [N_SLAVES];

    for (genvar s = 0; s < N_SLAVES; s++) begin : gen_unpack
        assign w_slv_base[s] = SLAVE_ADDR_BASE[s*ADDR_WIDTH +: ADDR_WIDTH];
        assign w_slv_mask[s] = SLAVE_ADDR_MASK[s*ADDR_WIDTH +: ADDR_WIDTH];
    end

    function automatic logic [S_IDX_W-1:0] f_decode(
        input logic [ADDR_WIDTH-1:0] addr
    );
        for (int s = 0; s < N_SLAVES; s++)
            if ((addr & w_slv_mask[s]) == w_slv_base[s])
                return S_IDX_W'(s);
        return '0;
    endfunction

    logic [S_IDX_W-1:0] w_wr_tgt [N_MASTERS];
    logic [S_IDX_W-1:0] w_rd_tgt [N_MASTERS];
    for (genvar m = 0; m < N_MASTERS; m++) begin : gen_dec
        assign w_wr_tgt[m] = f_decode(s_axi_awaddr_i[m]);
        assign w_rd_tgt[m] = f_decode(s_axi_araddr_i[m]);
    end

    // ================================================================
    // Per-Slave Write Path (grant held until B handshake)
    // ================================================================
    typedef enum logic {WR_IDLE, WR_ACTIVE} wr_st_e;
    wr_st_e              r_wr_st  [N_SLAVES];
    logic [M_IDX_W-1:0]  r_wr_gnt [N_SLAVES];

    logic [N_MASTERS-1:0] w_wr_req    [N_SLAVES];
    logic [N_MASTERS-1:0] w_wr_gnt_oh [N_SLAVES];
    logic                 w_wr_any    [N_SLAVES];
    logic                 w_wr_adv    [N_SLAVES];
    logic                 w_wr_b_done [N_SLAVES];

    for (genvar s = 0; s < N_SLAVES; s++) begin : gen_wr_slv

        for (genvar m = 0; m < N_MASTERS; m++) begin : gen_wreq
            assign w_wr_req[s][m] = s_axi_awvalid_i[m]
                                  && (w_wr_tgt[m] == S_IDX_W'(s))
                                  && (r_wr_st[s] == WR_IDLE);
        end

        komandara_arbiter #(.N_REQ(N_MASTERS), .ROUND_ROBIN(ROUND_ROBIN))
        u_wr_arb (
            .clk_i(clk_i), .rst_ni(rst_ni),
            .req_i(w_wr_req[s]), .advance_i(w_wr_adv[s]),
            .gnt_o(w_wr_gnt_oh[s]), .valid_o(w_wr_any[s])
        );

        logic [M_IDX_W-1:0] w_idx;
        always_comb begin
            w_idx = '0;
            for (int i = 0; i < N_MASTERS; i++)
                if (w_wr_gnt_oh[s][i]) w_idx = M_IDX_W'(i);
        end

        assign w_wr_b_done[s] = (r_wr_st[s] == WR_ACTIVE)
                               && m_axi_bvalid_i[s]
                               && s_axi_bready_i[r_wr_gnt[s]];
        assign w_wr_adv[s] = w_wr_b_done[s];

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                r_wr_st[s]  <= WR_IDLE;
                r_wr_gnt[s] <= '0;
            end else begin
                case (r_wr_st[s])
                    WR_IDLE:  if (w_wr_any[s]) begin r_wr_st[s] <= WR_ACTIVE; r_wr_gnt[s] <= w_idx; end
                    WR_ACTIVE: if (w_wr_b_done[s]) r_wr_st[s] <= WR_IDLE;
                    default: r_wr_st[s] <= WR_IDLE;
                endcase
            end
        end

        // Forward AW
        assign m_axi_awvalid_o[s] = (r_wr_st[s] == WR_ACTIVE) ? s_axi_awvalid_i[r_wr_gnt[s]] : 1'b0;
        assign m_axi_awid_o[s]    = s_axi_awid_i   [r_wr_gnt[s]];
        assign m_axi_awaddr_o[s]  = s_axi_awaddr_i [r_wr_gnt[s]];
        assign m_axi_awlen_o[s]   = s_axi_awlen_i  [r_wr_gnt[s]];
        assign m_axi_awsize_o[s]  = s_axi_awsize_i [r_wr_gnt[s]];
        assign m_axi_awburst_o[s] = s_axi_awburst_i[r_wr_gnt[s]];
        // Forward W
        assign m_axi_wvalid_o[s]  = (r_wr_st[s] == WR_ACTIVE) ? s_axi_wvalid_i[r_wr_gnt[s]] : 1'b0;
        assign m_axi_wdata_o[s]   = s_axi_wdata_i[r_wr_gnt[s]];
        assign m_axi_wstrb_o[s]   = s_axi_wstrb_i[r_wr_gnt[s]];
        assign m_axi_wlast_o[s]   = s_axi_wlast_i[r_wr_gnt[s]];
        // Forward B ready
        assign m_axi_bready_o[s]  = (r_wr_st[s] == WR_ACTIVE) ? s_axi_bready_i[r_wr_gnt[s]] : 1'b0;
    end

    // ================================================================
    // Per-Slave Read Path (grant held until RLAST handshake)
    // ================================================================
    typedef enum logic {RD_IDLE, RD_ACTIVE} rd_st_e;
    rd_st_e              r_rd_st  [N_SLAVES];
    logic [M_IDX_W-1:0]  r_rd_gnt [N_SLAVES];

    logic [N_MASTERS-1:0] w_rd_req    [N_SLAVES];
    logic [N_MASTERS-1:0] w_rd_gnt_oh [N_SLAVES];
    logic                 w_rd_any    [N_SLAVES];
    logic                 w_rd_adv    [N_SLAVES];
    logic                 w_rd_done   [N_SLAVES];

    for (genvar s = 0; s < N_SLAVES; s++) begin : gen_rd_slv

        for (genvar m = 0; m < N_MASTERS; m++) begin : gen_rreq
            assign w_rd_req[s][m] = s_axi_arvalid_i[m]
                                  && (w_rd_tgt[m] == S_IDX_W'(s))
                                  && (r_rd_st[s] == RD_IDLE);
        end

        komandara_arbiter #(.N_REQ(N_MASTERS), .ROUND_ROBIN(ROUND_ROBIN))
        u_rd_arb (
            .clk_i(clk_i), .rst_ni(rst_ni),
            .req_i(w_rd_req[s]), .advance_i(w_rd_adv[s]),
            .gnt_o(w_rd_gnt_oh[s]), .valid_o(w_rd_any[s])
        );

        logic [M_IDX_W-1:0] w_ri;
        always_comb begin
            w_ri = '0;
            for (int i = 0; i < N_MASTERS; i++)
                if (w_rd_gnt_oh[s][i]) w_ri = M_IDX_W'(i);
        end

        assign w_rd_done[s] = (r_rd_st[s] == RD_ACTIVE)
                             && m_axi_rvalid_i[s]
                             && m_axi_rlast_i[s]
                             && s_axi_rready_i[r_rd_gnt[s]];
        assign w_rd_adv[s] = w_rd_done[s];

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                r_rd_st[s]  <= RD_IDLE;
                r_rd_gnt[s] <= '0;
            end else begin
                case (r_rd_st[s])
                    RD_IDLE:  if (w_rd_any[s]) begin r_rd_st[s] <= RD_ACTIVE; r_rd_gnt[s] <= w_ri; end
                    RD_ACTIVE: if (w_rd_done[s]) r_rd_st[s] <= RD_IDLE;
                    default: r_rd_st[s] <= RD_IDLE;
                endcase
            end
        end

        // Forward AR
        assign m_axi_arvalid_o[s] = (r_rd_st[s] == RD_ACTIVE) ? s_axi_arvalid_i[r_rd_gnt[s]] : 1'b0;
        assign m_axi_arid_o[s]    = s_axi_arid_i   [r_rd_gnt[s]];
        assign m_axi_araddr_o[s]  = s_axi_araddr_i [r_rd_gnt[s]];
        assign m_axi_arlen_o[s]   = s_axi_arlen_i  [r_rd_gnt[s]];
        assign m_axi_arsize_o[s]  = s_axi_arsize_i [r_rd_gnt[s]];
        assign m_axi_arburst_o[s] = s_axi_arburst_i[r_rd_gnt[s]];
        // Forward R ready
        assign m_axi_rready_o[s]  = (r_rd_st[s] == RD_ACTIVE) ? s_axi_rready_i[r_rd_gnt[s]] : 1'b0;
    end

    // ================================================================
    // Per-Master Response Routing — Write
    // ================================================================
    for (genvar m = 0; m < N_MASTERS; m++) begin : gen_wr_mst
        always_comb begin
            s_axi_awready_o[m] = 1'b0;
            s_axi_wready_o[m]  = 1'b0;
            s_axi_bvalid_o[m]  = 1'b0;
            s_axi_bid_o[m]     = '0;
            s_axi_bresp_o[m]   = 2'b00;
            for (int s = 0; s < N_SLAVES; s++) begin
                if (r_wr_st[s] == WR_ACTIVE && r_wr_gnt[s] == M_IDX_W'(m)) begin
                    s_axi_awready_o[m] = m_axi_awready_i[s];
                    s_axi_wready_o[m]  = m_axi_wready_i[s];
                    s_axi_bvalid_o[m]  = m_axi_bvalid_i[s];
                    s_axi_bid_o[m]     = m_axi_bid_i[s];
                    s_axi_bresp_o[m]   = m_axi_bresp_i[s];
                end
            end
        end
    end

    // ================================================================
    // Per-Master Response Routing — Read
    // ================================================================
    for (genvar m = 0; m < N_MASTERS; m++) begin : gen_rd_mst
        always_comb begin
            s_axi_arready_o[m] = 1'b0;
            s_axi_rvalid_o[m]  = 1'b0;
            s_axi_rid_o[m]     = '0;
            s_axi_rdata_o[m]   = '0;
            s_axi_rresp_o[m]   = 2'b00;
            s_axi_rlast_o[m]   = 1'b0;
            for (int s = 0; s < N_SLAVES; s++) begin
                if (r_rd_st[s] == RD_ACTIVE && r_rd_gnt[s] == M_IDX_W'(m)) begin
                    s_axi_arready_o[m] = m_axi_arready_i[s];
                    s_axi_rvalid_o[m]  = m_axi_rvalid_i[s];
                    s_axi_rid_o[m]     = m_axi_rid_i[s];
                    s_axi_rdata_o[m]   = m_axi_rdata_i[s];
                    s_axi_rresp_o[m]   = m_axi_rresp_i[s];
                    s_axi_rlast_o[m]   = m_axi_rlast_i[s];
                end
            end
        end
    end

endmodule
