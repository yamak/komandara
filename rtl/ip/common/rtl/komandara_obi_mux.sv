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
// Komandara - Parametric OBI Multiplexer (N Masters -> 1 Slave)
// ============================================================================
// Routes parallel requests from N_MASTERS down to a single OBI Slave using a
// Round-Robin (or Fixed Priority) Arbiter.
// ============================================================================

module komandara_obi_mux #(
    parameter int N_MASTERS   = 2,
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter bit ROUND_ROBIN = 1'b1
)(
    input  logic                                  clk_i,
    input  logic                                  rst_ni,

    // N Masters input
    input  logic [N_MASTERS-1:0]                  s_req_i,
    input  logic [N_MASTERS-1:0]                  s_we_i,
    input  logic [N_MASTERS-1:0][ADDR_WIDTH-1:0]  s_addr_i,
    input  logic [N_MASTERS-1:0][DATA_WIDTH-1:0]  s_wdata_i,
    input  logic [N_MASTERS-1:0][DATA_WIDTH/8-1:0]s_wstrb_i,
    output logic [N_MASTERS-1:0]                  s_gnt_o,
    output logic [N_MASTERS-1:0]                  s_rvalid_o,
    output logic [N_MASTERS-1:0][DATA_WIDTH-1:0]  s_rdata_o,
    output logic [N_MASTERS-1:0]                  s_err_o,

    // 1 Slave output
    output logic                                  m_req_o,
    output logic                                  m_we_o,
    output logic [ADDR_WIDTH-1:0]                 m_addr_o,
    output logic [DATA_WIDTH-1:0]                 m_wdata_o,
    output logic [DATA_WIDTH/8-1:0]               m_wstrb_o,
    input  logic                                  m_gnt_i,
    input  logic                                  m_rvalid_i,
    input  logic [DATA_WIDTH-1:0]                 m_rdata_i,
    input  logic                                  m_err_i
);

    logic [N_MASTERS-1:0] w_gnt;
    logic                 w_any_req;
    logic [7:0]           r_outstanding;
    logic [N_MASTERS-1:0] r_active_master;
    logic [N_MASTERS-1:0] w_allowed_req;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_outstanding   <= 8'd0;
            r_active_master <= '0;
        end else begin
            case ({(m_gnt_i && m_req_o), m_rvalid_i})
                2'b10: r_outstanding <= r_outstanding + 1'b1;
                2'b01: r_outstanding <= r_outstanding - 1'b1;
                default: ; // 11 or 00 -> no change
            endcase

            // Lock the active master when an outstanding transaction begins
            if (m_gnt_i && m_req_o && r_outstanding == 8'd0) begin
                r_active_master <= w_gnt;
            end
        end
    end

    // Only allow new requests from the active master if there are outstanding transactions
    always_comb begin
        if (r_outstanding > 0)
            w_allowed_req = s_req_i & r_active_master;
        else
            w_allowed_req = s_req_i;
    end

    // Grant logic / Arbiter
    komandara_arbiter #(
        .N_REQ       (N_MASTERS),
        .ROUND_ROBIN (ROUND_ROBIN)
    ) u_arbiter (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .req_i     (w_allowed_req),
        .advance_i (m_gnt_i),
        .gnt_o     (w_gnt),
        .valid_o   (w_any_req)
    );

    // MUX downstream outputs based on the current winning grant
    always_comb begin
        m_req_o   = 1'b0;
        m_we_o    = 1'b0;
        m_addr_o  = '0;
        m_wdata_o = '0;
        m_wstrb_o = '0;
        
        for (int i = 0; i < N_MASTERS; i++) begin
            if (w_gnt[i] && w_allowed_req[i]) begin
                m_req_o   = 1'b1;
                m_we_o    = s_we_i[i];
                m_addr_o  = s_addr_i[i];
                m_wdata_o = s_wdata_i[i];
                m_wstrb_o = s_wstrb_i[i];
            end
        end
    end

    // Route grant back to the specific master
    assign s_gnt_o = w_gnt & {N_MASTERS{m_gnt_i}};

    // Route RVALID and RDATA back to the active master
    always_comb begin
        for (int i = 0; i < N_MASTERS; i++) begin
            // If outstanding is 0 but we get rvalid, it's either an error or 
            // a 0-wait state response arriving in the same cycle it was granted.
            // In the same cycle, r_active_master is not yet updated via flip-flop, 
            // so we must use w_gnt for immediate routing.
            logic v_match;
            v_match = (r_outstanding == 0) ? w_gnt[i] : r_active_master[i];
            
            s_rvalid_o[i] = v_match ? m_rvalid_i : 1'b0;
            s_rdata_o[i]  = m_rdata_i;
            s_err_o[i]    = v_match ? m_err_i : 1'b0;
        end
    end

endmodule
