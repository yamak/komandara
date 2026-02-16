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

    // Request
    input  logic                         i_req,
    input  logic                         i_we,
    input  logic [ADDR_WIDTH-1:0]        i_addr,     // Word address
    input  logic [DATA_WIDTH-1:0]        i_wdata,
    input  logic [(DATA_WIDTH/8)-1:0]    i_wstrb,

    // Response  (1-cycle latency for reads)
    output logic                         o_rvalid,
    output logic [DATA_WIDTH-1:0]        o_rdata
);

    localparam int DEPTH = 2**ADDR_WIDTH;
    localparam int BYTES = DATA_WIDTH / 8;

    // -----------------------------------------------------------------------
    // Memory array  — written to infer BRAM
    // -----------------------------------------------------------------------
    (* ram_style = "block" *)   // Xilinx synthesis attribute
    logic [DATA_WIDTH-1:0] r_mem [0:DEPTH-1];

    // Optional initialisation
    generate
        if (INIT_FILE != "") begin : gen_init
            initial begin
                $display("[BRAM] Loading memory from: %s", INIT_FILE);
                $readmemh(INIT_FILE, r_mem);
                $display("[BRAM] mem[0] = %08h", r_mem[0]);
                $display("[BRAM] mem[1] = %08h", r_mem[1]);
            end
        end : gen_init
    endgenerate

    // -----------------------------------------------------------------------
    // Read data register  (synchronous read → infers BRAM output register)
    // -----------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] r_rdata;
    logic                  r_rvalid;

    always_ff @(posedge i_clk) begin
        r_rvalid <= 1'b0;

        if (i_req) begin
            if (i_we) begin
                // Byte-granular write
                for (int b = 0; b < BYTES; b++) begin
                    if (i_wstrb[b]) begin
                        r_mem[i_addr][b*8 +: 8] <= i_wdata[b*8 +: 8];
                    end
                end
            end

            // Read (even on write — read-first behaviour)
            r_rdata  <= r_mem[i_addr];
            r_rvalid <= 1'b1;
        end
    end

    assign o_rdata  = r_rdata;
    assign o_rvalid = r_rvalid;

endmodule : komandara_bram
