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
// Komandara — Parametric BRAM  (Block RAM)
// ============================================================================
// Single-port byte-writable block RAM with synchronous read.
// Intended to infer FPGA block RAM (RAMB36E1/RAMB18E1 on Xilinx).
// For ASIC targets, this infers an SRAM array.
//
// Parameters:
//   ADDR_WIDTH — Determines memory depth:  2^ADDR_WIDTH words.
//   DATA_WIDTH — Word width (default 32).
//   INIT_FILE  — Optional hex file for initialisation (synthesis + sim).
//
// Interface:
//   Simple request/response.  Reads have 1-cycle latency.
//
// Shared infrastructure — not tied to any specific core version.
// ============================================================================

module komandara_bram #(
    parameter int ADDR_WIDTH = 14,   // 2^14 = 16K words = 64 KB
    parameter int DATA_WIDTH = 32,
    parameter     INIT_FILE  = ""
)(
    input  logic                         i_clk,

    // Port A Request
    input  logic                         i_req_a,
    input  logic                         i_we_a,
    input  logic [ADDR_WIDTH-1:0]        i_addr_a,     // Word address
    input  logic [DATA_WIDTH-1:0]        i_wdata_a,
    input  logic [(DATA_WIDTH/8)-1:0]    i_wstrb_a,

    // Port A Response  (1-cycle latency for reads)
    output logic                         o_rvalid_a,
    output logic [DATA_WIDTH-1:0]        o_rdata_a,

    // Port B Request
    input  logic                         i_req_b,
    input  logic                         i_we_b,
    input  logic [ADDR_WIDTH-1:0]        i_addr_b,     // Word address
    input  logic [DATA_WIDTH-1:0]        i_wdata_b,
    input  logic [(DATA_WIDTH/8)-1:0]    i_wstrb_b,

    // Port B Response  (1-cycle latency for reads)
    output logic                         o_rvalid_b,
    output logic [DATA_WIDTH-1:0]        o_rdata_b
);

    localparam int DEPTH = 2**ADDR_WIDTH;
    localparam int BYTES = DATA_WIDTH / 8;

    // -----------------------------------------------------------------------
    // Memory array  — written to infer True Dual-Port BRAM
    // -----------------------------------------------------------------------
    (* ram_style = "block" *)   // Xilinx synthesis attribute
    logic [DATA_WIDTH-1:0] r_mem [0:DEPTH-1];

    initial begin
`ifndef SYNTHESIS
        string fw_path;
        if ($value$plusargs("firmware=%s", fw_path)) begin
            $display("[BRAM] Loading runtime firmware from plusarg: %s", fw_path);
            $readmemh(fw_path, r_mem);
            $display("[BRAM] mem[0] = %08h", r_mem[0]);
            $display("[BRAM] mem[1] = %08h", r_mem[1]);
        end else
`endif
        begin
            // Optional compile-time initialisation
            if (INIT_FILE != "") begin
`ifndef SYNTHESIS
                $display("[BRAM] Loading memory from param: %s", INIT_FILE);
`endif
                $readmemh(INIT_FILE, r_mem);
`ifndef SYNTHESIS
                $display("[BRAM] mem[0] = %08h", r_mem[0]);
                $display("[BRAM] mem[1] = %08h", r_mem[1]);
`endif
            end
        end
    end

    // -----------------------------------------------------------------------
    // Read data registers  (synchronous read → infers BRAM output register)
    // -----------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] r_rdata_a, r_rdata_b;
    logic                  r_rvalid_a, r_rvalid_b;

    // Port A
    always_ff @(posedge i_clk) begin
        r_rvalid_a <= 1'b0;

        if (i_req_a) begin
            if (i_we_a) begin
                // Byte-granular write
                for (int b = 0; b < BYTES; b++) begin
                    if (i_wstrb_a[b]) begin
                        r_mem[i_addr_a][b*8 +: 8] <= i_wdata_a[b*8 +: 8];
                    end
                end
            end
            r_rdata_a  <= r_mem[i_addr_a];
            r_rvalid_a <= 1'b1;
        end
    end

    // Port B
    always_ff @(posedge i_clk) begin
        r_rvalid_b <= 1'b0;

        if (i_req_b) begin
            if (i_we_b) begin
                // Byte-granular write
                for (int b = 0; b < BYTES; b++) begin
                    if (i_wstrb_b[b]) begin
                        r_mem[i_addr_b][b*8 +: 8] <= i_wdata_b[b*8 +: 8];
                    end
                end
            end
            r_rdata_b  <= r_mem[i_addr_b];
            r_rvalid_b <= 1'b1;
        end
    end

    assign o_rdata_a  = r_rdata_a;
    assign o_rvalid_a = r_rvalid_a;

    assign o_rdata_b  = r_rdata_b;
    assign o_rvalid_b = r_rvalid_b;

endmodule : komandara_bram
