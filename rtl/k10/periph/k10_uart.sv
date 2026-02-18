// Copyright 2026 The Komandara Authors
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

module k10_uart #(
    parameter int unsigned CLK_FREQ_HZ = 50_000_000,
    parameter int unsigned BAUD_DEFAULT = 115200
)(
    input  logic        i_clk,
    input  logic        i_rst_n,

    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    input  logic        i_uart_rx,
    output logic        o_uart_tx,

    output logic        o_irq
);

    localparam int unsigned BAUD_DIV_DEFAULT = CLK_FREQ_HZ / BAUD_DEFAULT;

    logic        r_aw_pending;
    logic [5:0]  r_aw_addr;
    logic        r_w_pending;
    logic [31:0] r_w_data;
    logic        r_bvalid;

    logic        r_rvalid;
    logic [31:0] r_rdata;

    logic [31:0] r_baud_div;

    logic [9:0]  r_tx_shift;
    logic [31:0] r_tx_cnt;
    logic [3:0]  r_tx_bit_idx;
    logic        r_tx_busy;

    logic [7:0]  r_rx_data;
    logic [7:0]  r_rx_shift;
    logic [31:0] r_rx_cnt;
    logic [3:0]  r_rx_bit_idx;
    logic        r_rx_busy;
    logic        r_rx_valid;

    logic        r_irq_rx_en;
    logic        r_irq_tx_en;
    logic        r_irq_rx_pending;
    logic        r_irq_tx_pending;

    logic w_tx_ready;
    logic w_rx_take;

    assign w_tx_ready = !r_tx_busy;
    assign w_rx_take = s_axi_arvalid && s_axi_arready && (s_axi_araddr[5:2] == 4'h0) && r_rx_valid;

    assign s_axi_awready = !r_aw_pending && !r_bvalid;
    assign s_axi_wready  = !r_w_pending && !r_bvalid;
    assign s_axi_bvalid  = r_bvalid;
    assign s_axi_bresp   = 2'b00;

    assign s_axi_arready = !r_rvalid || s_axi_rready;
    assign s_axi_rvalid  = r_rvalid;
    assign s_axi_rdata   = r_rdata;
    assign s_axi_rresp   = 2'b00;

    assign o_uart_tx = r_tx_busy ? r_tx_shift[0] : 1'b1;
    assign o_irq = (r_irq_rx_pending && r_irq_rx_en) ||
                   (r_irq_tx_pending && r_irq_tx_en);

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_aw_pending    <= 1'b0;
            r_aw_addr       <= '0;
            r_w_pending     <= 1'b0;
            r_w_data        <= '0;
            r_bvalid        <= 1'b0;
            r_rvalid        <= 1'b0;
            r_rdata         <= '0;

            r_baud_div      <= BAUD_DIV_DEFAULT;

            r_tx_shift      <= 10'h3ff;
            r_tx_cnt        <= '0;
            r_tx_bit_idx    <= '0;
            r_tx_busy       <= 1'b0;

            r_rx_data       <= '0;
            r_rx_shift      <= '0;
            r_rx_cnt        <= '0;
            r_rx_bit_idx    <= '0;
            r_rx_busy       <= 1'b0;
            r_rx_valid      <= 1'b0;

            r_irq_rx_en     <= 1'b0;
            r_irq_tx_en     <= 1'b0;
            r_irq_rx_pending <= 1'b0;
            r_irq_tx_pending <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                r_aw_pending <= 1'b1;
                r_aw_addr    <= s_axi_awaddr[5:0];
            end

            if (s_axi_wvalid && s_axi_wready) begin
                r_w_pending <= 1'b1;
                r_w_data    <= s_axi_wdata;
            end

            if (r_aw_pending && r_w_pending && !r_bvalid) begin
                r_aw_pending <= 1'b0;
                r_w_pending  <= 1'b0;
                r_bvalid     <= 1'b1;

                unique case (r_aw_addr[5:2])
                    4'h0: begin
                        if (w_tx_ready) begin
                            r_tx_shift   <= {1'b1, r_w_data[7:0], 1'b0};
                            r_tx_busy    <= 1'b1;
                            r_tx_bit_idx <= 4'd0;
                            r_tx_cnt     <= (r_baud_div > 0) ? (r_baud_div - 1) : 32'd0;
                            r_irq_tx_pending <= 1'b0;
                        end
                    end
                    4'h2: begin
                        r_irq_tx_en <= r_w_data[0];
                        r_irq_rx_en <= r_w_data[1];
                    end
                    4'h3: begin
                        if (r_w_data != 32'd0) begin
                            r_baud_div <= r_w_data;
                        end
                    end
                    4'h4: begin
                        if (r_w_data[0]) r_irq_tx_pending <= 1'b0;
                        if (r_w_data[1]) r_irq_rx_pending <= 1'b0;
                    end
                    default: ;
                endcase
            end

            if (r_bvalid && s_axi_bready) begin
                r_bvalid <= 1'b0;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                r_rvalid <= 1'b1;
                unique case (s_axi_araddr[5:2])
                    4'h0: r_rdata <= {24'd0, r_rx_data};
                    4'h1: r_rdata <= {28'd0, r_irq_rx_pending, r_irq_tx_pending, r_rx_valid, w_tx_ready};
                    4'h2: r_rdata <= {30'd0, r_irq_rx_en, r_irq_tx_en};
                    4'h3: r_rdata <= r_baud_div;
                    4'h4: r_rdata <= {30'd0, r_irq_rx_pending, r_irq_tx_pending};
                    default: r_rdata <= 32'd0;
                endcase
            end

            if (r_rvalid && s_axi_rready) begin
                r_rvalid <= 1'b0;
            end

            if (w_rx_take) begin
                r_rx_valid <= 1'b0;
                r_irq_rx_pending <= 1'b0;
            end

            if (r_tx_busy) begin
                if (r_tx_cnt == 0) begin
                    r_tx_cnt <= (r_baud_div > 0) ? (r_baud_div - 1) : 32'd0;
                    r_tx_shift <= {1'b1, r_tx_shift[9:1]};
                    if (r_tx_bit_idx == 4'd9) begin
                        r_tx_busy <= 1'b0;
                        r_irq_tx_pending <= 1'b1;
                    end else begin
                        r_tx_bit_idx <= r_tx_bit_idx + 1'b1;
                    end
                end else begin
                    r_tx_cnt <= r_tx_cnt - 1'b1;
                end
            end

            if (!r_rx_busy) begin
                if (i_uart_rx == 1'b0) begin
                    r_rx_busy    <= 1'b1;
                    r_rx_bit_idx <= 4'd0;
                    r_rx_cnt     <= (r_baud_div >> 1);
                    r_rx_shift   <= 8'd0;
                end
            end else begin
                if (r_rx_cnt == 0) begin
                    if (r_rx_bit_idx == 4'd0) begin
                        if (i_uart_rx == 1'b0) begin
                            r_rx_bit_idx <= 4'd1;
                            r_rx_cnt <= (r_baud_div > 0) ? (r_baud_div - 1) : 32'd0;
                        end else begin
                            r_rx_busy <= 1'b0;
                        end
                    end else if (r_rx_bit_idx <= 4'd8) begin
                        r_rx_shift[r_rx_bit_idx[2:0] - 3'd1] <= i_uart_rx;
                        r_rx_bit_idx <= r_rx_bit_idx + 1'b1;
                        r_rx_cnt <= (r_baud_div > 0) ? (r_baud_div - 1) : 32'd0;
                    end else begin
                        r_rx_busy <= 1'b0;
                        if (i_uart_rx == 1'b1) begin
                            r_rx_data <= r_rx_shift;
                            r_rx_valid <= 1'b1;
                            r_irq_rx_pending <= 1'b1;
                        end
                    end
                end else begin
                    r_rx_cnt <= r_rx_cnt - 1'b1;
                end
            end
        end
    end

endmodule : k10_uart
