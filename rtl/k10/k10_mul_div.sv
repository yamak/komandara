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
// K10 — Multiply / Divide Unit  (M extension)
// ============================================================================
// Multiplies are single-cycle (combinational `*`; synthesis handles it).
// Divides / remainders are iterative restoring division (32 cycles).
//
// Interface protocol:
//   i_start  — held high while an MD instruction occupies the EX stage.
//   o_busy   — high during CALC (stalls pipeline).  Low at DONE (pipeline
//              captures result and advances).
//   o_done   — high when the result is valid.
//   o_result — the 32-bit result.
//
// FSM: IDLE → CALC (32 iterations) → DONE → IDLE
//
// In DONE state: o_busy=0, o_done=1.  The pipeline samples w_ex_result and
// advances the instruction from EX → MEM.  We remain in DONE until
// i_start drops (confirming the instruction left EX), then go to IDLE.
// This avoids any restart race conditions.
// ============================================================================

module k10_mul_div
  import komandara_k10_pkg::*;
(
    input  logic        i_clk,
    input  logic        i_rst_n,

    input  logic        i_start,    // = r_id_ex.valid && r_id_ex.ctrl.md_en
    input  md_op_e      i_op,
    input  logic [31:0] i_a,        // rs1
    input  logic [31:0] i_b,        // rs2

    output logic        o_busy,
    output logic        o_done,
    output logic [31:0] o_result
);

    // -----------------------------------------------------------------------
    // Multiply (single cycle — combinational)
    // -----------------------------------------------------------------------
    logic [63:0] w_mul_ss;   // signed   × signed
    logic [63:0] w_mul_su;   // signed   × unsigned
    logic [63:0] w_mul_uu;   // unsigned × unsigned

    assign w_mul_ss = $signed(i_a) * $signed(i_b);
    assign w_mul_su = $signed({{32{i_a[31]}}, i_a}) * $signed({1'b0, i_b});
    assign w_mul_uu = {32'd0, i_a} * {32'd0, i_b};

    // -----------------------------------------------------------------------
    // Classification helpers
    // -----------------------------------------------------------------------
    logic w_is_mul;
    assign w_is_mul = (i_op == MD_MUL)    || (i_op == MD_MULH)  ||
                      (i_op == MD_MULHSU) || (i_op == MD_MULHU);

    logic w_is_rem;
    assign w_is_rem = (i_op == MD_REM) || (i_op == MD_REMU);

    logic w_is_signed;
    assign w_is_signed = (i_op == MD_DIV) || (i_op == MD_REM);

    logic w_is_div_request;
    assign w_is_div_request = i_start && !w_is_mul;

    // -----------------------------------------------------------------------
    // Divide / Remainder — iterative restoring division
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] {
        DIV_IDLE,
        DIV_CALC,
        DIV_DONE
    } div_state_e;

    div_state_e r_state, w_state_next;

    logic [31:0] r_dividend;
    logic [31:0] r_divisor;
    logic [31:0] r_quotient;
    logic [31:0] r_remainder;
    logic [5:0]  r_count;        // 0..31
    logic        r_sign_q;       // sign of quotient
    logic        r_sign_r;       // sign of remainder
    logic        r_is_rem;       // 1 = REM/REMU, 0 = DIV/DIVU
    logic        r_div_by_zero;
    logic [31:0] r_orig_dividend; // Saved for div-by-zero remainder

    logic [32:0] w_sub;          // trial subtraction

    // -----------------------------------------------------------------------
    // Division datapath
    // -----------------------------------------------------------------------
    assign w_sub = {r_remainder, r_dividend[31]} - {1'b0, r_divisor};

    // -----------------------------------------------------------------------
    // Division FSM — combinational next-state
    // -----------------------------------------------------------------------
    always_comb begin
        w_state_next = r_state;

        unique case (r_state)
            DIV_IDLE: begin
                if (w_is_div_request) begin
                    w_state_next = DIV_CALC;
                end
            end
            DIV_CALC: begin
                if (r_count == 6'd31) begin
                    w_state_next = DIV_DONE;
                end
            end
            DIV_DONE: begin
                // Stay in DONE until the instruction leaves EX
                if (!w_is_div_request) begin
                    w_state_next = DIV_IDLE;
                end
            end
            default: w_state_next = DIV_IDLE;
        endcase
    end

    // -----------------------------------------------------------------------
    // Division FSM — sequential
    // -----------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state        <= DIV_IDLE;
            r_dividend     <= 32'd0;
            r_divisor      <= 32'd0;
            r_quotient     <= 32'd0;
            r_remainder    <= 32'd0;
            r_count        <= 6'd0;
            r_sign_q       <= 1'b0;
            r_sign_r       <= 1'b0;
            r_is_rem       <= 1'b0;
            r_div_by_zero  <= 1'b0;
            r_orig_dividend <= 32'd0;
        end else begin
            r_state <= w_state_next;

            unique case (r_state)
                DIV_IDLE: begin
                    if (w_is_div_request) begin
                        r_count       <= 6'd0;
                        r_quotient    <= 32'd0;
                        r_remainder   <= 32'd0;
                        r_is_rem      <= w_is_rem;
                        r_div_by_zero <= (i_b == 32'd0);

                        if (w_is_signed) begin
                            r_dividend      <= i_a[31] ? (~i_a + 32'd1) : i_a;
                            r_divisor       <= i_b[31] ? (~i_b + 32'd1) : i_b;
                            r_sign_q        <= i_a[31] ^ i_b[31];
                            r_sign_r        <= i_a[31];
                            r_orig_dividend <= i_a;  // Save original (signed) dividend
                        end else begin
                            r_dividend      <= i_a;
                            r_divisor       <= i_b;
                            r_sign_q        <= 1'b0;
                            r_sign_r        <= 1'b0;
                            r_orig_dividend <= i_a;  // Save original dividend
                        end
                    end
                end

                DIV_CALC: begin
                    r_count <= r_count + 6'd1;
                    if (!w_sub[32]) begin
                        // Subtraction succeeded
                        r_remainder <= w_sub[31:0];
                        r_quotient  <= {r_quotient[30:0], 1'b1};
                    end else begin
                        // Subtraction failed — restore
                        r_remainder <= {r_remainder[30:0], r_dividend[31]};
                        r_quotient  <= {r_quotient[30:0], 1'b0};
                    end
                    r_dividend <= {r_dividend[30:0], 1'b0};
                end

                DIV_DONE: begin
                    // Hold — registers are stable; output mux reads them.
                end

                default: ;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Output mux — sign correction applied combinationally
    // -----------------------------------------------------------------------
    logic [31:0] w_adj_quotient;
    logic [31:0] w_adj_remainder;
    logic [31:0] w_div_result;

    assign w_adj_quotient  = r_sign_q ? (~r_quotient  + 32'd1) : r_quotient;
    assign w_adj_remainder = r_sign_r ? (~r_remainder + 32'd1) : r_remainder;

    always_comb begin
        if (r_div_by_zero) begin
            // RISC-V spec: div by zero → quotient = all-ones, remainder = dividend
            w_div_result = r_is_rem ? r_orig_dividend : 32'hFFFF_FFFF;
        end else begin
            w_div_result = r_is_rem ? w_adj_remainder : w_adj_quotient;
        end
    end

    always_comb begin
        o_result = 32'd0;

        if (w_is_mul && i_start) begin
            unique case (i_op)
                MD_MUL:    o_result = w_mul_ss[31:0];
                MD_MULH:   o_result = w_mul_ss[63:32];
                MD_MULHSU: o_result = w_mul_su[63:32];
                MD_MULHU:  o_result = w_mul_uu[63:32];
                default:   o_result = 32'd0;
            endcase
        end else begin
            o_result = w_div_result;
        end
    end

    // -----------------------------------------------------------------------
    // Status
    // -----------------------------------------------------------------------
    // o_busy: stalls the pipeline during CALC (and the start cycle IDLE→CALC).
    //         NOT asserted during DONE — the pipeline must capture the result.
    assign o_busy = (r_state == DIV_CALC) ||
                    (r_state == DIV_IDLE && w_is_div_request);

    // o_done: result is valid.
    //   - Multiplies: every cycle the instruction is in EX.
    //   - Divides: during DIV_DONE.
    assign o_done = (w_is_mul && i_start) ||
                    (r_state == DIV_DONE);

endmodule : k10_mul_div
