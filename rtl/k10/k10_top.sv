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
// K10 — SoC Top
// ============================================================================
// Top-level System-on-Chip wrapper for the K10 core.
//
// Architecture:
//   k10_core ──► bus2axi4lite (ibus) ──► ┐
//            ──► bus2axi4lite (dbus) ──► ├─ AXI4-Lite Crossbar ──► BRAM (S0)
//                                        │                     ──► Periph (S1)
//                                        └───────────────────────────────────
//
// Address Map (fully parametric):
//   Slave 0 (BRAM):  MEM_BASE .. MEM_BASE + MEM_SIZE - 1
//   Slave 1 (Periph): PERI_BASE .. PERI_BASE + PERI_SIZE - 1
//
// The peripheral slave port is exposed externally so that UART, GPIO, timer
// etc. can be attached at the next level of hierarchy.
//
// Parameters:
//   MEM_SIZE_KB   — BRAM size in kilobytes (must be power of 2).
//   MEM_BASE      — Base address for BRAM.
//   PERI_BASE     — Base address for peripheral region.
//   PERI_SIZE     — Size of peripheral region (for address decoding mask).
//   BOOT_ADDR     — Initial PC value.
// ============================================================================

module k10_top
  import komandara_k10_pkg::*;
#(
    // Memory
    parameter int          MEM_SIZE_KB  = 64,
    parameter logic [31:0] MEM_BASE     = 32'h0000_0000,
    parameter logic [31:0] MEM_MASK     = 32'hFFFF_0000,  // Top bits for 64KB
    parameter              MEM_INIT     = "",

    // Peripherals
    parameter logic [31:0] PERI_BASE    = 32'h4000_0000,
    parameter logic [31:0] PERI_MASK    = 32'hF000_0000,

    // Boot
    parameter logic [31:0] BOOT_ADDR   = 32'h0000_0000,

    // Core
    parameter int unsigned PMP_REGIONS = 16,
    parameter logic [31:0] MHARTID     = 32'd0
)(
    input  logic        i_clk,
    input  logic        i_rst_n,

    // ==== External interrupts ====
    input  logic        i_ext_irq,
    input  logic        i_timer_irq,
    input  logic        i_sw_irq,

    // ==== Timer ====
    input  logic [63:0] i_mtime,

    // ==== Peripheral AXI4-Lite slave port (directly exposed) ====
    // This connects to the crossbar's S1 master port — user attaches
    // peripherals (UART, GPIO, etc.) to these signals.
    output logic [31:0] o_peri_awaddr,
    output logic [2:0]  o_peri_awprot,
    output logic        o_peri_awvalid,
    input  logic        o_peri_awready,

    output logic [31:0] o_peri_wdata,
    output logic [3:0]  o_peri_wstrb,
    output logic        o_peri_wvalid,
    input  logic        o_peri_wready,

    input  logic [1:0]  i_peri_bresp,
    input  logic        i_peri_bvalid,
    output logic        o_peri_bready,

    output logic [31:0] o_peri_araddr,
    output logic [2:0]  o_peri_arprot,
    output logic        o_peri_arvalid,
    input  logic        o_peri_arready,

    input  logic [31:0] i_peri_rdata,
    input  logic [1:0]  i_peri_rresp,
    input  logic        i_peri_rvalid,
    output logic        o_peri_rready
);

    // -----------------------------------------------------------------------
    // Derived parameters
    // -----------------------------------------------------------------------
    localparam int MEM_WORDS      = (MEM_SIZE_KB * 1024) / 4;
    localparam int MEM_ADDR_WIDTH = $clog2(MEM_WORDS);

    // Crossbar parameters
    localparam int N_MASTERS = 2;   // ibus, dbus
    localparam int N_SLAVES  = 2;   // BRAM, Periph

    // -----------------------------------------------------------------------
    // Core bus signals
    // -----------------------------------------------------------------------
    // Instruction bus
    logic        w_ibus_req, w_ibus_gnt, w_ibus_rvalid, w_ibus_err;
    logic [31:0] w_ibus_addr, w_ibus_rdata;

    // Data bus
    logic        w_dbus_req, w_dbus_we, w_dbus_gnt, w_dbus_rvalid, w_dbus_err;
    logic [31:0] w_dbus_addr, w_dbus_wdata, w_dbus_rdata;
    logic [3:0]  w_dbus_wstrb;

    // -----------------------------------------------------------------------
    // Core instance
    // -----------------------------------------------------------------------
    k10_core #(
        .BOOT_ADDR   (BOOT_ADDR),
        .PMP_REGIONS (PMP_REGIONS),
        .MHARTID     (MHARTID)
    ) u_core (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        // Instruction bus
        .o_ibus_req    (w_ibus_req),
        .o_ibus_addr   (w_ibus_addr),
        .i_ibus_gnt    (w_ibus_gnt),
        .i_ibus_rvalid (w_ibus_rvalid),
        .i_ibus_rdata  (w_ibus_rdata),
        .i_ibus_err    (w_ibus_err),
        // Data bus
        .o_dbus_req    (w_dbus_req),
        .o_dbus_we     (w_dbus_we),
        .o_dbus_addr   (w_dbus_addr),
        .o_dbus_wdata  (w_dbus_wdata),
        .o_dbus_wstrb  (w_dbus_wstrb),
        .i_dbus_gnt    (w_dbus_gnt),
        .i_dbus_rvalid (w_dbus_rvalid),
        .i_dbus_rdata  (w_dbus_rdata),
        .i_dbus_err    (w_dbus_err),
        // Interrupts
        .i_ext_irq     (i_ext_irq),
        .i_timer_irq   (i_timer_irq),
        .i_sw_irq      (i_sw_irq),
        .i_mtime       (i_mtime)
    );

    // -----------------------------------------------------------------------
    // Bus → AXI4-Lite adapters
    // -----------------------------------------------------------------------

    // ---- Master 0: Instruction bus (read-only) ----
    logic [31:0] w_m0_awaddr, w_m0_wdata, w_m0_araddr, w_m0_rdata;
    logic [2:0]  w_m0_awprot, w_m0_arprot;
    logic [3:0]  w_m0_wstrb;
    logic [1:0]  w_m0_bresp, w_m0_rresp;
    logic        w_m0_awvalid, w_m0_awready;
    logic        w_m0_wvalid, w_m0_wready;
    logic        w_m0_bvalid, w_m0_bready;
    logic        w_m0_arvalid, w_m0_arready;
    logic        w_m0_rvalid, w_m0_rready;

    komandara_bus2axi4lite #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32)
    ) u_ibus_adapter (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_req         (w_ibus_req),
        .i_we          (1'b0),          // Instruction bus is read-only
        .i_addr        (w_ibus_addr),
        .i_wdata       (32'd0),
        .i_wstrb       (4'd0),
        .o_gnt         (w_ibus_gnt),
        .o_rvalid      (w_ibus_rvalid),
        .o_rdata       (w_ibus_rdata),
        .o_err         (w_ibus_err),
        // AXI4-Lite
        .m_axi_awaddr  (w_m0_awaddr),
        .m_axi_awprot  (w_m0_awprot),
        .m_axi_awvalid (w_m0_awvalid),
        .m_axi_awready (w_m0_awready),
        .m_axi_wdata   (w_m0_wdata),
        .m_axi_wstrb   (w_m0_wstrb),
        .m_axi_wvalid  (w_m0_wvalid),
        .m_axi_wready  (w_m0_wready),
        .m_axi_bresp   (w_m0_bresp),
        .m_axi_bvalid  (w_m0_bvalid),
        .m_axi_bready  (w_m0_bready),
        .m_axi_araddr  (w_m0_araddr),
        .m_axi_arprot  (w_m0_arprot),
        .m_axi_arvalid (w_m0_arvalid),
        .m_axi_arready (w_m0_arready),
        .m_axi_rdata   (w_m0_rdata),
        .m_axi_rresp   (w_m0_rresp),
        .m_axi_rvalid  (w_m0_rvalid),
        .m_axi_rready  (w_m0_rready)
    );

    // ---- Master 1: Data bus (read/write) ----
    logic [31:0] w_m1_awaddr, w_m1_wdata, w_m1_araddr, w_m1_rdata;
    logic [2:0]  w_m1_awprot, w_m1_arprot;
    logic [3:0]  w_m1_wstrb;
    logic [1:0]  w_m1_bresp, w_m1_rresp;
    logic        w_m1_awvalid, w_m1_awready;
    logic        w_m1_wvalid, w_m1_wready;
    logic        w_m1_bvalid, w_m1_bready;
    logic        w_m1_arvalid, w_m1_arready;
    logic        w_m1_rvalid, w_m1_rready;

    komandara_bus2axi4lite #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32)
    ) u_dbus_adapter (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_req         (w_dbus_req),
        .i_we          (w_dbus_we),
        .i_addr        (w_dbus_addr),
        .i_wdata       (w_dbus_wdata),
        .i_wstrb       (w_dbus_wstrb),
        .o_gnt         (w_dbus_gnt),
        .o_rvalid      (w_dbus_rvalid),
        .o_rdata       (w_dbus_rdata),
        .o_err         (w_dbus_err),
        // AXI4-Lite
        .m_axi_awaddr  (w_m1_awaddr),
        .m_axi_awprot  (w_m1_awprot),
        .m_axi_awvalid (w_m1_awvalid),
        .m_axi_awready (w_m1_awready),
        .m_axi_wdata   (w_m1_wdata),
        .m_axi_wstrb   (w_m1_wstrb),
        .m_axi_wvalid  (w_m1_wvalid),
        .m_axi_wready  (w_m1_wready),
        .m_axi_bresp   (w_m1_bresp),
        .m_axi_bvalid  (w_m1_bvalid),
        .m_axi_bready  (w_m1_bready),
        .m_axi_araddr  (w_m1_araddr),
        .m_axi_arprot  (w_m1_arprot),
        .m_axi_arvalid (w_m1_arvalid),
        .m_axi_arready (w_m1_arready),
        .m_axi_rdata   (w_m1_rdata),
        .m_axi_rresp   (w_m1_rresp),
        .m_axi_rvalid  (w_m1_rvalid),
        .m_axi_rready  (w_m1_rready)
    );

    // -----------------------------------------------------------------------
    // AXI4-Lite Crossbar  (2 Masters × 2 Slaves)
    // -----------------------------------------------------------------------

    // Crossbar master-side (slave ports — from bus adapters)
    logic [N_MASTERS-1:0][31:0] w_xbar_s_awaddr;
    logic [N_MASTERS-1:0][2:0]  w_xbar_s_awprot;
    logic [N_MASTERS-1:0]       w_xbar_s_awvalid;
    logic [N_MASTERS-1:0]       w_xbar_s_awready;
    logic [N_MASTERS-1:0][31:0] w_xbar_s_wdata;
    logic [N_MASTERS-1:0][3:0]  w_xbar_s_wstrb;
    logic [N_MASTERS-1:0]       w_xbar_s_wvalid;
    logic [N_MASTERS-1:0]       w_xbar_s_wready;
    logic [N_MASTERS-1:0][1:0]  w_xbar_s_bresp;
    logic [N_MASTERS-1:0]       w_xbar_s_bvalid;
    logic [N_MASTERS-1:0]       w_xbar_s_bready;
    logic [N_MASTERS-1:0][31:0] w_xbar_s_araddr;
    logic [N_MASTERS-1:0][2:0]  w_xbar_s_arprot;
    logic [N_MASTERS-1:0]       w_xbar_s_arvalid;
    logic [N_MASTERS-1:0]       w_xbar_s_arready;
    logic [N_MASTERS-1:0][31:0] w_xbar_s_rdata;
    logic [N_MASTERS-1:0][1:0]  w_xbar_s_rresp;
    logic [N_MASTERS-1:0]       w_xbar_s_rvalid;
    logic [N_MASTERS-1:0]       w_xbar_s_rready;

    // Connect masters to crossbar slave ports
    // Master 0: ibus
    assign w_xbar_s_awaddr[0]  = w_m0_awaddr;
    assign w_xbar_s_awprot[0]  = w_m0_awprot;
    assign w_xbar_s_awvalid[0] = w_m0_awvalid;
    assign w_m0_awready        = w_xbar_s_awready[0];
    assign w_xbar_s_wdata[0]   = w_m0_wdata;
    assign w_xbar_s_wstrb[0]   = w_m0_wstrb;
    assign w_xbar_s_wvalid[0]  = w_m0_wvalid;
    assign w_m0_wready         = w_xbar_s_wready[0];
    assign w_m0_bresp          = w_xbar_s_bresp[0];
    assign w_m0_bvalid         = w_xbar_s_bvalid[0];
    assign w_xbar_s_bready[0]  = w_m0_bready;
    assign w_xbar_s_araddr[0]  = w_m0_araddr;
    assign w_xbar_s_arprot[0]  = w_m0_arprot;
    assign w_xbar_s_arvalid[0] = w_m0_arvalid;
    assign w_m0_arready        = w_xbar_s_arready[0];
    assign w_m0_rdata          = w_xbar_s_rdata[0];
    assign w_m0_rresp          = w_xbar_s_rresp[0];
    assign w_m0_rvalid         = w_xbar_s_rvalid[0];
    assign w_xbar_s_rready[0]  = w_m0_rready;

    // Master 1: dbus
    assign w_xbar_s_awaddr[1]  = w_m1_awaddr;
    assign w_xbar_s_awprot[1]  = w_m1_awprot;
    assign w_xbar_s_awvalid[1] = w_m1_awvalid;
    assign w_m1_awready        = w_xbar_s_awready[1];
    assign w_xbar_s_wdata[1]   = w_m1_wdata;
    assign w_xbar_s_wstrb[1]   = w_m1_wstrb;
    assign w_xbar_s_wvalid[1]  = w_m1_wvalid;
    assign w_m1_wready         = w_xbar_s_wready[1];
    assign w_m1_bresp          = w_xbar_s_bresp[1];
    assign w_m1_bvalid         = w_xbar_s_bvalid[1];
    assign w_xbar_s_bready[1]  = w_m1_bready;
    assign w_xbar_s_araddr[1]  = w_m1_araddr;
    assign w_xbar_s_arprot[1]  = w_m1_arprot;
    assign w_xbar_s_arvalid[1] = w_m1_arvalid;
    assign w_m1_arready        = w_xbar_s_arready[1];
    assign w_m1_rdata          = w_xbar_s_rdata[1];
    assign w_m1_rresp          = w_xbar_s_rresp[1];
    assign w_m1_rvalid         = w_xbar_s_rvalid[1];
    assign w_xbar_s_rready[1]  = w_m1_rready;

    // Crossbar slave-side (master ports — to BRAM and peripherals)
    logic [N_SLAVES-1:0][31:0] w_xbar_m_awaddr;
    logic [N_SLAVES-1:0][2:0]  w_xbar_m_awprot;
    logic [N_SLAVES-1:0]       w_xbar_m_awvalid;
    logic [N_SLAVES-1:0]       w_xbar_m_awready;
    logic [N_SLAVES-1:0][31:0] w_xbar_m_wdata;
    logic [N_SLAVES-1:0][3:0]  w_xbar_m_wstrb;
    logic [N_SLAVES-1:0]       w_xbar_m_wvalid;
    logic [N_SLAVES-1:0]       w_xbar_m_wready;
    logic [N_SLAVES-1:0][1:0]  w_xbar_m_bresp;
    logic [N_SLAVES-1:0]       w_xbar_m_bvalid;
    logic [N_SLAVES-1:0]       w_xbar_m_bready;
    logic [N_SLAVES-1:0][31:0] w_xbar_m_araddr;
    logic [N_SLAVES-1:0][2:0]  w_xbar_m_arprot;
    logic [N_SLAVES-1:0]       w_xbar_m_arvalid;
    logic [N_SLAVES-1:0]       w_xbar_m_arready;
    logic [N_SLAVES-1:0][31:0] w_xbar_m_rdata;
    logic [N_SLAVES-1:0][1:0]  w_xbar_m_rresp;
    logic [N_SLAVES-1:0]       w_xbar_m_rvalid;
    logic [N_SLAVES-1:0]       w_xbar_m_rready;

    // Address map for crossbar
    // Slave 0: BRAM at MEM_BASE  / MEM_MASK
    // Slave 1: Periph at PERI_BASE / PERI_MASK
    komandara_axi4lite_xbar #(
        .N_MASTERS       (N_MASTERS),
        .N_SLAVES        (N_SLAVES),
        .ADDR_WIDTH      (32),
        .DATA_WIDTH      (32),
        .ROUND_ROBIN     (1'b0),   // Fixed priority: ibus > dbus
        .SLAVE_ADDR_BASE ({PERI_BASE, MEM_BASE}),
        .SLAVE_ADDR_MASK ({PERI_MASK, MEM_MASK})
    ) u_xbar (
        .clk_i           (i_clk),
        .rst_ni          (i_rst_n),
        // Master-side (slave ports)
        .s_axi_awaddr_i  (w_xbar_s_awaddr),
        .s_axi_awprot_i  (w_xbar_s_awprot),
        .s_axi_awvalid_i (w_xbar_s_awvalid),
        .s_axi_awready_o (w_xbar_s_awready),
        .s_axi_wdata_i   (w_xbar_s_wdata),
        .s_axi_wstrb_i   (w_xbar_s_wstrb),
        .s_axi_wvalid_i  (w_xbar_s_wvalid),
        .s_axi_wready_o  (w_xbar_s_wready),
        .s_axi_bresp_o   (w_xbar_s_bresp),
        .s_axi_bvalid_o  (w_xbar_s_bvalid),
        .s_axi_bready_i  (w_xbar_s_bready),
        .s_axi_araddr_i  (w_xbar_s_araddr),
        .s_axi_arprot_i  (w_xbar_s_arprot),
        .s_axi_arvalid_i (w_xbar_s_arvalid),
        .s_axi_arready_o (w_xbar_s_arready),
        .s_axi_rdata_o   (w_xbar_s_rdata),
        .s_axi_rresp_o   (w_xbar_s_rresp),
        .s_axi_rvalid_o  (w_xbar_s_rvalid),
        .s_axi_rready_i  (w_xbar_s_rready),
        // Slave-side (master ports)
        .m_axi_awaddr_o  (w_xbar_m_awaddr),
        .m_axi_awprot_o  (w_xbar_m_awprot),
        .m_axi_awvalid_o (w_xbar_m_awvalid),
        .m_axi_awready_i (w_xbar_m_awready),
        .m_axi_wdata_o   (w_xbar_m_wdata),
        .m_axi_wstrb_o   (w_xbar_m_wstrb),
        .m_axi_wvalid_o  (w_xbar_m_wvalid),
        .m_axi_wready_i  (w_xbar_m_wready),
        .m_axi_bresp_i   (w_xbar_m_bresp),
        .m_axi_bvalid_i  (w_xbar_m_bvalid),
        .m_axi_bready_o  (w_xbar_m_bready),
        .m_axi_araddr_o  (w_xbar_m_araddr),
        .m_axi_arprot_o  (w_xbar_m_arprot),
        .m_axi_arvalid_o (w_xbar_m_arvalid),
        .m_axi_arready_i (w_xbar_m_arready),
        .m_axi_rdata_i   (w_xbar_m_rdata),
        .m_axi_rresp_i   (w_xbar_m_rresp),
        .m_axi_rvalid_i  (w_xbar_m_rvalid),
        .m_axi_rready_o  (w_xbar_m_rready)
    );

    // -----------------------------------------------------------------------
    // Slave 0: BRAM
    // -----------------------------------------------------------------------
    komandara_bram_axi4lite #(
        .MEM_ADDR_WIDTH (MEM_ADDR_WIDTH),
        .AXI_ADDR_WIDTH (32),
        .AXI_DATA_WIDTH (32),
        .INIT_FILE      (MEM_INIT)
    ) u_bram (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .s_axi_awaddr   (w_xbar_m_awaddr[0]),
        .s_axi_awprot   (w_xbar_m_awprot[0]),
        .s_axi_awvalid  (w_xbar_m_awvalid[0]),
        .s_axi_awready  (w_xbar_m_awready[0]),
        .s_axi_wdata    (w_xbar_m_wdata[0]),
        .s_axi_wstrb    (w_xbar_m_wstrb[0]),
        .s_axi_wvalid   (w_xbar_m_wvalid[0]),
        .s_axi_wready   (w_xbar_m_wready[0]),
        .s_axi_bresp    (w_xbar_m_bresp[0]),
        .s_axi_bvalid   (w_xbar_m_bvalid[0]),
        .s_axi_bready   (w_xbar_m_bready[0]),
        .s_axi_araddr   (w_xbar_m_araddr[0]),
        .s_axi_arprot   (w_xbar_m_arprot[0]),
        .s_axi_arvalid  (w_xbar_m_arvalid[0]),
        .s_axi_arready  (w_xbar_m_arready[0]),
        .s_axi_rdata    (w_xbar_m_rdata[0]),
        .s_axi_rresp    (w_xbar_m_rresp[0]),
        .s_axi_rvalid   (w_xbar_m_rvalid[0]),
        .s_axi_rready   (w_xbar_m_rready[0])
    );

    // -----------------------------------------------------------------------
    // Slave 1: Peripheral port (exposed externally)
    // -----------------------------------------------------------------------
    assign o_peri_awaddr  = w_xbar_m_awaddr[1];
    assign o_peri_awprot  = w_xbar_m_awprot[1];
    assign o_peri_awvalid = w_xbar_m_awvalid[1];
    assign w_xbar_m_awready[1] = o_peri_awready;

    assign o_peri_wdata   = w_xbar_m_wdata[1];
    assign o_peri_wstrb   = w_xbar_m_wstrb[1];
    assign o_peri_wvalid  = w_xbar_m_wvalid[1];
    assign w_xbar_m_wready[1] = o_peri_wready;

    assign w_xbar_m_bresp[1]  = i_peri_bresp;
    assign w_xbar_m_bvalid[1] = i_peri_bvalid;
    assign o_peri_bready = w_xbar_m_bready[1];

    assign o_peri_araddr  = w_xbar_m_araddr[1];
    assign o_peri_arprot  = w_xbar_m_arprot[1];
    assign o_peri_arvalid = w_xbar_m_arvalid[1];
    assign w_xbar_m_arready[1] = o_peri_arready;

    assign w_xbar_m_rdata[1]  = i_peri_rdata;
    assign w_xbar_m_rresp[1]  = i_peri_rresp;
    assign w_xbar_m_rvalid[1] = i_peri_rvalid;
    assign o_peri_rready = w_xbar_m_rready[1];

endmodule : k10_top
