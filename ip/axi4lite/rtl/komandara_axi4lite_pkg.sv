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
// Komandara - AXI4-Lite Package
// ============================================================================
// Defines common types and constants for AXI4-Lite interfaces.
// Shared infrastructure — not tied to any specific core version.
// ============================================================================

package komandara_axi4lite_pkg;

  // --------------------------------------------------------------------------
  // AXI4-Lite Response Encoding (BRESP / RRESP)
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,  // Normal access success
    AXI_RESP_EXOKAY = 2'b01,  // Exclusive access okay (not used in AXI4-Lite)
    AXI_RESP_SLVERR = 2'b10,  // Slave error
    AXI_RESP_DECERR = 2'b11   // Decode error
  } axi_resp_e;

  // --------------------------------------------------------------------------
  // AXI4-Lite Protection Encoding (AxPROT)
  // --------------------------------------------------------------------------
  //  [0] : 0 = Unprivileged, 1 = Privileged
  //  [1] : 0 = Secure,       1 = Non-secure
  //  [2] : 0 = Data,         1 = Instruction
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    AXI_PROT_UNPRIV_SEC_DATA    = 3'b000,
    AXI_PROT_PRIV_SEC_DATA      = 3'b001,
    AXI_PROT_UNPRIV_NSEC_DATA   = 3'b010,
    AXI_PROT_PRIV_NSEC_DATA     = 3'b011,
    AXI_PROT_UNPRIV_SEC_INSN    = 3'b100,
    AXI_PROT_PRIV_SEC_INSN      = 3'b101,
    AXI_PROT_UNPRIV_NSEC_INSN   = 3'b110,
    AXI_PROT_PRIV_NSEC_INSN     = 3'b111
  } axi_prot_e;

endpackage
