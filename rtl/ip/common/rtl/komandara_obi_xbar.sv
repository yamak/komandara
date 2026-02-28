// Copyright 2026 The Komandara Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

// ============================================================================
// Komandara — OBI (Native) 1xN Crossbar
// ============================================================================
// Simple single-master, multi-slave crossbar for Native OBI buses.
// Used primarily to split the instruction fetch bus between local TCM (BRAM)
// and the system AXI crossbar (for Debug ROM etc).
// ============================================================================

module komandara_obi_xbar #(
    parameter int N_SLAVES = 2,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter logic [N_SLAVES-1:0][31:0] SLAVE_ADDR_BASE = '0,
    parameter logic [N_SLAVES-1:0][31:0] SLAVE_ADDR_MASK = '0
)(
    input  logic                            clk_i,
    input  logic                            rst_ni,

    // Master (1)
    input  logic                            s_req_i,
    input  logic                            s_we_i,
    input  logic [ADDR_WIDTH-1:0]           s_addr_i,
    input  logic [DATA_WIDTH-1:0]           s_wdata_i,
    input  logic [(DATA_WIDTH/8)-1:0]       s_wstrb_i,
    output logic                            s_gnt_o,
    output logic                            s_rvalid_o,
    output logic [DATA_WIDTH-1:0]           s_rdata_o,
    output logic                            s_err_o,

    // Slaves (N)
    output logic [N_SLAVES-1:0]             m_req_o,
    output logic [N_SLAVES-1:0]             m_we_o,
    output logic [N_SLAVES-1:0][ADDR_WIDTH-1:0]  m_addr_o,
    output logic [N_SLAVES-1:0][DATA_WIDTH-1:0]  m_wdata_o,
    output logic [N_SLAVES-1:0][(DATA_WIDTH/8)-1:0] m_wstrb_o,
    input  logic [N_SLAVES-1:0]             m_gnt_i,
    input  logic [N_SLAVES-1:0]             m_rvalid_i,
    input  logic [N_SLAVES-1:0][DATA_WIDTH-1:0]  m_rdata_i,
    input  logic [N_SLAVES-1:0]             m_err_i
);

    logic [N_SLAVES-1:0] w_addr_match;

    always_comb begin
        w_addr_match = '0;
        for (int i = 0; i < N_SLAVES; i++) begin
            if ((s_addr_i & SLAVE_ADDR_MASK[i]) == (SLAVE_ADDR_BASE[i] & SLAVE_ADDR_MASK[i])) begin
                w_addr_match[i] = 1'b1;
                break; // Priority decoding: first match wins
            end
        end
    end

    // Master Request Routing
    always_comb begin
        s_gnt_o = 1'b0;
        for (int i = 0; i < N_SLAVES; i++) begin
            m_req_o[i]   = 1'b0;
            m_we_o[i]    = s_we_i;
            m_addr_o[i]  = s_addr_i;
            m_wdata_o[i] = s_wdata_i;
            m_wstrb_o[i] = s_wstrb_i;

            if (w_addr_match[i]) begin
                m_req_o[i] = s_req_i;
                s_gnt_o    = s_gnt_o | m_gnt_i[i];
            end
        end
    end

    // Slave Response Routing
    always_comb begin
        s_rvalid_o = 1'b0;
        s_rdata_o  = '0;
        s_err_o    = 1'b0;

        for (int i = 0; i < N_SLAVES; i++) begin
            if (m_rvalid_i[i]) begin
                s_rvalid_o = 1'b1;
                s_rdata_o  = m_rdata_i[i];
                s_err_o    = m_err_i[i];
            end
        end
    end

endmodule
