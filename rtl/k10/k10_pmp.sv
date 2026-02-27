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
// K10 — Physical Memory Protection  (PMP)
// ============================================================================
// Implements the PMP check logic per RISC-V Privileged Spec v1.12, §3.7.
//
// Supports all three address-matching modes:
//   - TOR   (Top of Range)
//   - NA4   (Naturally Aligned 4-byte)
//   - NAPOT (Naturally Aligned Power-of-Two)
//
// The PMP configuration / address registers are held in k10_csr and passed
// in as arrays.  This module is purely combinational.
//
// Rules:
//   - M-mode: allowed unless a matching region is locked (L=1) and denies.
//   - U-mode: denied unless a matching region explicitly grants access.
//   - If no region matches in U-mode, access is denied.
//   - If no region matches in M-mode, access is allowed (default).
// ============================================================================

module k10_pmp
  import komandara_k10_pkg::*;
#(
    parameter int unsigned PMP_REGIONS = 16
)(
    // PMP configuration (from CSR unit)
    input  logic [PMP_REGIONS-1:0][7:0]  i_pmp_cfg,
    input  logic [PMP_REGIONS-1:0][31:0] i_pmp_addr,

    // Access request
    input  logic [31:0]  i_addr,
    input  priv_lvl_e    i_priv,
    input  logic         i_read,
    input  logic         i_write,
    input  logic         i_exec,

    // Result
    output logic         o_allowed
);

    // -----------------------------------------------------------------------
    // Per-region match & permission
    // -----------------------------------------------------------------------
    logic [PMP_REGIONS-1:0] w_match;
    logic [PMP_REGIONS-1:0] w_perm_ok;

    genvar g;
    generate
        for (g = 0; g < PMP_REGIONS; g++) begin : gen_pmp_region

            // Configuration fields
            logic       w_lock;
            logic [1:0] w_mode;
            logic       w_r, w_w, w_x;

            assign w_lock = i_pmp_cfg[g][7];
            assign w_mode = i_pmp_cfg[g][4:3];
            assign w_x    = i_pmp_cfg[g][2];
            assign w_w    = i_pmp_cfg[g][1];
            assign w_r    = i_pmp_cfg[g][0];

            // Addresses shifted to byte granularity
            logic [33:0] w_pmpaddr_shifted;
            assign w_pmpaddr_shifted = {i_pmp_addr[g], 2'b00};

            // Previous region address (for TOR)
            logic [33:0] w_prev_addr;
            if (g == 0) begin : gen_prev_zero
                assign w_prev_addr = 34'd0;
            end else begin : gen_prev_nonzero
                assign w_prev_addr = {i_pmp_addr[g-1], 2'b00};
            end

            // NAPOT mask and base
            logic [33:0] w_napot_mask;
            logic [33:0] w_napot_base;
            logic [33:0] w_size_bits;

            // size_bits = (pmpaddr ^ (pmpaddr + 1)) << 2 | 2'b11
            // This creates a mask of all the "don't care" bits
            assign w_size_bits  = {(i_pmp_addr[g] ^ (i_pmp_addr[g] + 32'd1)), 2'b11};
            assign w_napot_mask = ~w_size_bits;
            assign w_napot_base = w_pmpaddr_shifted & w_napot_mask;

            // Extended address for comparison
            logic [33:0] w_addr_ext;
            assign w_addr_ext = {2'b00, i_addr};

            // Region match logic
            always_comb begin
                w_match[g] = 1'b0;

                case (w_mode)
                    2'b00: begin // PMP_OFF
                        w_match[g] = 1'b0;
                    end
                    2'b01: begin // PMP_TOR
                        w_match[g] = (w_addr_ext >= w_prev_addr) &&
                                     (w_addr_ext <  w_pmpaddr_shifted);
                    end
                    2'b10: begin // PMP_NA4  (4-byte naturally aligned)
                        w_match[g] = (w_addr_ext[33:2] == w_pmpaddr_shifted[33:2]);
                    end
                    2'b11: begin // PMP_NAPOT
                        w_match[g] = ((w_addr_ext & w_napot_mask) == w_napot_base);
                    end
                    default: w_match[g] = 1'b0;
                endcase
            end

            // Permission check
            assign w_perm_ok[g] = (!i_read  || w_r) &&
                                  (!i_write || w_w) &&
                                  (!i_exec  || w_x);

        end : gen_pmp_region
    endgenerate

    // -----------------------------------------------------------------------
    // Priority encoder: first matching region wins
    // -----------------------------------------------------------------------
    always_comb begin
        // Defaults
        if (i_priv == PRIV_M) begin
            o_allowed = 1'b1;  // M-mode: default allow
        end else begin
            o_allowed = 1'b0;  // U-mode: default deny
        end

        for (int i = PMP_REGIONS - 1; i >= 0; i--) begin
            if (w_match[i]) begin
                if (i_priv == PRIV_M) begin
                    // M-mode: only locked regions restrict access
                    o_allowed = i_pmp_cfg[i][7] ? w_perm_ok[i] : 1'b1;
                end else begin
                    // U-mode: explicit permission required
                    o_allowed = w_perm_ok[i];
                end
            end
        end
    end

endmodule : k10_pmp
