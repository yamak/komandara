// Copyright 2025 The Komandara Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

module k10_top
  import komandara_k10_pkg::*;
#(
    parameter logic [31:0] BOOT_ADDR   = 32'h8000_0000,
    parameter int unsigned PMP_REGIONS = 16,
    parameter logic [31:0] MHARTID     = 32'd0
)(
    input  logic        i_clk,
    input  logic        i_rst_n,

    input  logic        i_ext_irq,
    input  logic        i_timer_irq,
    input  logic        i_sw_irq,
    input  logic [14:0] i_irq_fast,

    input  logic        i_debug_req,
    input  logic [63:0] i_mtime,

    output logic        o_ibus_req,
    output logic [31:0] o_ibus_addr,
    input  logic        i_ibus_gnt,
    input  logic        i_ibus_rvalid,
    input  logic [31:0] i_ibus_rdata,
    input  logic        i_ibus_err,

    output logic        o_dbus_req,
    output logic        o_dbus_we,
    output logic [31:0] o_dbus_addr,
    output logic [31:0] o_dbus_wdata,
    output logic [3:0]  o_dbus_wstrb,
    input  logic        i_dbus_gnt,
    input  logic        i_dbus_rvalid,
    input  logic [31:0] i_dbus_rdata,
    input  logic        i_dbus_err
);

    k10_core #(
        .BOOT_ADDR   (BOOT_ADDR),
        .PMP_REGIONS (PMP_REGIONS),
        .MHARTID     (MHARTID)
    ) u_core (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .o_ibus_req    (o_ibus_req),
        .o_ibus_addr   (o_ibus_addr),
        .i_ibus_gnt    (i_ibus_gnt),
        .i_ibus_rvalid (i_ibus_rvalid),
        .i_ibus_rdata  (i_ibus_rdata),
        .i_ibus_err    (i_ibus_err),
        .o_dbus_req    (o_dbus_req),
        .o_dbus_we     (o_dbus_we),
        .o_dbus_addr   (o_dbus_addr),
        .o_dbus_wdata  (o_dbus_wdata),
        .o_dbus_wstrb  (o_dbus_wstrb),
        .i_dbus_gnt    (i_dbus_gnt),
        .i_dbus_rvalid (i_dbus_rvalid),
        .i_dbus_rdata  (i_dbus_rdata),
        .i_dbus_err    (i_dbus_err),
        .i_ext_irq     (i_ext_irq),
        .i_timer_irq   (i_timer_irq),
        .i_sw_irq      (i_sw_irq),
        .i_irq_fast    (i_irq_fast),
        .i_debug_req   (i_debug_req),
        .i_mtime       (i_mtime)
    );

endmodule : k10_top
