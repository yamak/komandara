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
// K10 — Simulation Controller (AXI4-Lite Slave)
// ============================================================================
// Simulation-only peripheral (similar to Ibex sim_ctrl).
// Provides software-controlled console output and simulation control.
//
// Register Map (byte offsets from base):
//   0x00  SIM_CTRL   — Write 0x1 = PASS + $finish, 0x0 = FAIL + $finish  (W)
//   0x04  CHAR_OUT   — Write byte → $write("%c", data[7:0])              (W)
//   0x08  SIM_STATUS — Read: cycle count [31:0]                           (R)
//   0x0C  reserved
//
// Use CHAR_OUT for software printf — each write emits one character.
// Use SIM_CTRL to terminate simulation with pass/fail status.
// ============================================================================

module k10_sim_ctrl (
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

    // ---- Software interrupt output ----
    output logic        o_sw_irq
);

    // -----------------------------------------------------------------------
    // Cycle counter (for SIM_STATUS register)
    // -----------------------------------------------------------------------
    logic [31:0] r_cycle_count;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            r_cycle_count <= 32'd0;
        else
            r_cycle_count <= r_cycle_count + 32'd1;
    end

    // -----------------------------------------------------------------------
    // MSIP register (software interrupt)
    // -----------------------------------------------------------------------
    logic r_msip;
    assign o_sw_irq = r_msip;

    // -----------------------------------------------------------------------
    // Write channel — simplified AXI4-Lite (accept AW+W together)
    // -----------------------------------------------------------------------
    // We use a simple approach: accept AW and W simultaneously.
    // If only one arrives, latch it and wait for the other.
    logic        r_aw_pending;
    logic [3:0]  r_aw_addr;
    logic        r_w_pending;
    logic [31:0] r_w_data;
    logic        r_bvalid;

    assign s_axi_awready = !r_aw_pending || (r_w_pending && !r_bvalid);
    assign s_axi_wready  = !r_w_pending || (r_aw_pending && !r_bvalid);
    assign s_axi_bvalid  = r_bvalid;
    assign s_axi_bresp   = 2'b00;

    // -----------------------------------------------------------------------
    // Read channel
    // -----------------------------------------------------------------------
    logic        r_rvalid;
    logic [31:0] r_rdata;

    assign s_axi_arready = !r_rvalid || s_axi_rready;
    assign s_axi_rvalid  = r_rvalid;
    assign s_axi_rdata   = r_rdata;
    assign s_axi_rresp   = 2'b00;

    // -----------------------------------------------------------------------
    // Sequential logic
    // -----------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_aw_pending <= 1'b0;
            r_aw_addr    <= 4'd0;
            r_w_pending  <= 1'b0;
            r_w_data     <= 32'd0;
            r_bvalid     <= 1'b0;
            r_rvalid     <= 1'b0;
            r_rdata      <= 32'd0;
            r_msip       <= 1'b0;
        end else begin

            // ---- Write address capture ----
            if (s_axi_awvalid && s_axi_awready) begin
                r_aw_pending <= 1'b1;
                r_aw_addr    <= s_axi_awaddr[3:0];
            end

            // ---- Write data capture ----
            if (s_axi_wvalid && s_axi_wready) begin
                r_w_pending <= 1'b1;
                r_w_data    <= s_axi_wdata;
            end

            // ---- Execute write ----
            if (r_aw_pending && r_w_pending && !r_bvalid) begin
                r_aw_pending <= 1'b0;
                r_w_pending  <= 1'b0;
                r_bvalid     <= 1'b1;

                unique case (r_aw_addr[3:2])
                    2'b00: begin  // 0x00: SIM_CTRL
                        // synthesis translate_off
                        if (r_w_data[0]) begin
                            $display("\n[SIM_CTRL] *** TEST PASSED ***");
                        end else begin
                            $display("\n[SIM_CTRL] *** TEST FAILED ***");
                        end
                        $finish;
                        // synthesis translate_on
                    end
                    2'b01: begin  // 0x04: CHAR_OUT
                        // synthesis translate_off
                        $write("%c", r_w_data[7:0]);
                        // synthesis translate_on
                    end
                    2'b10: begin  // 0x08: MSIP (software interrupt)
                        r_msip <= r_w_data[0];
                    end
                    2'b11: ;  // 0x0C: reserved
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
                    2'b00:   r_rdata <= 32'd0;         // SIM_CTRL: write-only
                    2'b01:   r_rdata <= 32'd0;         // CHAR_OUT: write-only
                    2'b10:   r_rdata <= {31'd0, r_msip}; // MSIP
                    2'b11:   r_rdata <= r_cycle_count;  // SIM_STATUS
                endcase
            end

            if (r_rvalid && s_axi_rready) begin
                r_rvalid <= 1'b0;
            end
        end
    end

endmodule : k10_sim_ctrl
