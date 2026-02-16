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
// Komandara - AXI4-Lite Crossbar (N Masters × N Slaves)
// ============================================================================
// Parametric AXI4-Lite crossbar interconnect.
//
// Features:
//   - Parametric master/slave count
//   - Selectable arbitration: round-robin or fixed-priority
//   - Independent write and read paths per slave (full duplex)
//   - Non-blocking: parallel paths to different slaves
//   - 1-cycle grant acquisition, then transparent forwarding
//
// Address Map: SLAVE_ADDR_BASE / SLAVE_ADDR_MASK (packed flat vectors).
//   Slave s matches if: (addr & mask_s) == base_s
//
// Shared infrastructure — not tied to any specific core version.
// ============================================================================

module komandara_axi4lite_xbar #(
    parameter int N_MASTERS   = 2,
    parameter int N_SLAVES    = 2,
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter bit ROUND_ROBIN = 1'b1,
    // Flat packed address map: {slave[N-1] ... slave[0]}, each ADDR_WIDTH bits
    parameter bit [N_SLAVES*ADDR_WIDTH-1:0] SLAVE_ADDR_BASE = '0,
    parameter bit [N_SLAVES*ADDR_WIDTH-1:0] SLAVE_ADDR_MASK = '0
)(
    input  logic clk_i,
    input  logic rst_ni,

    // ====================================================================
    // Master-side slave ports (from external masters, active high arrays)
    // ====================================================================
    input  logic [N_MASTERS-1:0][ADDR_WIDTH-1:0]     s_axi_awaddr_i,
    input  logic [N_MASTERS-1:0][2:0]                 s_axi_awprot_i,
    input  logic [N_MASTERS-1:0]                      s_axi_awvalid_i,
    output logic [N_MASTERS-1:0]                      s_axi_awready_o,

    input  logic [N_MASTERS-1:0][DATA_WIDTH-1:0]      s_axi_wdata_i,
    input  logic [N_MASTERS-1:0][(DATA_WIDTH/8)-1:0]  s_axi_wstrb_i,
    input  logic [N_MASTERS-1:0]                      s_axi_wvalid_i,
    output logic [N_MASTERS-1:0]                      s_axi_wready_o,

    output logic [N_MASTERS-1:0][1:0]                 s_axi_bresp_o,
    output logic [N_MASTERS-1:0]                      s_axi_bvalid_o,
    input  logic [N_MASTERS-1:0]                      s_axi_bready_i,

    input  logic [N_MASTERS-1:0][ADDR_WIDTH-1:0]      s_axi_araddr_i,
    input  logic [N_MASTERS-1:0][2:0]                 s_axi_arprot_i,
    input  logic [N_MASTERS-1:0]                      s_axi_arvalid_i,
    output logic [N_MASTERS-1:0]                      s_axi_arready_o,

    output logic [N_MASTERS-1:0][DATA_WIDTH-1:0]      s_axi_rdata_o,
    output logic [N_MASTERS-1:0][1:0]                 s_axi_rresp_o,
    output logic [N_MASTERS-1:0]                      s_axi_rvalid_o,
    input  logic [N_MASTERS-1:0]                      s_axi_rready_i,

    // ====================================================================
    // Slave-side master ports (to external slaves)
    // ====================================================================
    output logic [N_SLAVES-1:0][ADDR_WIDTH-1:0]       m_axi_awaddr_o,
    output logic [N_SLAVES-1:0][2:0]                  m_axi_awprot_o,
    output logic [N_SLAVES-1:0]                       m_axi_awvalid_o,
    input  logic [N_SLAVES-1:0]                       m_axi_awready_i,

    output logic [N_SLAVES-1:0][DATA_WIDTH-1:0]       m_axi_wdata_o,
    output logic [N_SLAVES-1:0][(DATA_WIDTH/8)-1:0]   m_axi_wstrb_o,
    output logic [N_SLAVES-1:0]                       m_axi_wvalid_o,
    input  logic [N_SLAVES-1:0]                       m_axi_wready_i,

    input  logic [N_SLAVES-1:0][1:0]                  m_axi_bresp_i,
    input  logic [N_SLAVES-1:0]                       m_axi_bvalid_i,
    output logic [N_SLAVES-1:0]                       m_axi_bready_o,

    output logic [N_SLAVES-1:0][ADDR_WIDTH-1:0]       m_axi_araddr_o,
    output logic [N_SLAVES-1:0][2:0]                  m_axi_arprot_o,
    output logic [N_SLAVES-1:0]                       m_axi_arvalid_o,
    input  logic [N_SLAVES-1:0]                       m_axi_arready_i,

    input  logic [N_SLAVES-1:0][DATA_WIDTH-1:0]       m_axi_rdata_i,
    input  logic [N_SLAVES-1:0][1:0]                  m_axi_rresp_i,
    input  logic [N_SLAVES-1:0]                       m_axi_rvalid_i,
    output logic [N_SLAVES-1:0]                       m_axi_rready_o
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    localparam int M_IDX_W    = (N_MASTERS > 1) ? $clog2(N_MASTERS) : 1;
    localparam int S_IDX_W    = (N_SLAVES  > 1) ? $clog2(N_SLAVES)  : 1;

    // ====================================================================
    // Address Decode — unpack flat parameters
    // ====================================================================
    logic [ADDR_WIDTH-1:0] w_slv_base [N_SLAVES];
    logic [ADDR_WIDTH-1:0] w_slv_mask [N_SLAVES];

    for (genvar s = 0; s < N_SLAVES; s++) begin : gen_addr_unpack
        assign w_slv_base[s] = SLAVE_ADDR_BASE[s*ADDR_WIDTH +: ADDR_WIDTH];
        assign w_slv_mask[s] = SLAVE_ADDR_MASK[s*ADDR_WIDTH +: ADDR_WIDTH];
    end

    // Address decode function: returns target slave index
    function automatic logic [S_IDX_W-1:0] f_decode(
        input logic [ADDR_WIDTH-1:0] addr
    );
        for (int s = 0; s < N_SLAVES; s++) begin
            if ((addr & w_slv_mask[s]) == w_slv_base[s])
                return S_IDX_W'(s);
        end
        return '0; // Default: slave 0
    endfunction

    // Per-master decode results
    logic [S_IDX_W-1:0] w_wr_target [N_MASTERS]; // Write target slave
    logic [S_IDX_W-1:0] w_rd_target [N_MASTERS]; // Read target slave

    for (genvar m = 0; m < N_MASTERS; m++) begin : gen_decode
        assign w_wr_target[m] = f_decode(s_axi_awaddr_i[m]);
        assign w_rd_target[m] = f_decode(s_axi_araddr_i[m]);
    end

    // ====================================================================
    // Per-Slave Write Path
    // ====================================================================
    typedef enum logic {WR_IDLE, WR_ACTIVE} wr_state_e;

    wr_state_e       r_wr_state [N_SLAVES];
    logic [M_IDX_W-1:0] r_wr_gnt_idx [N_SLAVES]; // Granted master index

    // Arbiter request/grant wires
    logic [N_MASTERS-1:0] w_wr_req   [N_SLAVES];
    logic [N_MASTERS-1:0] w_wr_gnt   [N_SLAVES];
    logic                 w_wr_valid  [N_SLAVES];
    logic                 w_wr_advance[N_SLAVES];

    // B handshake detection per slave
    logic w_wr_b_done [N_SLAVES];

    for (genvar s = 0; s < N_SLAVES; s++) begin : gen_wr_slv

        // ---- Request vector: masters targeting this slave ----
        for (genvar m = 0; m < N_MASTERS; m++) begin : gen_wr_req
            assign w_wr_req[s][m] = s_axi_awvalid_i[m]
                                  && (w_wr_target[m] == S_IDX_W'(s))
                                  && (r_wr_state[s] == WR_IDLE);
        end

        // ---- Arbiter ----
        komandara_arbiter #(
            .N_REQ       (N_MASTERS),
            .ROUND_ROBIN (ROUND_ROBIN)
        ) u_wr_arb (
            .clk_i     (clk_i),
            .rst_ni    (rst_ni),
            .req_i     (w_wr_req[s]),
            .advance_i (w_wr_advance[s]),
            .gnt_o     (w_wr_gnt[s]),
            .valid_o   (w_wr_valid[s])
        );

        // ---- Grant index from one-hot ----
        logic [M_IDX_W-1:0] w_arb_idx;
        always_comb begin
            w_arb_idx = '0;
            for (int i = 0; i < N_MASTERS; i++)
                if (w_wr_gnt[s][i]) w_arb_idx = M_IDX_W'(i);
        end

        // ---- B handshake ----
        assign w_wr_b_done[s] = (r_wr_state[s] == WR_ACTIVE)
                              && m_axi_bvalid_i[s]
                              && s_axi_bready_i[r_wr_gnt_idx[s]];

        assign w_wr_advance[s] = w_wr_b_done[s];

        // ---- State machine ----
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                r_wr_state[s]   <= WR_IDLE;
                r_wr_gnt_idx[s] <= '0;
            end else begin
                case (r_wr_state[s])
                    WR_IDLE: begin
                        if (w_wr_valid[s]) begin
                            r_wr_state[s]   <= WR_ACTIVE;
                            r_wr_gnt_idx[s] <= w_arb_idx;
                        end
                    end
                    WR_ACTIVE: begin
                        if (w_wr_b_done[s])
                            r_wr_state[s] <= WR_IDLE;
                    end
                    default: r_wr_state[s] <= WR_IDLE;
                endcase
            end
        end

        // ---- Forward AW from granted master → slave ----
        assign m_axi_awvalid_o[s] = (r_wr_state[s] == WR_ACTIVE)
                                   ? s_axi_awvalid_i[r_wr_gnt_idx[s]] : 1'b0;
        assign m_axi_awaddr_o[s]  = s_axi_awaddr_i[r_wr_gnt_idx[s]];
        assign m_axi_awprot_o[s]  = s_axi_awprot_i[r_wr_gnt_idx[s]];

        // ---- Forward W from granted master → slave ----
        assign m_axi_wvalid_o[s] = (r_wr_state[s] == WR_ACTIVE)
                                  ? s_axi_wvalid_i[r_wr_gnt_idx[s]] : 1'b0;
        assign m_axi_wdata_o[s]  = s_axi_wdata_i[r_wr_gnt_idx[s]];
        assign m_axi_wstrb_o[s]  = s_axi_wstrb_i[r_wr_gnt_idx[s]];

        // ---- Forward B ready from granted master → slave ----
        assign m_axi_bready_o[s] = (r_wr_state[s] == WR_ACTIVE)
                                  ? s_axi_bready_i[r_wr_gnt_idx[s]] : 1'b0;
    end

    // ====================================================================
    // Per-Slave Read Path
    // ====================================================================
    typedef enum logic {RD_IDLE, RD_ACTIVE} rd_state_e;

    rd_state_e          r_rd_state [N_SLAVES];
    logic [M_IDX_W-1:0] r_rd_gnt_idx [N_SLAVES];

    logic [N_MASTERS-1:0] w_rd_req   [N_SLAVES];
    logic [N_MASTERS-1:0] w_rd_gnt   [N_SLAVES];
    logic                 w_rd_valid  [N_SLAVES];
    logic                 w_rd_advance[N_SLAVES];

    logic w_rd_r_done [N_SLAVES];

    for (genvar s = 0; s < N_SLAVES; s++) begin : gen_rd_slv

        // ---- Request vector ----
        for (genvar m = 0; m < N_MASTERS; m++) begin : gen_rd_req
            assign w_rd_req[s][m] = s_axi_arvalid_i[m]
                                  && (w_rd_target[m] == S_IDX_W'(s))
                                  && (r_rd_state[s] == RD_IDLE);
        end

        // ---- Arbiter ----
        komandara_arbiter #(
            .N_REQ       (N_MASTERS),
            .ROUND_ROBIN (ROUND_ROBIN)
        ) u_rd_arb (
            .clk_i     (clk_i),
            .rst_ni    (rst_ni),
            .req_i     (w_rd_req[s]),
            .advance_i (w_rd_advance[s]),
            .gnt_o     (w_rd_gnt[s]),
            .valid_o   (w_rd_valid[s])
        );

        logic [M_IDX_W-1:0] w_rd_arb_idx;
        always_comb begin
            w_rd_arb_idx = '0;
            for (int i = 0; i < N_MASTERS; i++)
                if (w_rd_gnt[s][i]) w_rd_arb_idx = M_IDX_W'(i);
        end

        // ---- R handshake ----
        assign w_rd_r_done[s] = (r_rd_state[s] == RD_ACTIVE)
                              && m_axi_rvalid_i[s]
                              && s_axi_rready_i[r_rd_gnt_idx[s]];

        assign w_rd_advance[s] = w_rd_r_done[s];

        // ---- State machine ----
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                r_rd_state[s]   <= RD_IDLE;
                r_rd_gnt_idx[s] <= '0;
            end else begin
                case (r_rd_state[s])
                    RD_IDLE: begin
                        if (w_rd_valid[s]) begin
                            r_rd_state[s]   <= RD_ACTIVE;
                            r_rd_gnt_idx[s] <= w_rd_arb_idx;
                        end
                    end
                    RD_ACTIVE: begin
                        if (w_rd_r_done[s])
                            r_rd_state[s] <= RD_IDLE;
                    end
                    default: r_rd_state[s] <= RD_IDLE;
                endcase
            end
        end

        // ---- Forward AR from granted master → slave ----
        assign m_axi_arvalid_o[s] = (r_rd_state[s] == RD_ACTIVE)
                                   ? s_axi_arvalid_i[r_rd_gnt_idx[s]] : 1'b0;
        assign m_axi_araddr_o[s]  = s_axi_araddr_i[r_rd_gnt_idx[s]];
        assign m_axi_arprot_o[s]  = s_axi_arprot_i[r_rd_gnt_idx[s]];

        // ---- Forward R ready from granted master → slave ----
        assign m_axi_rready_o[s] = (r_rd_state[s] == RD_ACTIVE)
                                  ? s_axi_rready_i[r_rd_gnt_idx[s]] : 1'b0;
    end

    // ====================================================================
    // Per-Master Response Routing (Write)
    // ====================================================================
    for (genvar m = 0; m < N_MASTERS; m++) begin : gen_wr_mst

        always_comb begin
            s_axi_awready_o[m] = 1'b0;
            s_axi_wready_o[m]  = 1'b0;
            s_axi_bvalid_o[m]  = 1'b0;
            s_axi_bresp_o[m]   = 2'b00;

            for (int s = 0; s < N_SLAVES; s++) begin
                if (r_wr_state[s] == WR_ACTIVE
                    && r_wr_gnt_idx[s] == M_IDX_W'(m)) begin
                    s_axi_awready_o[m] = m_axi_awready_i[s];
                    s_axi_wready_o[m]  = m_axi_wready_i[s];
                    s_axi_bvalid_o[m]  = m_axi_bvalid_i[s];
                    s_axi_bresp_o[m]   = m_axi_bresp_i[s];
                end
            end
        end
    end

    // ====================================================================
    // Per-Master Response Routing (Read)
    // ====================================================================
    for (genvar m = 0; m < N_MASTERS; m++) begin : gen_rd_mst

        always_comb begin
            s_axi_arready_o[m] = 1'b0;
            s_axi_rvalid_o[m]  = 1'b0;
            s_axi_rdata_o[m]   = '0;
            s_axi_rresp_o[m]   = 2'b00;

            for (int s = 0; s < N_SLAVES; s++) begin
                if (r_rd_state[s] == RD_ACTIVE
                    && r_rd_gnt_idx[s] == M_IDX_W'(m)) begin
                    s_axi_arready_o[m] = m_axi_arready_i[s];
                    s_axi_rvalid_o[m]  = m_axi_rvalid_i[s];
                    s_axi_rdata_o[m]   = m_axi_rdata_i[s];
                    s_axi_rresp_o[m]   = m_axi_rresp_i[s];
                end
            end
        end
    end

endmodule
