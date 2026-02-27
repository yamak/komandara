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
// K10 — Instruction Tracer  (Simulation Only)
// ============================================================================
// Produces a CSV instruction trace compatible with Google riscv-dv's
// instr_trace_compare.py.  Taps the WB stage signals to log every retired
// instruction including: PC, instruction binary, GPR write-back, and
// privilege mode.
//
// Output file format (CSV columns):
//   pc, instr, gpr, csr, binary, mode, instr_str, operand, pad
//
// Only the fields used by the comparator are populated:
//   pc     — hex address (no 0x prefix)
//   binary — hex instruction encoding (no 0x prefix)
//   gpr    — "abi_name:hex_value" when rd is written, empty otherwise
//   mode   — "3" for M-mode, "0" for U-mode
//
// This module is intended to be instantiated inside k10_core under:
//   `ifndef SYNTHESIS  /  `endif
// ============================================================================

`ifndef SYNTHESIS

module k10_tracer
  import komandara_k10_pkg::*;
#(
    parameter string TRACE_FILE = "k10_trace.csv"
)(
    input  logic        i_clk,
    input  logic        i_rst_n,

    // WB-stage commit signals
    input  logic        i_valid,      // Instruction retired
    input  logic [31:0] i_pc,         // Committed PC
    input  logic [31:0] i_instr,      // Instruction binary
    input  logic [4:0]  i_rd_addr,    // Destination register address
    input  logic [31:0] i_rd_data,    // Writeback data
    input  logic        i_rd_wr_en,   // Register file write enable
    input  priv_lvl_e   i_mode        // Current privilege level
);

    // -----------------------------------------------------------------------
    // ABI register name lookup
    // -----------------------------------------------------------------------
    function automatic string abi_name(input logic [4:0] addr);
        case (addr)
            5'd0:  return "zero";
            5'd1:  return "ra";
            5'd2:  return "sp";
            5'd3:  return "gp";
            5'd4:  return "tp";
            5'd5:  return "t0";
            5'd6:  return "t1";
            5'd7:  return "t2";
            5'd8:  return "s0";
            5'd9:  return "s1";
            5'd10: return "a0";
            5'd11: return "a1";
            5'd12: return "a2";
            5'd13: return "a3";
            5'd14: return "a4";
            5'd15: return "a5";
            5'd16: return "a6";
            5'd17: return "a7";
            5'd18: return "s2";
            5'd19: return "s3";
            5'd20: return "s4";
            5'd21: return "s5";
            5'd22: return "s6";
            5'd23: return "s7";
            5'd24: return "s8";
            5'd25: return "s9";
            5'd26: return "s10";
            5'd27: return "s11";
            5'd28: return "t3";
            5'd29: return "t4";
            5'd30: return "t5";
            5'd31: return "t6";
            default: return "??";
        endcase
    endfunction

    // -----------------------------------------------------------------------
    // File handle
    // -----------------------------------------------------------------------
    integer fd;

    initial begin
        fd = $fopen(TRACE_FILE, "w");
        if (fd == 0) begin
            $display("[K10_TRACER] ERROR: Cannot open %s", TRACE_FILE);
            $finish;
        end
        // Write CSV header (matches riscv_trace_csv.py field order)
        $fwrite(fd, "pc,instr,gpr,csr,binary,mode,instr_str,operand,pad\n");
    end

    // -----------------------------------------------------------------------
    // Trace logging — only instructions that write to a GPR
    // -----------------------------------------------------------------------
    // Spike's --log-commits only produces entries for instructions that
    // modify a GPR (or CSR).  To match, we skip stores, branches, ECALL,
    // FENCE, and any other instruction that does not write to a register.
    // -----------------------------------------------------------------------
    /* verilator lint_off BLKSEQ */
    // Debug: count retired instructions for full tracing
    integer instr_count;
    initial instr_count = 0;

    always @(posedge i_clk) begin
        if (i_rst_n && i_valid) begin
            instr_count = instr_count + 1;

            if (instr_count <= 200) begin
                // Log ALL retired instructions for first 200
                if (i_rd_wr_en && i_rd_addr != 5'd0) begin
                    $fwrite(fd, "%h,,\"%s:%h\",,%h,%0d,,,\n",
                            i_pc, abi_name(i_rd_addr), i_rd_data,
                            i_instr, (i_mode == PRIV_M) ? 3 : 0);
                end else begin
                    $fwrite(fd, "%h,,,,%h,%0d,,,\n",
                            i_pc, i_instr, (i_mode == PRIV_M) ? 3 : 0);
                end
            end else if (i_rd_wr_en && i_rd_addr != 5'd0) begin
                // After 200, only log GPR-writing instructions
                $fwrite(fd, "%h,,\"%s:%h\",,%h,%0d,,,\n",
                        i_pc, abi_name(i_rd_addr), i_rd_data,
                        i_instr, (i_mode == PRIV_M) ? 3 : 0);
            end
        end
    end

    // -----------------------------------------------------------------------
    // Close file on simulation end
    // -----------------------------------------------------------------------
    final begin
        if (fd != 0) begin
            $fclose(fd);
            $display("[K10_TRACER] Trace written to %s", TRACE_FILE);
        end
    end

endmodule : k10_tracer

`endif // SYNTHESIS
