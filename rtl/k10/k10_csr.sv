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
// K10 — Control and Status Register Unit  (CSR)
// ============================================================================
// Implements the Machine-mode (M) and User-mode (U) CSR set for
// RV32IMAC_Zicsr as specified in the RISC-V Privileged Architecture v1.12.
//
// Supported CSRs:
//   Machine Information : mvendorid, marchid, mimpid, mhartid  (read-only)
//   Machine Trap Setup  : mstatus, misa, mie, mtvec, mcounteren
//   Machine Trap Handling: mscratch, mepc, mcause, mtval, mip
//   Machine Counters    : mcycle/h, minstret/h
//   PMP                 : pmpcfg0–3, pmpaddr0–15  (delegated to k10_pmp)
//   User Counters       : cycle/h, time/h, instret/h  (read-only shadows)
//
// Trap handling:
//   Exceptions and interrupts are resolved at the EX/MEM boundary.
//   On trap, mepc/mcause/mtval are set and a redirect to mtvec is issued.
//   MRET restores privilege and PC from mstatus.MPP and mepc.
// ============================================================================

module k10_csr
  import komandara_k10_pkg::*;
#(
    parameter logic [31:0] MVENDORID = 32'd0,
    parameter logic [31:0] MARCHID   = 32'd0,
    parameter logic [31:0] MIMPID    = 32'd0,
    parameter logic [31:0] MHARTID   = 32'd0,
    parameter int unsigned PMP_REGIONS = 16
)(
    input  logic        i_clk,
    input  logic        i_rst_n,

    // ---- CSR read/write port (from EX stage) ----
    input  logic        i_csr_en,
    input  csr_op_e     i_csr_op,
    input  logic [11:0] i_csr_addr,
    input  logic [31:0] i_csr_wdata,    // rs1 or zimm (zero-extended)
    output logic [31:0] o_csr_rdata,
    output logic        o_csr_illegal,  // Access violation or unknown CSR

    // ---- Current privilege level ----
    output priv_lvl_e   o_priv_lvl,

    // ---- Exception inputs (from pipeline) ----
    input  logic        i_exc_valid,         // An exception occurred
    input  logic [31:0] i_exc_cause,
    input  logic [31:0] i_exc_pc,            // PC of faulting instruction
    input  logic [31:0] i_exc_tval,          // Trap value

    // ---- System instructions ----
    input  logic        i_is_mret,
    input  logic        i_is_wfi,
    input  logic        i_is_dret,           // DRET instruction

    // ---- External interrupts ----
    input  logic        i_ext_irq,           // Machine external interrupt
    input  logic        i_timer_irq,         // Machine timer interrupt
    input  logic        i_sw_irq,            // Machine software interrupt
    input  logic [14:0] i_irq_fast,          // Fast interrupts (Ibex-style)

    // ---- Debug ----
    input  logic        i_debug_req,         // External debug halt request
    output logic        o_debug_mode,        // Currently in debug mode

    // ---- Trap output (redirect PC) ----
    output logic        o_trap_taken,
    output logic [31:0] o_trap_target,
    output logic        o_mret_taken,
    output logic [31:0] o_mret_target,
    output logic        o_dret_taken,
    output logic [31:0] o_dret_target,

    // ---- Performance counters ----
    input  logic        i_instr_retired,     // WB stage committed

    // ---- PMP interface (directly exposed for k10_pmp) ----
    output logic [PMP_REGIONS-1:0][7:0]  o_pmp_cfg,
    output logic [PMP_REGIONS-1:0][31:0] o_pmp_addr,

    // ---- External time source ----
    input  logic [63:0] i_mtime           // Memory-mapped timer value
);

    // -----------------------------------------------------------------------
    // Internal CSR registers
    // -----------------------------------------------------------------------

    // Privilege level
    priv_lvl_e r_priv;
    assign o_priv_lvl = r_priv;

    // --- mstatus ---
    // Relevant fields for M+U: MIE(3), MPIE(7), MPP(12:11), MPRV(17)
    logic       r_mstatus_mie;
    logic       r_mstatus_mpie;
    priv_lvl_e  r_mstatus_mpp;
    logic       r_mstatus_mprv;

    logic [31:0] w_mstatus;
    assign w_mstatus = {
        14'd0,              // [31:18]
        r_mstatus_mprv,     // [17]    MPRV
        4'd0,               // [16:13]
        2'(r_mstatus_mpp),  // [12:11] MPP
        3'd0,               // [10:8]
        r_mstatus_mpie,     // [7]     MPIE
        3'd0,               // [6:4]
        r_mstatus_mie,      // [3]     MIE
        3'd0                // [2:0]
    };

    // --- misa ---  (read-only, fixed)
    // MXL=1 (32-bit), Extensions: I, M, A, C, U
    // bit  0 = A, bit  2 = C, bit  8 = I, bit 12 = M, bit 20 = U
    localparam logic [31:0] MISA_VALUE = (32'b01 << 30) | // MXL=1
                                         (1 << 0)  |  // A
                                         (1 << 2)  |  // C
                                         (1 << 8)  |  // I
                                         (1 << 12) |  // M
                                         (1 << 20);   // U

    // --- mie (Machine Interrupt Enable) ---
    logic r_mie_meie;   // [11] Machine External
    logic r_mie_mtie;   // [7]  Machine Timer
    logic r_mie_msie;   // [3]  Machine Software
    logic [14:0] r_mie_fast;  // [30:16] Fast interrupts

    logic [31:0] w_mie;
    assign w_mie = {1'b0, r_mie_fast, 4'd0, r_mie_meie, 3'd0, r_mie_mtie, 3'd0, r_mie_msie, 3'd0};

    // --- mip (Machine Interrupt Pending) ---
    // MEIP, MTIP, MSIP are read-only (driven by external sources)
    // Fast IRQ pending bits [30:16] driven by i_irq_fast
    logic [31:0] w_mip;
    assign w_mip = {1'b0, i_irq_fast, 4'd0, i_ext_irq, 3'd0, i_timer_irq, 3'd0, i_sw_irq, 3'd0};

    // --- Debug Mode Registers ---
    logic        r_debug_mode;
    logic [31:0] r_dcsr;
    logic [31:0] r_dpc;
    logic [31:0] r_dscratch0;
    logic [31:0] r_dscratch1;

    assign o_debug_mode = r_debug_mode;

    // dcsr fields:
    //   [31:28] xdebugver = 4 (external debug)
    //   [15]    ebreakm   = enter debug on ebreak in M-mode
    //   [8:6]   cause     = debug entry cause
    //   [2]     step      = single-step
    //   [1:0]   prv       = privilege before debug entry
    logic [31:0] w_dcsr;
    assign w_dcsr = r_dcsr | {4'd4, 16'd0, 12'd0};  // xdebugver always 4

    // --- mtvec ---
    logic [31:0] r_mtvec;  // BASE[31:2], MODE[1:0]  (0=Direct, 1=Vectored)

    // --- mcounteren ---
    logic r_mcounteren_cy;
    logic r_mcounteren_tm;
    logic r_mcounteren_ir;

    // --- Machine Trap Handling ---
    logic [31:0] r_mscratch;
    logic [31:0] r_mepc;
    logic [31:0] r_mcause;
    logic [31:0] r_mtval;

    // --- Counters ---
    logic [63:0] r_mcycle;
    logic [63:0] r_minstret;

    // --- PMP ---
    logic [PMP_REGIONS-1:0][7:0]  r_pmpcfg;
    logic [PMP_REGIONS-1:0][31:0] r_pmpaddr;

    assign o_pmp_cfg  = r_pmpcfg;
    assign o_pmp_addr = r_pmpaddr;

    // -----------------------------------------------------------------------
    // Interrupt pending & enabled
    // -----------------------------------------------------------------------
    logic w_irq_pending;
    logic [31:0] w_irq_cause;

    always_comb begin
        w_irq_pending = 1'b0;
        w_irq_cause   = 32'd0;

        // No interrupts in debug mode
        if (!r_debug_mode && (r_mstatus_mie || (r_priv < PRIV_M))) begin
            // Priority: MEI > MSI > MTI > Fast[0..14]  (per spec 3.1.9)
            if (w_mip[11] && w_mie[11]) begin
                w_irq_pending = 1'b1;
                w_irq_cause   = INT_M_EXT;
            end else if (w_mip[3] && w_mie[3]) begin
                w_irq_pending = 1'b1;
                w_irq_cause   = INT_M_SW;
            end else if (w_mip[7] && w_mie[7]) begin
                w_irq_pending = 1'b1;
                w_irq_cause   = INT_M_TIMER;
            end else begin
                // Fast interrupts (causes 16..30)
                for (int i = 0; i < 15; i++) begin
                    if (w_mip[16+i] && w_mie[16+i]) begin
                        w_irq_pending = 1'b1;
                        w_irq_cause   = {1'b1, 31'(16 + i)};
                        break;
                    end
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // Debug mode entry detection
    // -----------------------------------------------------------------------
    logic w_debug_entry;
    logic [2:0] w_debug_cause;

    always_comb begin
        w_debug_entry = 1'b0;
        w_debug_cause = 3'd0;

        if (!r_debug_mode) begin
            if (i_debug_req) begin
                w_debug_entry = 1'b1;
                w_debug_cause = 3'd3;  // haltreq
            end else if (i_exc_valid && i_exc_cause == EXC_BREAKPOINT &&
                         r_dcsr[15]) begin  // ebreakm
                w_debug_entry = 1'b1;
                w_debug_cause = 3'd1;  // ebreak
            end else if (r_dcsr[2]) begin  // step
                w_debug_entry = 1'b1;
                w_debug_cause = 3'd4;  // step
            end
        end
    end

    // -----------------------------------------------------------------------
    // Trap vector calculation
    // -----------------------------------------------------------------------
    logic [31:0] w_trap_base;
    logic        w_trap_vectored;

    assign w_trap_base     = {r_mtvec[31:2], 2'b00};
    assign w_trap_vectored = (r_mtvec[1:0] == 2'b01);

    logic [31:0] w_trap_vec_addr;
    always_comb begin
        if (w_trap_vectored && w_irq_cause[31]) begin
            // Vectored mode for interrupts: BASE + 4 × cause
            w_trap_vec_addr = w_trap_base + {w_irq_cause[29:0], 2'b00};
        end else begin
            w_trap_vec_addr = w_trap_base;
        end
    end

    // -----------------------------------------------------------------------
    // Trap / MRET / DRET outputs
    // -----------------------------------------------------------------------
    // Debug entry takes priority over everything
    assign o_trap_taken  = w_debug_entry ? 1'b0 :
                           (i_exc_valid || w_irq_pending) && !r_debug_mode;
    assign o_trap_target = w_trap_vectored && w_irq_pending && !i_exc_valid
                           ? w_trap_vec_addr
                           : w_trap_base;
    assign o_mret_taken  = i_is_mret && !r_debug_mode;
    assign o_mret_target = r_mepc;
    assign o_dret_taken  = i_is_dret && r_debug_mode;
    assign o_dret_target = r_dpc;

    // -----------------------------------------------------------------------
    // CSR read logic
    // -----------------------------------------------------------------------
    logic [31:0] w_csr_rdata;
    logic        w_csr_exists;

    always_comb begin
        w_csr_rdata  = 32'd0;
        w_csr_exists = 1'b1;

        unique case (i_csr_addr)
            // Machine Information (read-only)
            CSR_MVENDORID:  w_csr_rdata = MVENDORID;
            CSR_MARCHID:    w_csr_rdata = MARCHID;
            CSR_MIMPID:     w_csr_rdata = MIMPID;
            CSR_MHARTID:    w_csr_rdata = MHARTID;

            // Machine Trap Setup
            CSR_MSTATUS:    w_csr_rdata = w_mstatus;
            CSR_MISA:       w_csr_rdata = MISA_VALUE;
            CSR_MIE:        w_csr_rdata = w_mie;
            CSR_MTVEC:      w_csr_rdata = r_mtvec;
            CSR_MCOUNTEREN: w_csr_rdata = {29'd0, r_mcounteren_ir,
                                           r_mcounteren_tm, r_mcounteren_cy};

            // Machine Trap Handling
            CSR_MSCRATCH:   w_csr_rdata = r_mscratch;
            CSR_MEPC:       w_csr_rdata = r_mepc;
            CSR_MCAUSE:     w_csr_rdata = r_mcause;
            CSR_MTVAL:      w_csr_rdata = r_mtval;
            CSR_MIP:        w_csr_rdata = w_mip;

            // Machine Counters
            CSR_MCYCLE:     w_csr_rdata = r_mcycle[31:0];
            CSR_MCYCLEH:    w_csr_rdata = r_mcycle[63:32];
            CSR_MINSTRET:   w_csr_rdata = r_minstret[31:0];
            CSR_MINSTRETH:  w_csr_rdata = r_minstret[63:32];

            // User Counters (read-only shadows, controlled by mcounteren)
            CSR_CYCLE:      w_csr_rdata = r_mcycle[31:0];
            CSR_CYCLEH:     w_csr_rdata = r_mcycle[63:32];
            CSR_TIME:       w_csr_rdata = i_mtime[31:0];
            CSR_TIMEH:      w_csr_rdata = i_mtime[63:32];
            CSR_INSTRET:    w_csr_rdata = r_minstret[31:0];
            CSR_INSTRETH:   w_csr_rdata = r_minstret[63:32];

            // PMP Config
            CSR_PMPCFG0:    w_csr_rdata = {r_pmpcfg[3],  r_pmpcfg[2],
                                           r_pmpcfg[1],  r_pmpcfg[0]};
            CSR_PMPCFG1:    w_csr_rdata = {r_pmpcfg[7],  r_pmpcfg[6],
                                           r_pmpcfg[5],  r_pmpcfg[4]};
            CSR_PMPCFG2:    w_csr_rdata = {r_pmpcfg[11], r_pmpcfg[10],
                                           r_pmpcfg[9],  r_pmpcfg[8]};
            CSR_PMPCFG3:    w_csr_rdata = {r_pmpcfg[15], r_pmpcfg[14],
                                           r_pmpcfg[13], r_pmpcfg[12]};

            // PMP Address
            CSR_PMPADDR0:   w_csr_rdata = r_pmpaddr[0];
            CSR_PMPADDR1:   w_csr_rdata = r_pmpaddr[1];
            CSR_PMPADDR2:   w_csr_rdata = r_pmpaddr[2];
            CSR_PMPADDR3:   w_csr_rdata = r_pmpaddr[3];
            CSR_PMPADDR4:   w_csr_rdata = r_pmpaddr[4];
            CSR_PMPADDR5:   w_csr_rdata = r_pmpaddr[5];
            CSR_PMPADDR6:   w_csr_rdata = r_pmpaddr[6];
            CSR_PMPADDR7:   w_csr_rdata = r_pmpaddr[7];
            CSR_PMPADDR8:   w_csr_rdata = r_pmpaddr[8];
            CSR_PMPADDR9:   w_csr_rdata = r_pmpaddr[9];
            CSR_PMPADDR10:  w_csr_rdata = r_pmpaddr[10];
            CSR_PMPADDR11:  w_csr_rdata = r_pmpaddr[11];
            CSR_PMPADDR12:  w_csr_rdata = r_pmpaddr[12];
            CSR_PMPADDR13:  w_csr_rdata = r_pmpaddr[13];
            CSR_PMPADDR14:  w_csr_rdata = r_pmpaddr[14];
            CSR_PMPADDR15:  w_csr_rdata = r_pmpaddr[15];

            // Debug Mode CSRs (only accessible in debug mode)
            CSR_DCSR:       w_csr_rdata = w_dcsr;
            CSR_DPC:        w_csr_rdata = r_dpc;
            CSR_DSCRATCH0:  w_csr_rdata = r_dscratch0;
            CSR_DSCRATCH1:  w_csr_rdata = r_dscratch1;

            default: begin
                w_csr_exists = 1'b0;
                w_csr_rdata  = 32'd0;
            end
        endcase
    end

    assign o_csr_rdata = w_csr_rdata;

    // -----------------------------------------------------------------------
    // Access check
    // -----------------------------------------------------------------------
    logic w_read_only;
    logic w_priv_ok;
    logic w_counter_ok;

    assign w_read_only = (i_csr_addr[11:10] == 2'b11);
    assign w_priv_ok   = (r_priv >= priv_lvl_e'(i_csr_addr[9:8]));

    // User counter access check
    always_comb begin
        w_counter_ok = 1'b1;
        if (r_priv == PRIV_U) begin
            unique case (i_csr_addr)
                CSR_CYCLE, CSR_CYCLEH:     w_counter_ok = r_mcounteren_cy;
                CSR_TIME, CSR_TIMEH:       w_counter_ok = r_mcounteren_tm;
                CSR_INSTRET, CSR_INSTRETH: w_counter_ok = r_mcounteren_ir;
                default: w_counter_ok = 1'b1;
            endcase
        end
    end

    // CSR is illegal if: doesn't exist, or privilege violation, or
    // write to read-only CSR
    logic w_is_write;
    assign w_is_write = i_csr_en &&
                        ((i_csr_op == CSR_RW) ||
                         (i_csr_op == CSR_RS && i_csr_wdata != 32'd0) ||
                         (i_csr_op == CSR_RC && i_csr_wdata != 32'd0));

    assign o_csr_illegal = i_csr_en &&
                           (!w_csr_exists || !w_priv_ok || !w_counter_ok ||
                            (w_read_only && w_is_write));

    // -----------------------------------------------------------------------
    // CSR write value computation
    // -----------------------------------------------------------------------
    logic [31:0] w_csr_wval;
    always_comb begin
        w_csr_wval = 32'd0;
        unique case (i_csr_op)
            CSR_RW: w_csr_wval = i_csr_wdata;
            CSR_RS: w_csr_wval = w_csr_rdata | i_csr_wdata;
            CSR_RC: w_csr_wval = w_csr_rdata & ~i_csr_wdata;
            default: w_csr_wval = i_csr_wdata;
        endcase
    end

    // Do we actually write?
    logic w_do_write;
    assign w_do_write = i_csr_en && !o_csr_illegal && !w_read_only &&
                        !o_trap_taken; // Don't write CSR if trap is being taken

    // -----------------------------------------------------------------------
    // Sequential — CSR updates, trap handling, MRET
    // -----------------------------------------------------------------------
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_priv           <= PRIV_M;
            r_mstatus_mie    <= 1'b0;
            r_mstatus_mpie   <= 1'b0;
            r_mstatus_mpp    <= PRIV_M;
            r_mstatus_mprv   <= 1'b0;
            r_mie_meie       <= 1'b0;
            r_mie_mtie       <= 1'b0;
            r_mie_msie       <= 1'b0;
            r_mie_fast       <= 15'd0;
            r_mtvec          <= 32'd0;
            r_mcounteren_cy  <= 1'b0;
            r_mcounteren_tm  <= 1'b0;
            r_mcounteren_ir  <= 1'b0;
            r_mscratch       <= 32'd0;
            r_mepc           <= 32'd0;
            r_mcause         <= 32'd0;
            r_mtval          <= 32'd0;
            r_mcycle         <= 64'd0;
            r_minstret       <= 64'd0;
            r_debug_mode     <= 1'b0;
            r_dcsr           <= {4'd4, 16'd0, 12'd0};  // xdebugver=4, prv=M
            r_dpc            <= 32'd0;
            r_dscratch0      <= 32'd0;
            r_dscratch1      <= 32'd0;
            for (int i = 0; i < PMP_REGIONS; i++) begin
                r_pmpcfg[i]  <= 8'd0;
                r_pmpaddr[i] <= 32'd0;
            end
        end else begin

            // ---- Counters (always tick) ----
            r_mcycle <= r_mcycle + 64'd1;
            if (i_instr_retired) begin
                r_minstret <= r_minstret + 64'd1;
            end

            // ---- Debug Mode Entry (highest priority) ----
            if (w_debug_entry) begin
                r_debug_mode   <= 1'b1;
                r_dpc          <= i_exc_pc;
                r_dcsr[8:6]    <= w_debug_cause;
                r_dcsr[1:0]    <= r_priv;  // Save current privilege

            // ---- Debug Mode Exit (DRET) ----
            end else if (o_dret_taken) begin
                r_debug_mode   <= 1'b0;
                r_priv         <= priv_lvl_e'(r_dcsr[1:0]);

            // ---- Trap Entry ----
            end else if (o_trap_taken) begin
                // Save state
                r_mepc         <= i_exc_valid ? i_exc_pc :
                                  i_exc_pc;  // For interrupts, mepc = PC of interrupted instr
                r_mcause       <= i_exc_valid ? i_exc_cause : w_irq_cause;
                r_mtval        <= i_exc_valid ? i_exc_tval : 32'd0;

                // Update mstatus
                r_mstatus_mpie <= r_mstatus_mie;
                r_mstatus_mie  <= 1'b0;
                r_mstatus_mpp  <= r_priv;

                // Enter M-mode
                r_priv         <= PRIV_M;

            // ---- MRET ----
            end else if (i_is_mret) begin
                r_mstatus_mie  <= r_mstatus_mpie;
                r_mstatus_mpie <= 1'b1;
                r_priv         <= r_mstatus_mpp;
                // If MPP != M, clear MPRV (spec 3.1.6.1)
                if (r_mstatus_mpp != PRIV_M) begin
                    r_mstatus_mprv <= 1'b0;
                end
                r_mstatus_mpp  <= PRIV_U;  // Set MPP to least-privileged

            // ---- CSR writes ----
            end else if (w_do_write) begin
                unique case (i_csr_addr)
                    CSR_MSTATUS: begin
                        r_mstatus_mie  <= w_csr_wval[3];
                        r_mstatus_mpie <= w_csr_wval[7];
                        // MPP can only be M or U
                        if (w_csr_wval[12:11] == 2'b11 || w_csr_wval[12:11] == 2'b00)
                            r_mstatus_mpp <= priv_lvl_e'(w_csr_wval[12:11]);
                        r_mstatus_mprv <= w_csr_wval[17];
                    end

                    CSR_MIE: begin
                        r_mie_meie <= w_csr_wval[11];
                        r_mie_mtie <= w_csr_wval[7];
                        r_mie_msie <= w_csr_wval[3];
                        r_mie_fast <= w_csr_wval[30:16];
                    end

                    CSR_MTVEC: begin
                        // MODE can be 0 (Direct) or 1 (Vectored)
                        r_mtvec <= {w_csr_wval[31:2], w_csr_wval[1] ? 2'b00 : w_csr_wval[1:0]};
                    end

                    CSR_MCOUNTEREN: begin
                        r_mcounteren_cy <= w_csr_wval[0];
                        r_mcounteren_tm <= w_csr_wval[1];
                        r_mcounteren_ir <= w_csr_wval[2];
                    end

                    CSR_MSCRATCH: r_mscratch <= w_csr_wval;
                    CSR_MEPC:     r_mepc     <= {w_csr_wval[31:1], 1'b0}; // bit 0 always 0
                    CSR_MCAUSE:   r_mcause   <= w_csr_wval;
                    CSR_MTVAL:    r_mtval    <= w_csr_wval;

                    // MIP: MEIP/MTIP/MSIP are read-only (external), no writable bits for M+U
                    CSR_MIP: begin
                        // Nothing writable in M+U mode
                    end

                    CSR_MCYCLE:    r_mcycle[31:0]   <= w_csr_wval;
                    CSR_MCYCLEH:   r_mcycle[63:32]  <= w_csr_wval;
                    CSR_MINSTRET:  r_minstret[31:0] <= w_csr_wval;
                    CSR_MINSTRETH: r_minstret[63:32] <= w_csr_wval;

                    // PMP Config
                    CSR_PMPCFG0: begin
                        for (int i = 0; i < 4; i++)
                            if (!r_pmpcfg[i][7]) // Lock bit check
                                r_pmpcfg[i] <= w_csr_wval[i*8 +: 8];
                    end
                    CSR_PMPCFG1: begin
                        for (int i = 0; i < 4; i++)
                            if (!r_pmpcfg[4+i][7])
                                r_pmpcfg[4+i] <= w_csr_wval[i*8 +: 8];
                    end
                    CSR_PMPCFG2: begin
                        for (int i = 0; i < 4; i++)
                            if (!r_pmpcfg[8+i][7])
                                r_pmpcfg[8+i] <= w_csr_wval[i*8 +: 8];
                    end
                    CSR_PMPCFG3: begin
                        for (int i = 0; i < 4; i++)
                            if (!r_pmpcfg[12+i][7])
                                r_pmpcfg[12+i] <= w_csr_wval[i*8 +: 8];
                    end

                    // PMP Address
                    CSR_PMPADDR0:  if (!r_pmpcfg[0][7])  r_pmpaddr[0]  <= w_csr_wval;
                    CSR_PMPADDR1:  if (!r_pmpcfg[1][7])  r_pmpaddr[1]  <= w_csr_wval;
                    CSR_PMPADDR2:  if (!r_pmpcfg[2][7])  r_pmpaddr[2]  <= w_csr_wval;
                    CSR_PMPADDR3:  if (!r_pmpcfg[3][7])  r_pmpaddr[3]  <= w_csr_wval;
                    CSR_PMPADDR4:  if (!r_pmpcfg[4][7])  r_pmpaddr[4]  <= w_csr_wval;
                    CSR_PMPADDR5:  if (!r_pmpcfg[5][7])  r_pmpaddr[5]  <= w_csr_wval;
                    CSR_PMPADDR6:  if (!r_pmpcfg[6][7])  r_pmpaddr[6]  <= w_csr_wval;
                    CSR_PMPADDR7:  if (!r_pmpcfg[7][7])  r_pmpaddr[7]  <= w_csr_wval;
                    CSR_PMPADDR8:  if (!r_pmpcfg[8][7])  r_pmpaddr[8]  <= w_csr_wval;
                    CSR_PMPADDR9:  if (!r_pmpcfg[9][7])  r_pmpaddr[9]  <= w_csr_wval;
                    CSR_PMPADDR10: if (!r_pmpcfg[10][7]) r_pmpaddr[10] <= w_csr_wval;
                    CSR_PMPADDR11: if (!r_pmpcfg[11][7]) r_pmpaddr[11] <= w_csr_wval;
                    CSR_PMPADDR12: if (!r_pmpcfg[12][7]) r_pmpaddr[12] <= w_csr_wval;
                    CSR_PMPADDR13: if (!r_pmpcfg[13][7]) r_pmpaddr[13] <= w_csr_wval;
                    CSR_PMPADDR14: if (!r_pmpcfg[14][7]) r_pmpaddr[14] <= w_csr_wval;
                    CSR_PMPADDR15: if (!r_pmpcfg[15][7]) r_pmpaddr[15] <= w_csr_wval;

                    // Debug CSRs
                    CSR_DCSR: begin
                        // Only writable fields: ebreakm[15], step[2], prv[1:0]
                        r_dcsr[15]  <= w_csr_wval[15];  // ebreakm
                        r_dcsr[2]   <= w_csr_wval[2];   // step
                        if (w_csr_wval[1:0] == 2'b11 || w_csr_wval[1:0] == 2'b00)
                            r_dcsr[1:0] <= w_csr_wval[1:0];  // prv
                    end
                    CSR_DPC:       r_dpc       <= {w_csr_wval[31:1], 1'b0};
                    CSR_DSCRATCH0: r_dscratch0 <= w_csr_wval;
                    CSR_DSCRATCH1: r_dscratch1 <= w_csr_wval;

                    default: ; // Unknown — silently ignore (illegal already flagged)
                endcase
            end
        end
    end

endmodule : k10_csr
