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
// K10 — Timer Peripheral (AXI4-Lite Slave)
// ============================================================================
// RISC-V compatible timer with mtime and mtimecmp registers.
//
// Register Map (byte offsets from base):
//   0x00  mtime_lo    — Timer counter [31:0]   (R/W)
//   0x04  mtime_hi    — Timer counter [63:32]  (R/W)
//   0x08  mtimecmp_lo — Timer compare [31:0]   (R/W)
//   0x0C  mtimecmp_hi — Timer compare [63:32]  (R/W)
//
// Timer interrupt: asserted when mtime >= mtimecmp.
// mtime auto-increments every clock cycle; writable for testing.
// ============================================================================

module k10_timer (
    input  logic        i_clk,
    input  logic        i_rst_n,

    // ---- AXI4-Lite Slave ----
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

    // ---- Timer outputs ----
    output logic        o_timer_irq,
    output logic [63:0] o_mtime
);

    // -----------------------------------------------------------------------
    // Timer registers
    // -----------------------------------------------------------------------
    logic [63:0] r_mtime;
    logic [63:0] r_mtimecmp;

    assign o_mtime     = r_mtime;
    assign o_timer_irq = (r_mtime >= r_mtimecmp);

    // -----------------------------------------------------------------------
    // Write channel
    // -----------------------------------------------------------------------
    logic        r_aw_pending;
    logic [3:0]  r_aw_addr;  // offset bits [3:0]
    logic        r_w_pending;
    logic [31:0] r_w_data;
    logic [3:0]  r_w_strb;

    // Accept address and data independently
    assign s_axi_awready = !r_aw_pending || (r_w_pending && !s_axi_bvalid);
    assign s_axi_wready  = !r_w_pending || (r_aw_pending && !s_axi_bvalid);

    // Write response
    logic r_bvalid;
    assign s_axi_bvalid = r_bvalid;
    assign s_axi_bresp  = 2'b00;  // OKAY

    // -----------------------------------------------------------------------
    // Read channel
    // -----------------------------------------------------------------------
    logic        r_rvalid;
    logic [31:0] r_rdata;

    assign s_axi_arready = !r_rvalid || s_axi_rready;
    assign s_axi_rvalid  = r_rvalid;
    assign s_axi_rdata   = r_rdata;
    assign s_axi_rresp   = 2'b00;  // OKAY

    // -----------------------------------------------------------------------
    // Sequential logic
    // -----------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_mtime      <= 64'd0;
            r_mtimecmp   <= 64'hFFFF_FFFF_FFFF_FFFF;  // Max value = no interrupt
            r_aw_pending <= 1'b0;
            r_aw_addr    <= 4'd0;
            r_w_pending  <= 1'b0;
            r_w_data     <= 32'd0;
            r_w_strb     <= 4'd0;
            r_bvalid     <= 1'b0;
            r_rvalid     <= 1'b0;
            r_rdata      <= 32'd0;
        end else begin
            // ---- mtime auto-increment ----
            r_mtime <= r_mtime + 64'd1;

            // ---- Write address capture ----
            if (s_axi_awvalid && s_axi_awready) begin
                r_aw_pending <= 1'b1;
                r_aw_addr    <= s_axi_awaddr[3:0];
            end

            // ---- Write data capture ----
            if (s_axi_wvalid && s_axi_wready) begin
                r_w_pending <= 1'b1;
                r_w_data    <= s_axi_wdata;
                r_w_strb    <= s_axi_wstrb;
            end

            // ---- Execute write ----
            if (r_aw_pending && r_w_pending && !r_bvalid) begin
                r_aw_pending <= 1'b0;
                r_w_pending  <= 1'b0;
                r_bvalid     <= 1'b1;

                unique case (r_aw_addr[3:2])
                    2'b00: begin  // 0x00: mtime_lo
                        if (r_w_strb[0]) r_mtime[7:0]   <= r_w_data[7:0];
                        if (r_w_strb[1]) r_mtime[15:8]   <= r_w_data[15:8];
                        if (r_w_strb[2]) r_mtime[23:16]  <= r_w_data[23:16];
                        if (r_w_strb[3]) r_mtime[31:24]  <= r_w_data[31:24];
                    end
                    2'b01: begin  // 0x04: mtime_hi
                        if (r_w_strb[0]) r_mtime[39:32]  <= r_w_data[7:0];
                        if (r_w_strb[1]) r_mtime[47:40]  <= r_w_data[15:8];
                        if (r_w_strb[2]) r_mtime[55:48]  <= r_w_data[23:16];
                        if (r_w_strb[3]) r_mtime[63:56]  <= r_w_data[31:24];
                    end
                    2'b10: begin  // 0x08: mtimecmp_lo
                        if (r_w_strb[0]) r_mtimecmp[7:0]   <= r_w_data[7:0];
                        if (r_w_strb[1]) r_mtimecmp[15:8]   <= r_w_data[15:8];
                        if (r_w_strb[2]) r_mtimecmp[23:16]  <= r_w_data[23:16];
                        if (r_w_strb[3]) r_mtimecmp[31:24]  <= r_w_data[31:24];
                    end
                    2'b11: begin  // 0x0C: mtimecmp_hi
                        if (r_w_strb[0]) r_mtimecmp[39:32]  <= r_w_data[7:0];
                        if (r_w_strb[1]) r_mtimecmp[47:40]  <= r_w_data[15:8];
                        if (r_w_strb[2]) r_mtimecmp[55:48]  <= r_w_data[23:16];
                        if (r_w_strb[3]) r_mtimecmp[63:56]  <= r_w_data[31:24];
                    end
                endcase
            end

            // ---- Write response handshake ----
            if (r_bvalid && s_axi_bready) begin
                r_bvalid <= 1'b0;
            end

            // ---- Read ----
            if (s_axi_arvalid && s_axi_arready) begin
                r_rvalid <= 1'b1;
                unique case (s_axi_araddr[3:2])
                    2'b00: r_rdata <= r_mtime[31:0];
                    2'b01: r_rdata <= r_mtime[63:32];
                    2'b10: r_rdata <= r_mtimecmp[31:0];
                    2'b11: r_rdata <= r_mtimecmp[63:32];
                endcase
            end

            if (r_rvalid && s_axi_rready) begin
                r_rvalid <= 1'b0;
            end
        end
    end

endmodule : k10_timer
