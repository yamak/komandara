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
// Komandara K10 — Package
// ============================================================================
// Central package for the K10 5-stage in-order RV32IMAC_Zicsr_Zifencei core.
// Contains all opcodes, type definitions, control structures, CSR addresses,
// and pipeline-register structs used throughout the core.
// ============================================================================

package komandara_k10_pkg;

  // =========================================================================
  // ISA Constants
  // =========================================================================
  parameter int XLEN     = 32;
  parameter int ILEN     = 32;
  parameter int NUM_REGS = 32;
  parameter int REG_AW   = 5;   // $clog2(NUM_REGS)

  // =========================================================================
  // Opcodes  (RV32I Base — Table 24.1 of riscv-spec-20191213)
  // =========================================================================
  typedef enum logic [6:0] {
    OP_LUI      = 7'b0110111,
    OP_AUIPC    = 7'b0010111,
    OP_JAL      = 7'b1101111,
    OP_JALR     = 7'b1100111,
    OP_BRANCH   = 7'b1100011,
    OP_LOAD     = 7'b0000011,
    OP_STORE    = 7'b0100011,
    OP_OP_IMM   = 7'b0010011,
    OP_OP       = 7'b0110011,
    OP_MISC_MEM = 7'b0001111,  // FENCE, FENCE.I
    OP_SYSTEM   = 7'b1110011,  // ECALL, EBREAK, CSR*, MRET, WFI
    OP_AMO      = 7'b0101111   // Atomic  (A extension)
  } opcode_e;

  // =========================================================================
  // ALU Operations
  // =========================================================================
  typedef enum logic [3:0] {
    ALU_ADD    = 4'd0,
    ALU_SUB    = 4'd1,
    ALU_SLL    = 4'd2,
    ALU_SLT    = 4'd3,
    ALU_SLTU   = 4'd4,
    ALU_XOR    = 4'd5,
    ALU_SRL    = 4'd6,
    ALU_SRA    = 4'd7,
    ALU_OR     = 4'd8,
    ALU_AND    = 4'd9,
    ALU_PASS_B = 4'd10   // Pass operand-B through (LUI, AUIPC)
  } alu_op_e;

  // =========================================================================
  // Multiply / Divide Operations  (M extension)
  // =========================================================================
  typedef enum logic [2:0] {
    MD_MUL    = 3'd0,
    MD_MULH   = 3'd1,
    MD_MULHSU = 3'd2,
    MD_MULHU  = 3'd3,
    MD_DIV    = 3'd4,
    MD_DIVU   = 3'd5,
    MD_REM    = 3'd6,
    MD_REMU   = 3'd7
  } md_op_e;

  // =========================================================================
  // Branch Conditions  (funct3 encoding)
  // =========================================================================
  typedef enum logic [2:0] {
    BR_BEQ  = 3'b000,
    BR_BNE  = 3'b001,
    BR_BLT  = 3'b100,
    BR_BGE  = 3'b101,
    BR_BLTU = 3'b110,
    BR_BGEU = 3'b111
  } branch_op_e;

  // =========================================================================
  // Load / Store Size  (funct3 encoding)
  // =========================================================================
  typedef enum logic [2:0] {
    LS_BYTE   = 3'b000,  // LB  / SB
    LS_HALF   = 3'b001,  // LH  / SH
    LS_WORD   = 3'b010,  // LW  / SW
    LS_BYTE_U = 3'b100,  // LBU
    LS_HALF_U = 3'b101   // LHU
  } ls_size_e;

  // =========================================================================
  // CSR Operations  (funct3[1:0])
  // =========================================================================
  typedef enum logic [1:0] {
    CSR_RW = 2'b01,  // CSRRW / CSRRWI
    CSR_RS = 2'b10,  // CSRRS / CSRRSI
    CSR_RC = 2'b11   // CSRRC / CSRRCI
  } csr_op_e;

  // =========================================================================
  // AMO funct5 field  (A extension)
  // =========================================================================
  typedef enum logic [4:0] {
    AMO_LR      = 5'b00010,
    AMO_SC      = 5'b00011,
    AMO_SWAP    = 5'b00001,
    AMO_ADD     = 5'b00000,
    AMO_XOR     = 5'b00100,
    AMO_AND     = 5'b01100,
    AMO_OR      = 5'b01000,
    AMO_MIN     = 5'b10000,
    AMO_MAX     = 5'b10100,
    AMO_MINU    = 5'b11000,
    AMO_MAXU    = 5'b11100
  } amo_op_e;

  // =========================================================================
  // Writeback Source
  // =========================================================================
  typedef enum logic [1:0] {
    WB_ALU  = 2'b00,  // ALU / MUL-DIV result
    WB_MEM  = 2'b01,  // Load data
    WB_PC4  = 2'b10,  // PC + 4  (JAL, JALR)
    WB_CSR  = 2'b11   // CSR read value
  } wb_sel_e;

  // =========================================================================
  // ALU Operand-A Source
  // =========================================================================
  typedef enum logic {
    ALU_A_RS1 = 1'b0,  // Register rs1
    ALU_A_PC  = 1'b1   // Current PC  (AUIPC, branch target)
  } alu_a_sel_e;

  // =========================================================================
  // ALU Operand-B Source
  // =========================================================================
  typedef enum logic {
    ALU_B_RS2 = 1'b0,  // Register rs2
    ALU_B_IMM = 1'b1   // Immediate
  } alu_b_sel_e;

  // =========================================================================
  // Forwarding Mux Select
  // =========================================================================
  typedef enum logic [1:0] {
    FWD_NONE = 2'b00,   // No forwarding — use register file value
    FWD_MEM  = 2'b01,   // Forward from MEM stage (EX/MEM.alu_result)
    FWD_WB   = 2'b10    // Forward from WB  stage (writeback data)
  } fwd_sel_e;

  // =========================================================================
  // Privilege Levels  (M + U only for K10)
  // =========================================================================
  typedef enum logic [1:0] {
    PRIV_U = 2'b00,
    PRIV_M = 2'b11
  } priv_lvl_e;

  // =========================================================================
  // Decoded Control Signals  (generated in Decode, carried through pipeline)
  // =========================================================================
  typedef struct packed {
    // ALU
    alu_op_e    alu_op;
    alu_a_sel_e alu_a_sel;
    alu_b_sel_e alu_b_sel;

    // Multiply / Divide
    logic       md_en;
    md_op_e     md_op;

    // Branch / Jump
    logic       is_branch;
    logic       is_jal;
    logic       is_jalr;
    branch_op_e branch_op;

    // Memory
    logic       mem_read;
    logic       mem_write;
    ls_size_e   mem_size;

    // Writeback
    logic       reg_write;
    wb_sel_e    wb_sel;

    // CSR
    logic       csr_en;
    csr_op_e    csr_op;
    logic       csr_imm;       // 1 = zimm operand, 0 = rs1

    // System
    logic       is_ecall;
    logic       is_ebreak;
    logic       is_mret;
    logic       is_wfi;
    logic       is_fence;
    logic       is_fence_i;

    // Atomic
    logic       is_atomic;
    amo_op_e    amo_op;

    // Instruction width
    logic       is_compressed; // 16-bit (C extension)

    // Exception: illegal instruction detected in decode
    logic       illegal;
  } ctrl_t;

  // =========================================================================
  // Pipeline Register Structs
  // =========================================================================

  // ----- IF / ID -----
  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] instr;
    logic        is_compressed;
    logic        valid;
  } if_id_t;

  // ----- ID / EX -----
  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] instr;       // Original instruction binary (for tracer)
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] imm;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [4:0]  rd_addr;
    logic [11:0] csr_addr;
    ctrl_t       ctrl;
    logic        valid;
  } id_ex_t;

  // ----- EX / MEM -----
  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] instr;         // Original instruction binary (for tracer)
    logic [31:0] alu_result;
    logic [31:0] rs2_data;      // Store data (forwarded)
    logic [4:0]  rd_addr;
    logic [11:0] csr_addr;
    logic [31:0] csr_rdata;     // CSR read value
    ctrl_t       ctrl;
    logic        valid;
  } ex_mem_t;

  // ----- MEM / WB -----
  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] instr;       // Original instruction binary (for tracer)
    logic [31:0] alu_result;
    logic [31:0] mem_rdata;
    logic [31:0] csr_rdata;
    logic [4:0]  rd_addr;
    ctrl_t       ctrl;
    logic        valid;
  } mem_wb_t;

  // =========================================================================
  // Trap Causes  (mcause values — Privileged Spec Table 3.6)
  // =========================================================================
  // Exception codes (bit 31 = 0)
  parameter logic [31:0] EXC_INSTR_MISALIGN  = 32'd0;
  parameter logic [31:0] EXC_INSTR_FAULT     = 32'd1;
  parameter logic [31:0] EXC_ILLEGAL_INSTR   = 32'd2;
  parameter logic [31:0] EXC_BREAKPOINT      = 32'd3;
  parameter logic [31:0] EXC_LOAD_MISALIGN   = 32'd4;
  parameter logic [31:0] EXC_LOAD_FAULT      = 32'd5;
  parameter logic [31:0] EXC_STORE_MISALIGN  = 32'd6;
  parameter logic [31:0] EXC_STORE_FAULT     = 32'd7;
  parameter logic [31:0] EXC_ECALL_U         = 32'd8;
  parameter logic [31:0] EXC_ECALL_M         = 32'd11;

  // Interrupt codes (bit 31 = 1)
  parameter logic [31:0] INT_U_SW    = 32'h8000_0000;
  parameter logic [31:0] INT_M_SW    = 32'h8000_0003;
  parameter logic [31:0] INT_U_TIMER = 32'h8000_0004;
  parameter logic [31:0] INT_M_TIMER = 32'h8000_0007;
  parameter logic [31:0] INT_U_EXT   = 32'h8000_0008;
  parameter logic [31:0] INT_M_EXT   = 32'h8000_000B;

  // =========================================================================
  // CSR Addresses  (M + U mode subset)
  // =========================================================================

  // Machine Information Registers (read-only)
  parameter logic [11:0] CSR_MVENDORID  = 12'hF11;
  parameter logic [11:0] CSR_MARCHID    = 12'hF12;
  parameter logic [11:0] CSR_MIMPID     = 12'hF13;
  parameter logic [11:0] CSR_MHARTID    = 12'hF14;

  // Machine Trap Setup
  parameter logic [11:0] CSR_MSTATUS    = 12'h300;
  parameter logic [11:0] CSR_MISA       = 12'h301;
  parameter logic [11:0] CSR_MIE        = 12'h304;
  parameter logic [11:0] CSR_MTVEC      = 12'h305;
  parameter logic [11:0] CSR_MCOUNTEREN = 12'h306;

  // Machine Trap Handling
  parameter logic [11:0] CSR_MSCRATCH   = 12'h340;
  parameter logic [11:0] CSR_MEPC       = 12'h341;
  parameter logic [11:0] CSR_MCAUSE     = 12'h342;
  parameter logic [11:0] CSR_MTVAL      = 12'h343;
  parameter logic [11:0] CSR_MIP        = 12'h344;

  // Machine Counter/Timers
  parameter logic [11:0] CSR_MCYCLE     = 12'hB00;
  parameter logic [11:0] CSR_MINSTRET   = 12'hB02;
  parameter logic [11:0] CSR_MCYCLEH    = 12'hB80;
  parameter logic [11:0] CSR_MINSTRETH  = 12'hB82;

  // User Counter/Timers (read-only shadows)
  parameter logic [11:0] CSR_CYCLE      = 12'hC00;
  parameter logic [11:0] CSR_TIME       = 12'hC01;
  parameter logic [11:0] CSR_INSTRET    = 12'hC02;
  parameter logic [11:0] CSR_CYCLEH     = 12'hC80;
  parameter logic [11:0] CSR_TIMEH      = 12'hC81;
  parameter logic [11:0] CSR_INSTRETH   = 12'hC82;

  // PMP Configuration
  parameter logic [11:0] CSR_PMPCFG0    = 12'h3A0;
  parameter logic [11:0] CSR_PMPCFG1    = 12'h3A1;
  parameter logic [11:0] CSR_PMPCFG2    = 12'h3A2;
  parameter logic [11:0] CSR_PMPCFG3    = 12'h3A3;

  // PMP Address (0..15)
  parameter logic [11:0] CSR_PMPADDR0   = 12'h3B0;
  parameter logic [11:0] CSR_PMPADDR1   = 12'h3B1;
  parameter logic [11:0] CSR_PMPADDR2   = 12'h3B2;
  parameter logic [11:0] CSR_PMPADDR3   = 12'h3B3;
  parameter logic [11:0] CSR_PMPADDR4   = 12'h3B4;
  parameter logic [11:0] CSR_PMPADDR5   = 12'h3B5;
  parameter logic [11:0] CSR_PMPADDR6   = 12'h3B6;
  parameter logic [11:0] CSR_PMPADDR7   = 12'h3B7;
  parameter logic [11:0] CSR_PMPADDR8   = 12'h3B8;
  parameter logic [11:0] CSR_PMPADDR9   = 12'h3B9;
  parameter logic [11:0] CSR_PMPADDR10  = 12'h3BA;
  parameter logic [11:0] CSR_PMPADDR11  = 12'h3BB;
  parameter logic [11:0] CSR_PMPADDR12  = 12'h3BC;
  parameter logic [11:0] CSR_PMPADDR13  = 12'h3BD;
  parameter logic [11:0] CSR_PMPADDR14  = 12'h3BE;
  parameter logic [11:0] CSR_PMPADDR15  = 12'h3BF;

  // =========================================================================
  // PMP Types
  // =========================================================================
  typedef enum logic [1:0] {
    PMP_OFF   = 2'b00,
    PMP_TOR   = 2'b01,
    PMP_NA4   = 2'b10,
    PMP_NAPOT = 2'b11
  } pmp_mode_e;

  typedef struct packed {
    logic       lock;
    logic [1:0] reserved;
    pmp_mode_e  mode;
    logic       x;   // Execute
    logic       w;   // Write
    logic       r;   // Read
  } pmp_cfg_t;

  // =========================================================================
  // NOP control word  (all fields zero / default — no side effects)
  // Used to flush pipeline stages.
  // =========================================================================
  parameter ctrl_t CTRL_NOP = '{
      alu_op:        ALU_ADD,
      alu_a_sel:     ALU_A_RS1,
      alu_b_sel:     ALU_B_RS2,
      md_en:         1'b0,
      md_op:         MD_MUL,
      is_branch:     1'b0,
      is_jal:        1'b0,
      is_jalr:       1'b0,
      branch_op:     BR_BEQ,
      mem_read:      1'b0,
      mem_write:     1'b0,
      mem_size:      LS_BYTE,
      reg_write:     1'b0,
      wb_sel:        WB_ALU,
      csr_en:        1'b0,
      csr_op:        CSR_RW,
      csr_imm:       1'b0,
      is_ecall:      1'b0,
      is_ebreak:     1'b0,
      is_mret:       1'b0,
      is_wfi:        1'b0,
      is_fence:      1'b0,
      is_fence_i:    1'b0,
      is_atomic:     1'b0,
      amo_op:        AMO_ADD,
      is_compressed: 1'b0,
      illegal:       1'b0
  };

  // =========================================================================
  // Pipeline-register NOP constants  (used for flush / reset)
  // =========================================================================
  parameter if_id_t IF_ID_NOP = '{
      pc:            32'd0,
      instr:         32'd0,
      is_compressed: 1'b0,
      valid:         1'b0
  };

  parameter id_ex_t ID_EX_NOP = '{
      pc:       32'd0,
      instr:    32'd0,
      rs1_data: 32'd0,
      rs2_data: 32'd0,
      imm:      32'd0,
      rs1_addr: 5'd0,
      rs2_addr: 5'd0,
      rd_addr:  5'd0,
      csr_addr: 12'd0,
      ctrl:     CTRL_NOP,
      valid:    1'b0
  };

  parameter ex_mem_t EX_MEM_NOP = '{
      pc:         32'd0,
      instr:      32'd0,
      alu_result: 32'd0,
      rs2_data:   32'd0,
      rd_addr:    5'd0,
      csr_addr:   12'd0,
      csr_rdata:  32'd0,
      ctrl:       CTRL_NOP,
      valid:      1'b0
  };

  parameter mem_wb_t MEM_WB_NOP = '{
      pc:         32'd0,
      instr:      32'd0,
      alu_result: 32'd0,
      mem_rdata:  32'd0,
      csr_rdata:  32'd0,
      rd_addr:    5'd0,
      ctrl:       CTRL_NOP,
      valid:      1'b0
  };

endpackage : komandara_k10_pkg
