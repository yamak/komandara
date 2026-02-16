/*
 * Copyright 2025 The Komandara Authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

//-----------------------------------------------------------------------------
// Komandara K10 — RISC-V DV core setting
//-----------------------------------------------------------------------------
// RV32IMAC_Zicsr_Zifencei  |  M + U modes  |  16 PMP regions  |  No MMU
//-----------------------------------------------------------------------------

// XLEN
parameter int XLEN = 32;

// No address translation
parameter satp_mode_t SATP_MODE = BARE;

// Supported privilege modes: M + U
privileged_mode_t supported_privileged_mode[] = {MACHINE_MODE, USER_MODE};

// No unsupported instructions
riscv_instr_name_t unsupported_instr[];

// ISA extensions: RV32I + M + A + C
riscv_instr_group_t supported_isa[$] = {RV32I, RV32M, RV32A, RV32C};

// Interrupt modes
mtvec_mode_t supported_interrupt_mode[$] = {DIRECT, VECTORED};

// Interrupt vector count
int max_interrupt_vector_num = 16;

// PMP: 16 regions
bit support_pmp = 1;

// No ePMP
bit support_epmp = 0;

// No debug mode
bit support_debug_mode = 0;

// No U-mode trap delegation
bit support_umode_trap = 0;

// No sfence.vma
bit support_sfence = 0;

// Unaligned load/store supported
bit support_unaligned_load_store = 1'b1;

// GPR settings
parameter int NUM_FLOAT_GPR = 32;
parameter int NUM_GPR = 32;
parameter int NUM_VEC_GPR = 32;

// No vector extension
parameter int VECTOR_EXTENSION_ENABLE = 0;
parameter int VLEN = 512;
parameter int ELEN = 32;
parameter int SELEN = 8;
parameter int VELEN = int'($ln(ELEN)/$ln(2)) - 3;
parameter int MAX_LMUL = 8;

// Single hart
parameter int NUM_HARTS = 1;

// Implemented CSRs
`ifdef DSIM
privileged_reg_t implemented_csr[] = {
`else
const privileged_reg_t implemented_csr[] = {
`endif
    // Machine Information
    MVENDORID,
    MARCHID,
    MIMPID,
    MHARTID,
    // Machine Trap Setup
    MSTATUS,
    MISA,
    MIE,
    MTVEC,
    MCOUNTEREN,
    // Machine Trap Handling
    MSCRATCH,
    MEPC,
    MCAUSE,
    MTVAL,
    MIP,
    // Machine Counters
    MCYCLE,
    MCYCLEH,
    MINSTRET,
    MINSTRETH
};

// No custom CSRs
bit [11:0] custom_csr[] = {
};

// Implemented interrupts
`ifdef DSIM
interrupt_cause_t implemented_interrupt[] = {
`else
const interrupt_cause_t implemented_interrupt[] = {
`endif
    M_SOFTWARE_INTR,
    M_TIMER_INTR,
    M_EXTERNAL_INTR
};

// Implemented exceptions
`ifdef DSIM
exception_cause_t implemented_exception[] = {
`else
const exception_cause_t implemented_exception[] = {
`endif
    INSTRUCTION_ACCESS_FAULT,
    ILLEGAL_INSTRUCTION,
    BREAKPOINT,
    LOAD_ADDRESS_MISALIGNED,
    LOAD_ACCESS_FAULT,
    STORE_AMO_ADDRESS_MISALIGNED,
    STORE_AMO_ACCESS_FAULT,
    ECALL_UMODE,
    ECALL_MMODE
};
