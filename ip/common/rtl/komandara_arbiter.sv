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
// Komandara - Parametric Arbiter (Round-Robin / Fixed Priority)
// ============================================================================
// Combinational arbiter with registered RR pointer. Supports:
//   - ROUND_ROBIN = 1 : Fair round-robin arbitration
//   - ROUND_ROBIN = 0 : Fixed priority (lower index = higher priority)
//
// Shared infrastructure — not tied to any specific core version.
//
// Usage: assert advance_i for one cycle when the granted transaction
//        completes, to rotate the RR pointer.
// ============================================================================

module komandara_arbiter #(
    parameter int N_REQ       = 2,
    parameter bit ROUND_ROBIN = 1'b1
)(
    input  logic              clk_i,
    input  logic              rst_ni,

    input  logic [N_REQ-1:0]  req_i,      // Request vector
    input  logic              advance_i,   // Advance RR pointer

    output logic [N_REQ-1:0]  gnt_o,      // One-hot grant
    output logic              valid_o      // At least one request active
);

    localparam int IDX_W = (N_REQ > 1) ? $clog2(N_REQ) : 1;

    assign valid_o = |req_i;

    // --------------------------------------------------------
    // Fixed Priority Arbiter (lower index = higher priority)
    // --------------------------------------------------------
    logic [N_REQ-1:0] w_pri_gnt;

    always_comb begin
        w_pri_gnt = '0;
        for (int i = 0; i < N_REQ; i++) begin
            if (req_i[i]) begin
                w_pri_gnt[i] = 1'b1;
                break;
            end
        end
    end

    // --------------------------------------------------------
    // Round-Robin Arbiter (mask-based)
    // --------------------------------------------------------
    logic [IDX_W-1:0] r_rr_ptr;       // Points to highest-priority slot

    logic [N_REQ-1:0] w_rr_mask;      // 1 for positions >= r_rr_ptr
    logic [N_REQ-1:0] w_rr_masked_req;
    logic [N_REQ-1:0] w_rr_masked_gnt;
    logic [N_REQ-1:0] w_rr_unmask_gnt;
    logic [N_REQ-1:0] w_rr_gnt;

    // Mask generation
    always_comb begin
        w_rr_mask = '0;
        for (int i = 0; i < N_REQ; i++) begin
            if (i[IDX_W-1:0] >= r_rr_ptr)
                w_rr_mask[i] = 1'b1;
        end
    end

    assign w_rr_masked_req = req_i & w_rr_mask;

    // Priority-encode masked requests
    always_comb begin
        w_rr_masked_gnt = '0;
        for (int i = 0; i < N_REQ; i++) begin
            if (w_rr_masked_req[i]) begin
                w_rr_masked_gnt[i] = 1'b1;
                break;
            end
        end
    end

    // Priority-encode all requests (wrap-around)
    always_comb begin
        w_rr_unmask_gnt = '0;
        for (int i = 0; i < N_REQ; i++) begin
            if (req_i[i]) begin
                w_rr_unmask_gnt[i] = 1'b1;
                break;
            end
        end
    end

    // Use masked if available, else wrap
    assign w_rr_gnt = |w_rr_masked_req ? w_rr_masked_gnt : w_rr_unmask_gnt;

    // Grant index encoder
    logic [IDX_W-1:0] w_gnt_idx;
    always_comb begin
        w_gnt_idx = '0;
        for (int i = 0; i < N_REQ; i++) begin
            if (gnt_o[i]) w_gnt_idx = IDX_W'(i);
        end
    end

    // RR pointer update
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_rr_ptr <= '0;
        end else if (advance_i && valid_o) begin
            r_rr_ptr <= (w_gnt_idx == IDX_W'(N_REQ - 1)) ? '0 : w_gnt_idx + IDX_W'(1);
        end
    end

    // --------------------------------------------------------
    // Output Select
    // --------------------------------------------------------
    generate
        if (ROUND_ROBIN) begin : gen_rr
            assign gnt_o = w_rr_gnt;
        end else begin : gen_pri
            assign gnt_o = w_pri_gnt;
        end
    endgenerate

    // --------------------------------------------------------
    // Assertions
    // --------------------------------------------------------
    // synthesis translate_off
    // Grant must be one-hot or zero
    property p_gnt_onehot;
        @(posedge clk_i) disable iff (!rst_ni)
        $onehot0(gnt_o);
    endproperty
    a_gnt_onehot : assert property (p_gnt_onehot)
        else $error("[ARBITER] Grant is not one-hot or zero");
    // synthesis translate_on

endmodule
