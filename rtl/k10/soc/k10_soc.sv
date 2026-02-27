// Copyright 2026 The Komandara Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

module k10_soc
  import komandara_k10_pkg::*;
#(
    parameter int          MEM_SIZE_KB = 64,
    parameter logic [31:0] MEM_BASE    = 32'h8000_0000,
    parameter logic [31:0] MEM_MASK    = 32'hFFFF_0000,
    parameter              MEM_INIT    = "",
    parameter logic [31:0] PERI_BASE   = 32'h4000_0000,
    parameter logic [31:0] PERI_MASK   = 32'hF000_0000,
    parameter logic [31:0] BOOT_ADDR   = 32'h8000_0000
)(
    input  logic        i_clk,
    input  logic        i_rst_n,
    input  logic        i_ext_irq,
    input  logic [14:0] i_irq_fast,
    input  logic        i_debug_req,
    input  logic        i_jtag_tck,
    input  logic        i_jtag_tms,
    input  logic        i_jtag_trst_n,
    input  logic        i_jtag_tdi,
    output logic        o_jtag_tdo,
    input  logic        i_uart_rx,
    output logic        o_uart_tx,
    output logic        o_timer_irq,
    output logic        o_sw_irq,
    output logic        o_uart_irq,
    output logic [63:0] o_mtime
);

    localparam int MEM_WORDS      = (MEM_SIZE_KB * 1024) / 4;
    localparam int MEM_ADDR_WIDTH = $clog2(MEM_WORDS);
    localparam int N_MASTERS      = 3;
    localparam int N_SLAVES       = 5;
    localparam int SLV_BRAM       = 0;
    localparam int SLV_TIMER      = 1;
    localparam int SLV_SIM_CTRL   = 2;
    localparam int SLV_UART       = 3;
    localparam int SLV_DM         = 4;

    localparam logic [31:0] TIMER_BASE    = PERI_BASE + 32'h0000;
    localparam logic [31:0] TIMER_MASK    = 32'hFFFF_F000;
    localparam logic [31:0] SIM_CTRL_BASE = PERI_BASE + 32'h1000;
    localparam logic [31:0] SIM_CTRL_MASK = 32'hFFFF_F000;
    localparam logic [31:0] UART_BASE     = PERI_BASE + 32'h2000;
    localparam logic [31:0] UART_MASK     = 32'hFFFF_F000;
    localparam logic [31:0] DM_BASE       = PERI_BASE + 32'h3000;
    localparam logic [31:0] DM_MASK       = 32'hFFFF_F000;
    localparam logic [31:0] DM_HALT_ADDR  = DM_BASE + 32'h0800;
    localparam logic [31:0] DM_EXC_ADDR   = DM_BASE + 32'h0810;

    logic        w_ibus_req, w_ibus_gnt, w_ibus_rvalid, w_ibus_err;
    logic [31:0] w_ibus_addr, w_ibus_rdata;
    logic        w_dbus_req, w_dbus_we, w_dbus_gnt, w_dbus_rvalid, w_dbus_err;
    logic [31:0] w_dbus_addr, w_dbus_wdata, w_dbus_rdata;
    logic [3:0]  w_dbus_wstrb;

    logic [N_MASTERS-1:0][31:0] w_m_awaddr, w_m_wdata, w_m_araddr, w_m_rdata;
    logic [N_MASTERS-1:0][2:0]  w_m_awprot, w_m_arprot;
    logic [N_MASTERS-1:0][3:0]  w_m_wstrb;
    logic [N_MASTERS-1:0][1:0]  w_m_bresp, w_m_rresp;
    logic [N_MASTERS-1:0]       w_m_awvalid, w_m_awready;
    logic [N_MASTERS-1:0]       w_m_wvalid, w_m_wready;
    logic [N_MASTERS-1:0]       w_m_bvalid, w_m_bready;
    logic [N_MASTERS-1:0]       w_m_arvalid, w_m_arready;
    logic [N_MASTERS-1:0]       w_m_rvalid, w_m_rready;

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

    (* mark_debug = "true" *) logic [31:0] w_dm_device_rdata;
    (* mark_debug = "true" *) logic        w_dm_req;
    (* mark_debug = "true" *) logic        w_dm_we;
    (* mark_debug = "true" *) logic [31:0] w_dm_addr;
    logic [3:0]  w_dm_be;
    (* mark_debug = "true" *) logic [31:0] w_dm_wdata;

    logic        w_dm_awready;
    logic        w_dm_wready;
    logic [1:0]  w_dm_bresp;
    logic        w_dm_bvalid;
    logic        w_dm_bready;
    logic        w_dm_arready;
    logic [31:0] w_dm_rdata;
    logic [1:0]  w_dm_rresp;
    logic        w_dm_rvalid;
    logic        w_dm_rready;
    logic [31:0] r_dm_rdata;
    logic [31:0] r_dm_addr;
    logic [31:0] r_dm_wdata;
    logic [3:0]  r_dm_be;

    typedef enum logic [2:0] {
        DM_IDLE,
        DM_READ_REQ,
        DM_READ_RESP,
        DM_READ_WAIT,
        DM_WRITE_REQ,
        DM_WRITE_WAIT
    } dm_axi_state_e;
    (* mark_debug = "true" *) dm_axi_state_e r_dm_state;

    logic        w_dm_host_req;
    logic [31:0] w_dm_host_addr;
    logic        w_dm_host_we;
    logic [31:0] w_dm_host_wdata;
    logic [3:0]  w_dm_host_be;
    logic        w_dm_host_gnt;
    logic        w_dm_host_rvalid;
    logic [31:0] w_dm_host_rdata;
    logic        w_dm_host_err;

    (* mark_debug = "true" *) logic        w_dm_debug_req;
    (* mark_debug = "true" *) logic        w_dm_ndmreset;
    logic        w_dmactive;
    logic        w_core_rst_n;
    logic        w_debug_mode;

    k10_top #(
        .BOOT_ADDR (BOOT_ADDR),
        .DEBUG_HALT_ADDR (DM_HALT_ADDR),
        .DEBUG_EXCEPTION_ADDR (DM_EXC_ADDR)
    ) u_top (
        .i_clk         (i_clk),
        .i_rst_n       (w_core_rst_n),
        .i_ext_irq     (i_ext_irq || o_uart_irq),
        .i_timer_irq   (o_timer_irq),
        .i_sw_irq      (o_sw_irq),
        .i_irq_fast    (i_irq_fast),
        .i_debug_req   (i_debug_req || w_dm_debug_req),
        .o_debug_mode  (w_debug_mode),
        .i_mtime       (o_mtime),
        .o_ibus_req    (w_ibus_req),
        .o_ibus_addr   (w_ibus_addr),
        .i_ibus_gnt    (w_ibus_gnt),
        .i_ibus_rvalid (w_ibus_rvalid),
        .i_ibus_rdata  (w_ibus_rdata),
        .i_ibus_err    (w_ibus_err),
        .o_dbus_req    (w_dbus_req),
        .o_dbus_we     (w_dbus_we),
        .o_dbus_addr   (w_dbus_addr),
        .o_dbus_wdata  (w_dbus_wdata),
        .o_dbus_wstrb  (w_dbus_wstrb),
        .i_dbus_gnt    (w_dbus_gnt),
        .i_dbus_rvalid (w_dbus_rvalid),
        .i_dbus_rdata  (w_dbus_rdata),
        .i_dbus_err    (w_dbus_err)
    );

    assign w_core_rst_n = i_rst_n && !w_dm_ndmreset;

    komandara_bus2axi4lite #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32)
    ) u_ibus_adapter (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_req         (w_ibus_req),
        .i_we          (1'b0),
        .i_addr        (w_ibus_addr),
        .i_wdata       (32'd0),
        .i_wstrb       (4'd0),
        .o_gnt         (w_ibus_gnt),
        .o_rvalid      (w_ibus_rvalid),
        .o_rdata       (w_ibus_rdata),
        .o_err         (w_ibus_err),
        .m_axi_awaddr  (w_m_awaddr[0]),
        .m_axi_awprot  (w_m_awprot[0]),
        .m_axi_awvalid (w_m_awvalid[0]),
        .m_axi_awready (w_m_awready[0]),
        .m_axi_wdata   (w_m_wdata[0]),
        .m_axi_wstrb   (w_m_wstrb[0]),
        .m_axi_wvalid  (w_m_wvalid[0]),
        .m_axi_wready  (w_m_wready[0]),
        .m_axi_bresp   (w_m_bresp[0]),
        .m_axi_bvalid  (w_m_bvalid[0]),
        .m_axi_bready  (w_m_bready[0]),
        .m_axi_araddr  (w_m_araddr[0]),
        .m_axi_arprot  (w_m_arprot[0]),
        .m_axi_arvalid (w_m_arvalid[0]),
        .m_axi_arready (w_m_arready[0]),
        .m_axi_rdata   (w_m_rdata[0]),
        .m_axi_rresp   (w_m_rresp[0]),
        .m_axi_rvalid  (w_m_rvalid[0]),
        .m_axi_rready  (w_m_rready[0])
    );

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
        .m_axi_awaddr  (w_m_awaddr[1]),
        .m_axi_awprot  (w_m_awprot[1]),
        .m_axi_awvalid (w_m_awvalid[1]),
        .m_axi_awready (w_m_awready[1]),
        .m_axi_wdata   (w_m_wdata[1]),
        .m_axi_wstrb   (w_m_wstrb[1]),
        .m_axi_wvalid  (w_m_wvalid[1]),
        .m_axi_wready  (w_m_wready[1]),
        .m_axi_bresp   (w_m_bresp[1]),
        .m_axi_bvalid  (w_m_bvalid[1]),
        .m_axi_bready  (w_m_bready[1]),
        .m_axi_araddr  (w_m_araddr[1]),
        .m_axi_arprot  (w_m_arprot[1]),
        .m_axi_arvalid (w_m_arvalid[1]),
        .m_axi_arready (w_m_arready[1]),
        .m_axi_rdata   (w_m_rdata[1]),
        .m_axi_rresp   (w_m_rresp[1]),
        .m_axi_rvalid  (w_m_rvalid[1]),
        .m_axi_rready  (w_m_rready[1])
    );

    komandara_bus2axi4lite #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32)
    ) u_dm_host_adapter (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_req         (w_dm_host_req),
        .i_we          (w_dm_host_we),
        .i_addr        (w_dm_host_addr),
        .i_wdata       (w_dm_host_wdata),
        .i_wstrb       (w_dm_host_be),
        .o_gnt         (w_dm_host_gnt),
        .o_rvalid      (w_dm_host_rvalid),
        .o_rdata       (w_dm_host_rdata),
        .o_err         (w_dm_host_err),
        .m_axi_awaddr  (w_m_awaddr[2]),
        .m_axi_awprot  (w_m_awprot[2]),
        .m_axi_awvalid (w_m_awvalid[2]),
        .m_axi_awready (w_m_awready[2]),
        .m_axi_wdata   (w_m_wdata[2]),
        .m_axi_wstrb   (w_m_wstrb[2]),
        .m_axi_wvalid  (w_m_wvalid[2]),
        .m_axi_wready  (w_m_wready[2]),
        .m_axi_bresp   (w_m_bresp[2]),
        .m_axi_bvalid  (w_m_bvalid[2]),
        .m_axi_bready  (w_m_bready[2]),
        .m_axi_araddr  (w_m_araddr[2]),
        .m_axi_arprot  (w_m_arprot[2]),
        .m_axi_arvalid (w_m_arvalid[2]),
        .m_axi_arready (w_m_arready[2]),
        .m_axi_rdata   (w_m_rdata[2]),
        .m_axi_rresp   (w_m_rresp[2]),
        .m_axi_rvalid  (w_m_rvalid[2]),
        .m_axi_rready  (w_m_rready[2])
    );

    genvar m;
    generate
        for (m = 0; m < N_MASTERS; m++) begin : g_master_xbar_map
            assign w_xbar_s_awaddr[m]  = w_m_awaddr[m];
            assign w_xbar_s_awprot[m]  = w_m_awprot[m];
            assign w_xbar_s_awvalid[m] = w_m_awvalid[m];
            assign w_m_awready[m]      = w_xbar_s_awready[m];
            assign w_xbar_s_wdata[m]   = w_m_wdata[m];
            assign w_xbar_s_wstrb[m]   = w_m_wstrb[m];
            assign w_xbar_s_wvalid[m]  = w_m_wvalid[m];
            assign w_m_wready[m]       = w_xbar_s_wready[m];
            assign w_m_bresp[m]        = w_xbar_s_bresp[m];
            assign w_m_bvalid[m]       = w_xbar_s_bvalid[m];
            assign w_xbar_s_bready[m]  = w_m_bready[m];
            assign w_xbar_s_araddr[m]  = w_m_araddr[m];
            assign w_xbar_s_arprot[m]  = w_m_arprot[m];
            assign w_xbar_s_arvalid[m] = w_m_arvalid[m];
            assign w_m_arready[m]      = w_xbar_s_arready[m];
            assign w_m_rdata[m]        = w_xbar_s_rdata[m];
            assign w_m_rresp[m]        = w_xbar_s_rresp[m];
            assign w_m_rvalid[m]       = w_xbar_s_rvalid[m];
            assign w_xbar_s_rready[m]  = w_m_rready[m];
        end
    endgenerate

    komandara_axi4lite_xbar #(
        .N_MASTERS       (N_MASTERS),
        .N_SLAVES        (N_SLAVES),
        .ADDR_WIDTH      (32),
        .DATA_WIDTH      (32),
        .ROUND_ROBIN     (1'b0),
        .SLAVE_ADDR_BASE ({DM_BASE, UART_BASE, SIM_CTRL_BASE, TIMER_BASE, MEM_BASE}),
        .SLAVE_ADDR_MASK ({DM_MASK, UART_MASK, SIM_CTRL_MASK, TIMER_MASK, MEM_MASK})
    ) u_xbar (
        .clk_i           (i_clk),
        .rst_ni          (i_rst_n),
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

    komandara_bram_axi4lite #(
        .MEM_ADDR_WIDTH (MEM_ADDR_WIDTH),
        .AXI_ADDR_WIDTH (32),
        .AXI_DATA_WIDTH (32),
        .INIT_FILE      (MEM_INIT)
    ) u_bram (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .s_axi_awaddr  (w_xbar_m_awaddr[0]),
        .s_axi_awprot  (w_xbar_m_awprot[0]),
        .s_axi_awvalid (w_xbar_m_awvalid[0]),
        .s_axi_awready (w_xbar_m_awready[0]),
        .s_axi_wdata   (w_xbar_m_wdata[0]),
        .s_axi_wstrb   (w_xbar_m_wstrb[0]),
        .s_axi_wvalid  (w_xbar_m_wvalid[0]),
        .s_axi_wready  (w_xbar_m_wready[0]),
        .s_axi_bresp   (w_xbar_m_bresp[0]),
        .s_axi_bvalid  (w_xbar_m_bvalid[0]),
        .s_axi_bready  (w_xbar_m_bready[0]),
        .s_axi_araddr  (w_xbar_m_araddr[0]),
        .s_axi_arprot  (w_xbar_m_arprot[0]),
        .s_axi_arvalid (w_xbar_m_arvalid[0]),
        .s_axi_arready (w_xbar_m_arready[0]),
        .s_axi_rdata   (w_xbar_m_rdata[0]),
        .s_axi_rresp   (w_xbar_m_rresp[0]),
        .s_axi_rvalid  (w_xbar_m_rvalid[0]),
        .s_axi_rready  (w_xbar_m_rready[0])
    );

    logic        r_dm_aw_pending;
    logic [31:0] r_dm_aw_addr;
    logic        r_dm_w_pending;
    logic [31:0] r_dm_w_data;
    logic [3:0]  r_dm_w_be;

    assign w_dm_awready = (!r_dm_aw_pending || (r_dm_w_pending && !w_dm_bvalid)) && (r_dm_state == DM_IDLE);
    assign w_dm_wready  = (!r_dm_w_pending  || (r_dm_aw_pending && !w_dm_bvalid)) && (r_dm_state == DM_IDLE);
    assign w_dm_bresp   = 2'b00;
    assign w_dm_arready = (r_dm_state == DM_IDLE) && !r_dm_aw_pending && !r_dm_w_pending && !w_xbar_m_awvalid[SLV_DM];
    assign w_dm_rresp   = 2'b00;

    assign w_dm_req = (r_dm_state == DM_READ_REQ) || (r_dm_state == DM_WRITE_REQ);
    assign w_dm_we = (r_dm_state == DM_WRITE_REQ);
    assign w_dm_addr = r_dm_addr;
    assign w_dm_be = r_dm_be;
    assign w_dm_wdata = r_dm_wdata;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            w_dm_bvalid     <= 1'b0;
            w_dm_rvalid     <= 1'b0;
            r_dm_rdata      <= 32'd0;
            r_dm_addr       <= 32'd0;
            r_dm_wdata      <= 32'd0;
            r_dm_be         <= 4'd0;
            r_dm_state      <= DM_IDLE;
            r_dm_aw_pending <= 1'b0;
            r_dm_aw_addr    <= 32'd0;
            r_dm_w_pending  <= 1'b0;
            r_dm_w_data     <= 32'd0;
            r_dm_w_be       <= 4'd0;
        end else begin
            if (w_xbar_m_awvalid[SLV_DM] && w_dm_awready) begin
                r_dm_aw_pending <= 1'b1;
                r_dm_aw_addr    <= w_xbar_m_awaddr[SLV_DM];
            end
            if (w_xbar_m_wvalid[SLV_DM] && w_dm_wready) begin
                r_dm_w_pending <= 1'b1;
                r_dm_w_data    <= w_xbar_m_wdata[SLV_DM];
                r_dm_w_be      <= w_xbar_m_wstrb[SLV_DM];
            end

            case (r_dm_state)
                DM_IDLE: begin
                    if (r_dm_aw_pending && r_dm_w_pending && !w_dm_bvalid) begin
                        r_dm_aw_pending <= 1'b0;
                        r_dm_w_pending  <= 1'b0;
                        r_dm_addr       <= r_dm_aw_addr;
                        r_dm_wdata      <= r_dm_w_data;
                        r_dm_be         <= r_dm_w_be;
                        r_dm_state      <= DM_WRITE_REQ;
                    end else if (w_xbar_m_arvalid[SLV_DM] && w_dm_arready) begin
                        r_dm_addr  <= w_xbar_m_araddr[SLV_DM];
                        r_dm_wdata <= 32'd0;
                        r_dm_be    <= 4'hF;
                        r_dm_state <= DM_READ_REQ;
                    end
                end

                DM_READ_REQ: begin
                    r_dm_state <= DM_READ_RESP;
                end

                DM_READ_RESP: begin
                    r_dm_rdata  <= w_dm_device_rdata;
                    w_dm_rvalid <= 1'b1;
                    r_dm_state  <= DM_READ_WAIT;
                end

                DM_READ_WAIT: begin
                    if (w_dm_rvalid && w_dm_rready) begin
                        w_dm_rvalid <= 1'b0;
                        r_dm_state  <= DM_IDLE;
                    end
                end

                DM_WRITE_REQ: begin
                    w_dm_bvalid <= 1'b1;
                    r_dm_state  <= DM_WRITE_WAIT;
                end

                DM_WRITE_WAIT: begin
                    if (w_dm_bvalid && w_dm_bready) begin
                        w_dm_bvalid <= 1'b0;
                        r_dm_state  <= DM_IDLE;
                    end
                end

                default: begin
                    r_dm_state <= DM_IDLE;
                end
            endcase
        end
    end

    assign w_dm_rdata = r_dm_rdata;

    assign w_xbar_m_awready[SLV_DM] = w_dm_awready;
    assign w_xbar_m_wready[SLV_DM]  = w_dm_wready;
    assign w_xbar_m_bresp[SLV_DM]   = w_dm_bresp;
    assign w_xbar_m_bvalid[SLV_DM]  = w_dm_bvalid;
    assign w_dm_bready              = w_xbar_m_bready[SLV_DM];
    assign w_xbar_m_arready[SLV_DM] = w_dm_arready;
    assign w_xbar_m_rdata[SLV_DM]   = w_dm_rdata;
    assign w_xbar_m_rresp[SLV_DM]   = w_dm_rresp;
    assign w_xbar_m_rvalid[SLV_DM]  = w_dm_rvalid;
    assign w_dm_rready              = w_xbar_m_rready[SLV_DM];

    k10_timer u_timer (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_debug_mode  (w_debug_mode),
        .s_axi_awaddr  (w_xbar_m_awaddr[SLV_TIMER]),
        .s_axi_awprot  (w_xbar_m_awprot[SLV_TIMER]),
        .s_axi_awvalid (w_xbar_m_awvalid[SLV_TIMER]),
        .s_axi_awready (w_xbar_m_awready[SLV_TIMER]),
        .s_axi_wdata   (w_xbar_m_wdata[SLV_TIMER]),
        .s_axi_wstrb   (w_xbar_m_wstrb[SLV_TIMER]),
        .s_axi_wvalid  (w_xbar_m_wvalid[SLV_TIMER]),
        .s_axi_wready  (w_xbar_m_wready[SLV_TIMER]),
        .s_axi_bresp   (w_xbar_m_bresp[SLV_TIMER]),
        .s_axi_bvalid  (w_xbar_m_bvalid[SLV_TIMER]),
        .s_axi_bready  (w_xbar_m_bready[SLV_TIMER]),
        .s_axi_araddr  (w_xbar_m_araddr[SLV_TIMER]),
        .s_axi_arprot  (w_xbar_m_arprot[SLV_TIMER]),
        .s_axi_arvalid (w_xbar_m_arvalid[SLV_TIMER]),
        .s_axi_arready (w_xbar_m_arready[SLV_TIMER]),
        .s_axi_rdata   (w_xbar_m_rdata[SLV_TIMER]),
        .s_axi_rresp   (w_xbar_m_rresp[SLV_TIMER]),
        .s_axi_rvalid  (w_xbar_m_rvalid[SLV_TIMER]),
        .s_axi_rready  (w_xbar_m_rready[SLV_TIMER]),
        .o_timer_irq   (o_timer_irq),
        .o_mtime       (o_mtime)
    );

    k10_sim_ctrl u_sim_ctrl (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .s_axi_awaddr  (w_xbar_m_awaddr[SLV_SIM_CTRL]),
        .s_axi_awprot  (w_xbar_m_awprot[SLV_SIM_CTRL]),
        .s_axi_awvalid (w_xbar_m_awvalid[SLV_SIM_CTRL]),
        .s_axi_awready (w_xbar_m_awready[SLV_SIM_CTRL]),
        .s_axi_wdata   (w_xbar_m_wdata[SLV_SIM_CTRL]),
        .s_axi_wstrb   (w_xbar_m_wstrb[SLV_SIM_CTRL]),
        .s_axi_wvalid  (w_xbar_m_wvalid[SLV_SIM_CTRL]),
        .s_axi_wready  (w_xbar_m_wready[SLV_SIM_CTRL]),
        .s_axi_bresp   (w_xbar_m_bresp[SLV_SIM_CTRL]),
        .s_axi_bvalid  (w_xbar_m_bvalid[SLV_SIM_CTRL]),
        .s_axi_bready  (w_xbar_m_bready[SLV_SIM_CTRL]),
        .s_axi_araddr  (w_xbar_m_araddr[SLV_SIM_CTRL]),
        .s_axi_arprot  (w_xbar_m_arprot[SLV_SIM_CTRL]),
        .s_axi_arvalid (w_xbar_m_arvalid[SLV_SIM_CTRL]),
        .s_axi_arready (w_xbar_m_arready[SLV_SIM_CTRL]),
        .s_axi_rdata   (w_xbar_m_rdata[SLV_SIM_CTRL]),
        .s_axi_rresp   (w_xbar_m_rresp[SLV_SIM_CTRL]),
        .s_axi_rvalid  (w_xbar_m_rvalid[SLV_SIM_CTRL]),
        .s_axi_rready  (w_xbar_m_rready[SLV_SIM_CTRL]),
        .o_sw_irq      (o_sw_irq)
    );

    k10_uart #(
        .CLK_FREQ_HZ (50_000_000),
        .BAUD_DEFAULT(115200)
    ) u_uart (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .s_axi_awaddr  (w_xbar_m_awaddr[SLV_UART]),
        .s_axi_awprot  (w_xbar_m_awprot[SLV_UART]),
        .s_axi_awvalid (w_xbar_m_awvalid[SLV_UART]),
        .s_axi_awready (w_xbar_m_awready[SLV_UART]),
        .s_axi_wdata   (w_xbar_m_wdata[SLV_UART]),
        .s_axi_wstrb   (w_xbar_m_wstrb[SLV_UART]),
        .s_axi_wvalid  (w_xbar_m_wvalid[SLV_UART]),
        .s_axi_wready  (w_xbar_m_wready[SLV_UART]),
        .s_axi_bresp   (w_xbar_m_bresp[SLV_UART]),
        .s_axi_bvalid  (w_xbar_m_bvalid[SLV_UART]),
        .s_axi_bready  (w_xbar_m_bready[SLV_UART]),
        .s_axi_araddr  (w_xbar_m_araddr[SLV_UART]),
        .s_axi_arprot  (w_xbar_m_arprot[SLV_UART]),
        .s_axi_arvalid (w_xbar_m_arvalid[SLV_UART]),
        .s_axi_arready (w_xbar_m_arready[SLV_UART]),
        .s_axi_rdata   (w_xbar_m_rdata[SLV_UART]),
        .s_axi_rresp   (w_xbar_m_rresp[SLV_UART]),
        .s_axi_rvalid  (w_xbar_m_rvalid[SLV_UART]),
        .s_axi_rready  (w_xbar_m_rready[SLV_UART]),
        .i_uart_rx     (i_uart_rx),
        .o_uart_tx     (o_uart_tx),
        .o_irq         (o_uart_irq)
    );

    dm_top #(
        .NrHarts    (1),
        .IdcodeValue(32'h2495_11C3),
        .BusWidth   (32)
    ) u_dm_top (
        .clk_i          (i_clk),
        .rst_ni         (i_rst_n),
        .testmode_i     (1'b0),
        .ndmreset_o     (w_dm_ndmreset),
        .dmactive_o     (w_dmactive),
        .debug_req_o    (w_dm_debug_req),
        .unavailable_i  (1'b0),
        .device_req_i   (w_dm_req),
        .device_we_i    (w_dm_we),
        .device_addr_i  (w_dm_addr),
        .device_be_i    (w_dm_be),
        .device_wdata_i (w_dm_wdata),
        .device_rdata_o (w_dm_device_rdata),
        .host_req_o     (w_dm_host_req),
        .host_add_o     (w_dm_host_addr),
        .host_we_o      (w_dm_host_we),
        .host_wdata_o   (w_dm_host_wdata),
        .host_be_o      (w_dm_host_be),
        .host_gnt_i     (w_dm_host_gnt),
        .host_r_valid_i (w_dm_host_rvalid),
        .host_r_rdata_i (w_dm_host_rdata),
        .tck_i          (i_jtag_tck),
        .tms_i          (i_jtag_tms),
        .trst_ni        (i_jtag_trst_n),
        .td_i           (i_jtag_tdi),
        .td_o           (o_jtag_tdo)
    );

    logic [2:0] w_dm_unused;
    assign w_dm_unused = {w_dm_host_err, w_dmactive, w_dm_ndmreset};

endmodule : k10_soc
