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
// Komandara — AXI4 Full Slave (SRAM-backed, burst-capable)
// ============================================================================
// Supports FIXED, INCR, WRAP bursts. Byte-addressable internal memory.
// Independent write and read paths.
// ============================================================================

module komandara_axi4_slave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int MEM_DEPTH  = 4096   // bytes
)(
    input  logic clk_i,
    input  logic rst_ni,

    // Write Address
    input  logic [ID_WIDTH-1:0]       s_axi_awid_i,
    input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr_i,
    input  logic [7:0]                s_axi_awlen_i,
    input  logic [2:0]                s_axi_awsize_i,
    input  logic [1:0]                s_axi_awburst_i,
    input  logic                      s_axi_awvalid_i,
    output logic                      s_axi_awready_o,

    // Write Data
    input  logic [DATA_WIDTH-1:0]     s_axi_wdata_i,
    input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb_i,
    input  logic                      s_axi_wlast_i,
    input  logic                      s_axi_wvalid_i,
    output logic                      s_axi_wready_o,

    // Write Response
    output logic [ID_WIDTH-1:0]       s_axi_bid_o,
    output logic [1:0]                s_axi_bresp_o,
    output logic                      s_axi_bvalid_o,
    input  logic                      s_axi_bready_i,

    // Read Address
    input  logic [ID_WIDTH-1:0]       s_axi_arid_i,
    input  logic [ADDR_WIDTH-1:0]     s_axi_araddr_i,
    input  logic [7:0]                s_axi_arlen_i,
    input  logic [2:0]                s_axi_arsize_i,
    input  logic [1:0]                s_axi_arburst_i,
    input  logic                      s_axi_arvalid_i,
    output logic                      s_axi_arready_o,

    // Read Data
    output logic [ID_WIDTH-1:0]       s_axi_rid_o,
    output logic [DATA_WIDTH-1:0]     s_axi_rdata_o,
    output logic [1:0]                s_axi_rresp_o,
    output logic                      s_axi_rlast_o,
    output logic                      s_axi_rvalid_o,
    input  logic                      s_axi_rready_i
);

    import komandara_axi4_pkg::*;

    localparam int STRB_WIDTH    = DATA_WIDTH / 8;
    localparam int MEM_ADDR_BITS = $clog2(MEM_DEPTH);

    // --------------------------------------------------------
    // Memory
    // --------------------------------------------------------
    logic [7:0] r_mem [MEM_DEPTH];

    // --------------------------------------------------------
    // Address helpers
    // --------------------------------------------------------
    function automatic logic [ADDR_WIDTH-1:0] f_next_addr(
        input logic [ADDR_WIDTH-1:0] cur,
        input logic [ADDR_WIDTH-1:0] start,
        input logic [7:0]            len,
        input logic [2:0]            size,
        input logic [1:0]            burst
    );
        logic [ADDR_WIDTH-1:0] incr      = ADDR_WIDTH'(1) << size;
        logic [ADDR_WIDTH-1:0] next_incr = cur + incr;
        case (burst)
            2'b00:   return cur;           // FIXED
            2'b01:   return next_incr;     // INCR
            2'b10: begin                   // WRAP
                logic [ADDR_WIDTH-1:0] wrap_sz = (ADDR_WIDTH'(len) + 1) << size;
                logic [ADDR_WIDTH-1:0] lower   = start & ~(wrap_sz - 1);
                return lower | (next_incr & (wrap_sz - 1));
            end
            default: return next_incr;
        endcase
    endfunction

    // --------------------------------------------------------
    // Write Path FSM
    // --------------------------------------------------------
    typedef enum logic [1:0] {WR_IDLE, WR_DATA, WR_RESP} wr_state_e;
    wr_state_e r_wr_state;

    logic [ID_WIDTH-1:0]       r_wr_id;
    logic [ADDR_WIDTH-1:0]     r_wr_addr;
    logic [ADDR_WIDTH-1:0]     r_wr_start;
    logic [7:0]                r_wr_len;
    logic [2:0]                r_wr_size;
    logic [1:0]                r_wr_burst;

    assign s_axi_awready_o = (r_wr_state == WR_IDLE);
    assign s_axi_wready_o  = (r_wr_state == WR_DATA);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_wr_state     <= WR_IDLE;
            s_axi_bvalid_o <= 1'b0;
            s_axi_bid_o    <= '0;
            s_axi_bresp_o  <= 2'b00;
        end else begin
            case (r_wr_state)
                WR_IDLE: begin
                    if (s_axi_awvalid_i && s_axi_awready_o) begin
                        r_wr_id    <= s_axi_awid_i;
                        r_wr_addr  <= s_axi_awaddr_i;
                        r_wr_start <= s_axi_awaddr_i;
                        r_wr_len   <= s_axi_awlen_i;
                        r_wr_size  <= s_axi_awsize_i;
                        r_wr_burst <= s_axi_awburst_i;
                        r_wr_state <= WR_DATA;
                    end
                    // Clear B when accepted
                    if (s_axi_bvalid_o && s_axi_bready_i)
                        s_axi_bvalid_o <= 1'b0;
                end

                WR_DATA: begin
                    if (s_axi_wvalid_i && s_axi_wready_o) begin
                        // Write bytes to memory
                        for (int b = 0; b < STRB_WIDTH; b++) begin
                            if (s_axi_wstrb_i[b])
                                r_mem[r_wr_addr[MEM_ADDR_BITS-1:0] + b[MEM_ADDR_BITS-1:0]]
                                    <= s_axi_wdata_i[b*8 +: 8];
                        end
                        // Advance address
                        r_wr_addr <= f_next_addr(r_wr_addr, r_wr_start,
                                                 r_wr_len, r_wr_size, r_wr_burst);
                        if (s_axi_wlast_i) begin
                            r_wr_state     <= WR_RESP;
                            s_axi_bvalid_o <= 1'b1;
                            s_axi_bid_o    <= r_wr_id;
                            s_axi_bresp_o  <= AXI_RESP_OKAY;
                        end
                    end
                end

                WR_RESP: begin
                    if (s_axi_bvalid_o && s_axi_bready_i) begin
                        s_axi_bvalid_o <= 1'b0;
                        r_wr_state     <= WR_IDLE;
                    end
                end

                default: r_wr_state <= WR_IDLE;
            endcase
        end
    end

    // --------------------------------------------------------
    // Read Path FSM
    // --------------------------------------------------------
    typedef enum logic [1:0] {RD_IDLE, RD_DATA} rd_state_e;
    rd_state_e r_rd_state;

    logic [ID_WIDTH-1:0]       r_rd_id;
    logic [ADDR_WIDTH-1:0]     r_rd_addr;
    logic [ADDR_WIDTH-1:0]     r_rd_start;
    logic [7:0]                r_rd_len;
    logic [2:0]                r_rd_size;
    logic [1:0]                r_rd_burst;
    logic [7:0]                r_rd_beat_cnt; // remaining beats

    assign s_axi_arready_o = (r_rd_state == RD_IDLE);
    assign s_axi_rid_o     = r_rd_id;
    assign s_axi_rresp_o   = AXI_RESP_OKAY;
    assign s_axi_rlast_o   = (r_rd_state == RD_DATA) && (r_rd_beat_cnt == 0);
    assign s_axi_rvalid_o  = (r_rd_state == RD_DATA);

    // Combinational read from memory
    always_comb begin
        s_axi_rdata_o = '0;
        for (int b = 0; b < STRB_WIDTH; b++)
            s_axi_rdata_o[b*8 +: 8] = r_mem[r_rd_addr[MEM_ADDR_BITS-1:0]
                                             + b[MEM_ADDR_BITS-1:0]];
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_rd_state    <= RD_IDLE;
            r_rd_beat_cnt <= '0;
        end else begin
            case (r_rd_state)
                RD_IDLE: begin
                    if (s_axi_arvalid_i && s_axi_arready_o) begin
                        r_rd_id       <= s_axi_arid_i;
                        r_rd_addr     <= s_axi_araddr_i;
                        r_rd_start    <= s_axi_araddr_i;
                        r_rd_len      <= s_axi_arlen_i;
                        r_rd_size     <= s_axi_arsize_i;
                        r_rd_burst    <= s_axi_arburst_i;
                        r_rd_beat_cnt <= s_axi_arlen_i;
                        r_rd_state    <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (s_axi_rvalid_o && s_axi_rready_i) begin
                        if (r_rd_beat_cnt == 0) begin
                            r_rd_state <= RD_IDLE;
                        end else begin
                            r_rd_addr     <= f_next_addr(r_rd_addr, r_rd_start,
                                                         r_rd_len, r_rd_size, r_rd_burst);
                            r_rd_beat_cnt <= r_rd_beat_cnt - 8'd1;
                        end
                    end
                end

                default: r_rd_state <= RD_IDLE;
            endcase
        end
    end

    // --------------------------------------------------------
    // Memory init
    // --------------------------------------------------------
    initial begin
        for (int i = 0; i < MEM_DEPTH; i++)
            r_mem[i] = 8'h00;
    end

endmodule
