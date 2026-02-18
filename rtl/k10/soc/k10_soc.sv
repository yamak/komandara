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
    input  logic        i_uart_rx,
    output logic        o_uart_tx,
    output logic        o_timer_irq,
    output logic        o_sw_irq,
    output logic        o_uart_irq,
    output logic [63:0] o_mtime
);

    localparam int MEM_WORDS      = (MEM_SIZE_KB * 1024) / 4;
    localparam int MEM_ADDR_WIDTH = $clog2(MEM_WORDS);
    localparam int N_MASTERS      = 2;
    localparam int N_SLAVES       = 2;

    logic        w_ibus_req, w_ibus_gnt, w_ibus_rvalid, w_ibus_err;
    logic [31:0] w_ibus_addr, w_ibus_rdata;
    logic        w_dbus_req, w_dbus_we, w_dbus_gnt, w_dbus_rvalid, w_dbus_err;
    logic [31:0] w_dbus_addr, w_dbus_wdata, w_dbus_rdata;
    logic [3:0]  w_dbus_wstrb;

    logic [31:0] w_m0_awaddr, w_m0_wdata, w_m0_araddr, w_m0_rdata;
    logic [2:0]  w_m0_awprot, w_m0_arprot;
    logic [3:0]  w_m0_wstrb;
    logic [1:0]  w_m0_bresp, w_m0_rresp;
    logic        w_m0_awvalid, w_m0_awready;
    logic        w_m0_wvalid, w_m0_wready;
    logic        w_m0_bvalid, w_m0_bready;
    logic        w_m0_arvalid, w_m0_arready;
    logic        w_m0_rvalid, w_m0_rready;

    logic [31:0] w_m1_awaddr, w_m1_wdata, w_m1_araddr, w_m1_rdata;
    logic [2:0]  w_m1_awprot, w_m1_arprot;
    logic [3:0]  w_m1_wstrb;
    logic [1:0]  w_m1_bresp, w_m1_rresp;
    logic        w_m1_awvalid, w_m1_awready;
    logic        w_m1_wvalid, w_m1_wready;
    logic        w_m1_bvalid, w_m1_bready;
    logic        w_m1_arvalid, w_m1_arready;
    logic        w_m1_rvalid, w_m1_rready;

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

    logic [31:0] w_peri_awaddr, w_peri_wdata, w_peri_araddr, w_peri_rdata;
    logic [2:0]  w_peri_awprot, w_peri_arprot;
    logic [3:0]  w_peri_wstrb;
    logic [1:0]  w_peri_bresp, w_peri_rresp;
    logic        w_peri_awvalid, w_peri_awready;
    logic        w_peri_wvalid, w_peri_wready;
    logic        w_peri_bvalid, w_peri_bready;
    logic        w_peri_arvalid, w_peri_arready;
    logic        w_peri_rvalid, w_peri_rready;

    logic [1:0] w_aw_sel;
    logic [1:0] w_ar_sel;
    logic [1:0] r_wr_sel;
    logic [1:0] r_rd_sel;

    logic [31:0] w_tmr_awaddr, w_tmr_wdata, w_tmr_araddr, w_tmr_rdata;
    logic [2:0]  w_tmr_awprot, w_tmr_arprot;
    logic [3:0]  w_tmr_wstrb;
    logic [1:0]  w_tmr_bresp, w_tmr_rresp;
    logic        w_tmr_awvalid, w_tmr_awready;
    logic        w_tmr_wvalid, w_tmr_wready;
    logic        w_tmr_bvalid, w_tmr_bready;
    logic        w_tmr_arvalid, w_tmr_arready;
    logic        w_tmr_rvalid, w_tmr_rready;

    logic [31:0] w_sim_awaddr, w_sim_wdata, w_sim_araddr, w_sim_rdata;
    logic [2:0]  w_sim_awprot, w_sim_arprot;
    logic [3:0]  w_sim_wstrb;
    logic [1:0]  w_sim_bresp, w_sim_rresp;
    logic        w_sim_awvalid, w_sim_awready;
    logic        w_sim_wvalid, w_sim_wready;
    logic        w_sim_bvalid, w_sim_bready;
    logic        w_sim_arvalid, w_sim_arready;
    logic        w_sim_rvalid, w_sim_rready;

    logic [31:0] w_uart_awaddr, w_uart_wdata, w_uart_araddr, w_uart_rdata;
    logic [2:0]  w_uart_awprot, w_uart_arprot;
    logic [3:0]  w_uart_wstrb;
    logic [1:0]  w_uart_bresp, w_uart_rresp;
    logic        w_uart_awvalid, w_uart_awready;
    logic        w_uart_wvalid, w_uart_wready;
    logic        w_uart_bvalid, w_uart_bready;
    logic        w_uart_arvalid, w_uart_arready;
    logic        w_uart_rvalid, w_uart_rready;

    k10_top #(
        .BOOT_ADDR (BOOT_ADDR)
    ) u_top (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_ext_irq     (i_ext_irq || o_uart_irq),
        .i_timer_irq   (o_timer_irq),
        .i_sw_irq      (o_sw_irq),
        .i_irq_fast    (i_irq_fast),
        .i_debug_req   (i_debug_req),
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

    komandara_axi4lite_xbar #(
        .N_MASTERS       (N_MASTERS),
        .N_SLAVES        (N_SLAVES),
        .ADDR_WIDTH      (32),
        .DATA_WIDTH      (32),
        .ROUND_ROBIN     (1'b0),
        .SLAVE_ADDR_BASE ({PERI_BASE, MEM_BASE}),
        .SLAVE_ADDR_MASK ({PERI_MASK, MEM_MASK})
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

    assign w_peri_awaddr       = w_xbar_m_awaddr[1];
    assign w_peri_awprot       = w_xbar_m_awprot[1];
    assign w_peri_awvalid      = w_xbar_m_awvalid[1];
    assign w_xbar_m_awready[1] = w_peri_awready;
    assign w_peri_wdata        = w_xbar_m_wdata[1];
    assign w_peri_wstrb        = w_xbar_m_wstrb[1];
    assign w_peri_wvalid       = w_xbar_m_wvalid[1];
    assign w_xbar_m_wready[1]  = w_peri_wready;
    assign w_xbar_m_bresp[1]   = w_peri_bresp;
    assign w_xbar_m_bvalid[1]  = w_peri_bvalid;
    assign w_peri_bready       = w_xbar_m_bready[1];
    assign w_peri_araddr       = w_xbar_m_araddr[1];
    assign w_peri_arprot       = w_xbar_m_arprot[1];
    assign w_peri_arvalid      = w_xbar_m_arvalid[1];
    assign w_xbar_m_arready[1] = w_peri_arready;
    assign w_xbar_m_rdata[1]   = w_peri_rdata;
    assign w_xbar_m_rresp[1]   = w_peri_rresp;
    assign w_xbar_m_rvalid[1]  = w_peri_rvalid;
    assign w_peri_rready       = w_xbar_m_rready[1];

    assign w_aw_sel = w_peri_awaddr[13:12];
    assign w_ar_sel = w_peri_araddr[13:12];

    assign w_tmr_awaddr  = w_peri_awaddr;
    assign w_tmr_awprot  = w_peri_awprot;
    assign w_tmr_awvalid = w_peri_awvalid && (w_aw_sel == 2'b00);
    assign w_tmr_wdata   = w_peri_wdata;
    assign w_tmr_wstrb   = w_peri_wstrb;
    assign w_tmr_wvalid  = w_peri_wvalid && (w_aw_sel == 2'b00);
    assign w_sim_awaddr  = w_peri_awaddr;
    assign w_sim_awprot  = w_peri_awprot;
    assign w_sim_awvalid = w_peri_awvalid && (w_aw_sel == 2'b01);
    assign w_sim_wdata   = w_peri_wdata;
    assign w_sim_wstrb   = w_peri_wstrb;
    assign w_sim_wvalid  = w_peri_wvalid && (w_aw_sel == 2'b01);
    assign w_uart_awaddr  = w_peri_awaddr;
    assign w_uart_awprot  = w_peri_awprot;
    assign w_uart_awvalid = w_peri_awvalid && (w_aw_sel == 2'b10);
    assign w_uart_wdata   = w_peri_wdata;
    assign w_uart_wstrb   = w_peri_wstrb;
    assign w_uart_wvalid  = w_peri_wvalid && (w_aw_sel == 2'b10);

    always_comb begin
        unique case (w_aw_sel)
            2'b00: begin
                w_peri_awready = w_tmr_awready;
                w_peri_wready  = w_tmr_wready;
            end
            2'b01: begin
                w_peri_awready = w_sim_awready;
                w_peri_wready  = w_sim_wready;
            end
            2'b10: begin
                w_peri_awready = w_uart_awready;
                w_peri_wready  = w_uart_wready;
            end
            default: begin
                w_peri_awready = 1'b1;
                w_peri_wready  = 1'b1;
            end
        endcase
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) r_wr_sel <= 2'b00;
        else if (w_peri_awvalid && w_peri_awready) r_wr_sel <= w_aw_sel;
    end

    assign w_tmr_bready = w_peri_bready && (r_wr_sel == 2'b00);
    assign w_sim_bready = w_peri_bready && (r_wr_sel == 2'b01);
    assign w_uart_bready = w_peri_bready && (r_wr_sel == 2'b10);

    always_comb begin
        unique case (r_wr_sel)
            2'b00: begin
                w_peri_bvalid = w_tmr_bvalid;
                w_peri_bresp  = w_tmr_bresp;
            end
            2'b01: begin
                w_peri_bvalid = w_sim_bvalid;
                w_peri_bresp  = w_sim_bresp;
            end
            2'b10: begin
                w_peri_bvalid = w_uart_bvalid;
                w_peri_bresp  = w_uart_bresp;
            end
            default: begin
                w_peri_bvalid = 1'b1;
                w_peri_bresp  = 2'b11;
            end
        endcase
    end

    assign w_tmr_araddr  = w_peri_araddr;
    assign w_tmr_arprot  = w_peri_arprot;
    assign w_tmr_arvalid = w_peri_arvalid && (w_ar_sel == 2'b00);
    assign w_sim_araddr  = w_peri_araddr;
    assign w_sim_arprot  = w_peri_arprot;
    assign w_sim_arvalid = w_peri_arvalid && (w_ar_sel == 2'b01);
    assign w_uart_araddr  = w_peri_araddr;
    assign w_uart_arprot  = w_peri_arprot;
    assign w_uart_arvalid = w_peri_arvalid && (w_ar_sel == 2'b10);

    always_comb begin
        unique case (w_ar_sel)
            2'b00: w_peri_arready = w_tmr_arready;
            2'b01: w_peri_arready = w_sim_arready;
            2'b10: w_peri_arready = w_uart_arready;
            default: w_peri_arready = 1'b1;
        endcase
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) r_rd_sel <= 2'b00;
        else if (w_peri_arvalid && w_peri_arready) r_rd_sel <= w_ar_sel;
    end

    assign w_tmr_rready  = w_peri_rready && (r_rd_sel == 2'b00);
    assign w_sim_rready  = w_peri_rready && (r_rd_sel == 2'b01);
    assign w_uart_rready = w_peri_rready && (r_rd_sel == 2'b10);

    always_comb begin
        unique case (r_rd_sel)
            2'b00: begin
                w_peri_rvalid = w_tmr_rvalid;
                w_peri_rdata  = w_tmr_rdata;
                w_peri_rresp  = w_tmr_rresp;
            end
            2'b01: begin
                w_peri_rvalid = w_sim_rvalid;
                w_peri_rdata  = w_sim_rdata;
                w_peri_rresp  = w_sim_rresp;
            end
            2'b10: begin
                w_peri_rvalid = w_uart_rvalid;
                w_peri_rdata  = w_uart_rdata;
                w_peri_rresp  = w_uart_rresp;
            end
            default: begin
                w_peri_rvalid = 1'b1;
                w_peri_rdata  = 32'd0;
                w_peri_rresp  = 2'b11;
            end
        endcase
    end

    k10_timer u_timer (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .s_axi_awaddr  (w_tmr_awaddr),
        .s_axi_awprot  (w_tmr_awprot),
        .s_axi_awvalid (w_tmr_awvalid),
        .s_axi_awready (w_tmr_awready),
        .s_axi_wdata   (w_tmr_wdata),
        .s_axi_wstrb   (w_tmr_wstrb),
        .s_axi_wvalid  (w_tmr_wvalid),
        .s_axi_wready  (w_tmr_wready),
        .s_axi_bresp   (w_tmr_bresp),
        .s_axi_bvalid  (w_tmr_bvalid),
        .s_axi_bready  (w_tmr_bready),
        .s_axi_araddr  (w_tmr_araddr),
        .s_axi_arprot  (w_tmr_arprot),
        .s_axi_arvalid (w_tmr_arvalid),
        .s_axi_arready (w_tmr_arready),
        .s_axi_rdata   (w_tmr_rdata),
        .s_axi_rresp   (w_tmr_rresp),
        .s_axi_rvalid  (w_tmr_rvalid),
        .s_axi_rready  (w_tmr_rready),
        .o_timer_irq   (o_timer_irq),
        .o_mtime       (o_mtime)
    );

    k10_sim_ctrl u_sim_ctrl (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .s_axi_awaddr  (w_sim_awaddr),
        .s_axi_awprot  (w_sim_awprot),
        .s_axi_awvalid (w_sim_awvalid),
        .s_axi_awready (w_sim_awready),
        .s_axi_wdata   (w_sim_wdata),
        .s_axi_wstrb   (w_sim_wstrb),
        .s_axi_wvalid  (w_sim_wvalid),
        .s_axi_wready  (w_sim_wready),
        .s_axi_bresp   (w_sim_bresp),
        .s_axi_bvalid  (w_sim_bvalid),
        .s_axi_bready  (w_sim_bready),
        .s_axi_araddr  (w_sim_araddr),
        .s_axi_arprot  (w_sim_arprot),
        .s_axi_arvalid (w_sim_arvalid),
        .s_axi_arready (w_sim_arready),
        .s_axi_rdata   (w_sim_rdata),
        .s_axi_rresp   (w_sim_rresp),
        .s_axi_rvalid  (w_sim_rvalid),
        .s_axi_rready  (w_sim_rready),
        .o_sw_irq      (o_sw_irq)
    );

    k10_uart #(
        .CLK_FREQ_HZ (50_000_000),
        .BAUD_DEFAULT(115200)
    ) u_uart (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .s_axi_awaddr  (w_uart_awaddr),
        .s_axi_awprot  (w_uart_awprot),
        .s_axi_awvalid (w_uart_awvalid),
        .s_axi_awready (w_uart_awready),
        .s_axi_wdata   (w_uart_wdata),
        .s_axi_wstrb   (w_uart_wstrb),
        .s_axi_wvalid  (w_uart_wvalid),
        .s_axi_wready  (w_uart_wready),
        .s_axi_bresp   (w_uart_bresp),
        .s_axi_bvalid  (w_uart_bvalid),
        .s_axi_bready  (w_uart_bready),
        .s_axi_araddr  (w_uart_araddr),
        .s_axi_arprot  (w_uart_arprot),
        .s_axi_arvalid (w_uart_arvalid),
        .s_axi_arready (w_uart_arready),
        .s_axi_rdata   (w_uart_rdata),
        .s_axi_rresp   (w_uart_rresp),
        .s_axi_rvalid  (w_uart_rvalid),
        .s_axi_rready  (w_uart_rready),
        .i_uart_rx     (i_uart_rx),
        .o_uart_tx     (o_uart_tx),
        .o_irq         (o_uart_irq)
    );

endmodule : k10_soc
