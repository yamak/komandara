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
// Komandara - Skid Buffer (AXI Register Slice)
// ============================================================================
// A single-entry pipeline register that decouples upstream and downstream
// valid/ready handshakes. Achieves full throughput (one transfer per cycle)
// when the downstream is continuously ready.
//
// Shared infrastructure — not tied to any specific core version.
//
// Key Properties:
//   - s_ready_o does NOT depend on m_ready_i (breaks timing path)
//   - Zero latency pass-through when buffer is empty
//   - Captures data in skid register when downstream stalls
//   - Full throughput: no bubbles when downstream is always ready
// ============================================================================

module komandara_skid_buffer #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                  clk_i,
    input  logic                  rst_ni,

    // Upstream (slave) interface
    input  logic [DATA_WIDTH-1:0] s_data_i,
    input  logic                  s_valid_i,
    output logic                  s_ready_o,

    // Downstream (master) interface
    output logic [DATA_WIDTH-1:0] m_data_o,
    output logic                  m_valid_o,
    input  logic                  m_ready_i
);

    // --------------------------------------------------------
    // Skid register
    // --------------------------------------------------------
    logic [DATA_WIDTH-1:0] r_skid_data;
    logic                  r_skid_valid;

    // --------------------------------------------------------
    // Output assignments
    // --------------------------------------------------------
    // Upstream ready: accept when skid register is empty.
    // This signal depends ONLY on r_skid_valid (registered),
    // breaking the combinational path from m_ready_i → s_ready_o.
    assign s_ready_o = ~r_skid_valid;

    // Output mux: skid register has priority over pass-through.
    assign m_data_o  = r_skid_valid ? r_skid_data : s_data_i;
    assign m_valid_o = r_skid_valid | s_valid_i;

    // --------------------------------------------------------
    // Skid register control
    // --------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            r_skid_valid <= 1'b0;
            r_skid_data  <= '0;
        end else begin
            if (r_skid_valid) begin
                // Skid buffer occupied → drain when downstream accepts
                if (m_ready_i) begin
                    r_skid_valid <= 1'b0;
                end
            end else begin
                // Skid buffer empty → capture if downstream not ready
                if (s_valid_i && !m_ready_i) begin
                    r_skid_data  <= s_data_i;
                    r_skid_valid <= 1'b1;
                end
            end
        end
    end

    // --------------------------------------------------------
    // Assertions
    // --------------------------------------------------------
    // synthesis translate_off

    // If m_valid_o is asserted and m_ready_i is not, m_data_o must be stable
    property p_data_stable;
        @(posedge clk_i) disable iff (!rst_ni)
        (m_valid_o && !m_ready_i) |=> (m_valid_o && ($stable(m_data_o) || m_ready_i));
    endproperty
    a_data_stable : assert property (p_data_stable)
        else $error("[SKID_BUF] Output data changed while valid & !ready");

    // synthesis translate_on

endmodule
