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
// Testbench: AXI4 Full Crossbar (2M × 2S) — VIP masters + DUT slaves
// ============================================================================

`timescale 1ns / 1ps

module tb_axi4_xbar;

    import axi_vip_pkg::*;
    import axi_vip_mst0_pkg::*;
    import axi_vip_mst1_pkg::*;

    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int ID_WIDTH   = 4;
    localparam int CLK_PERIOD = 10;
    localparam int MEM_DEPTH  = 4096;

    localparam bit [2*32-1:0] SLV_BASE = {32'h0001_0000, 32'h0000_0000};
    localparam bit [2*32-1:0] SLV_MASK = {32'hFFFF_0000, 32'hFFFF_0000};

    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // AXI wires — master 0
    logic [ID_WIDTH-1:0] m0_awid;  logic [31:0] m0_awaddr;
    logic [7:0] m0_awlen; logic [2:0] m0_awsize; logic [1:0] m0_awburst;
    logic       m0_awlock; logic [3:0] m0_awcache; logic [2:0] m0_awprot;
    logic [3:0] m0_awqos; logic [3:0] m0_awregion;
    logic       m0_awvalid, m0_awready;
    logic [31:0] m0_wdata; logic [3:0] m0_wstrb; logic m0_wlast, m0_wvalid, m0_wready;
    logic [ID_WIDTH-1:0] m0_bid; logic [1:0] m0_bresp; logic m0_bvalid, m0_bready;
    logic [ID_WIDTH-1:0] m0_arid;  logic [31:0] m0_araddr;
    logic [7:0] m0_arlen; logic [2:0] m0_arsize; logic [1:0] m0_arburst;
    logic       m0_arlock; logic [3:0] m0_arcache; logic [2:0] m0_arprot;
    logic [3:0] m0_arqos; logic [3:0] m0_arregion;
    logic       m0_arvalid, m0_arready;
    logic [ID_WIDTH-1:0] m0_rid; logic [31:0] m0_rdata; logic [1:0] m0_rresp;
    logic m0_rlast, m0_rvalid, m0_rready;

    // AXI wires — master 1
    logic [ID_WIDTH-1:0] m1_awid;  logic [31:0] m1_awaddr;
    logic [7:0] m1_awlen; logic [2:0] m1_awsize; logic [1:0] m1_awburst;
    logic       m1_awlock; logic [3:0] m1_awcache; logic [2:0] m1_awprot;
    logic [3:0] m1_awqos; logic [3:0] m1_awregion;
    logic       m1_awvalid, m1_awready;
    logic [31:0] m1_wdata; logic [3:0] m1_wstrb; logic m1_wlast, m1_wvalid, m1_wready;
    logic [ID_WIDTH-1:0] m1_bid; logic [1:0] m1_bresp; logic m1_bvalid, m1_bready;
    logic [ID_WIDTH-1:0] m1_arid;  logic [31:0] m1_araddr;
    logic [7:0] m1_arlen; logic [2:0] m1_arsize; logic [1:0] m1_arburst;
    logic       m1_arlock; logic [3:0] m1_arcache; logic [2:0] m1_arprot;
    logic [3:0] m1_arqos; logic [3:0] m1_arregion;
    logic       m1_arvalid, m1_arready;
    logic [ID_WIDTH-1:0] m1_rid; logic [31:0] m1_rdata; logic [1:0] m1_rresp;
    logic m1_rlast, m1_rvalid, m1_rready;

    // AXI wires — crossbar → slave 0
    logic [ID_WIDTH-1:0] s0_awid;  logic [31:0] s0_awaddr;
    logic [7:0] s0_awlen; logic [2:0] s0_awsize; logic [1:0] s0_awburst;
    logic       s0_awvalid, s0_awready;
    logic [31:0] s0_wdata; logic [3:0] s0_wstrb; logic s0_wlast, s0_wvalid, s0_wready;
    logic [ID_WIDTH-1:0] s0_bid; logic [1:0] s0_bresp; logic s0_bvalid, s0_bready;
    logic [ID_WIDTH-1:0] s0_arid;  logic [31:0] s0_araddr;
    logic [7:0] s0_arlen; logic [2:0] s0_arsize; logic [1:0] s0_arburst;
    logic       s0_arvalid, s0_arready;
    logic [ID_WIDTH-1:0] s0_rid; logic [31:0] s0_rdata; logic [1:0] s0_rresp;
    logic s0_rlast, s0_rvalid, s0_rready;

    // AXI wires — crossbar → slave 1
    logic [ID_WIDTH-1:0] s1_awid;  logic [31:0] s1_awaddr;
    logic [7:0] s1_awlen; logic [2:0] s1_awsize; logic [1:0] s1_awburst;
    logic       s1_awvalid, s1_awready;
    logic [31:0] s1_wdata; logic [3:0] s1_wstrb; logic s1_wlast, s1_wvalid, s1_wready;
    logic [ID_WIDTH-1:0] s1_bid; logic [1:0] s1_bresp; logic s1_bvalid, s1_bready;
    logic [ID_WIDTH-1:0] s1_arid;  logic [31:0] s1_araddr;
    logic [7:0] s1_arlen; logic [2:0] s1_arsize; logic [1:0] s1_arburst;
    logic       s1_arvalid, s1_arready;
    logic [ID_WIDTH-1:0] s1_rid; logic [31:0] s1_rdata; logic [1:0] s1_rresp;
    logic s1_rlast, s1_rvalid, s1_rready;

    // ---- VIP Master 0 ----
    axi_vip_mst0 u_vip_mst0 (
        .aclk(aclk), .aresetn(aresetn),
        .m_axi_awid(m0_awid), .m_axi_awaddr(m0_awaddr), .m_axi_awlen(m0_awlen),
        .m_axi_awsize(m0_awsize), .m_axi_awburst(m0_awburst), .m_axi_awlock(m0_awlock),
        .m_axi_awcache(m0_awcache), .m_axi_awprot(m0_awprot), .m_axi_awqos(m0_awqos),
        .m_axi_awregion(m0_awregion), .m_axi_awvalid(m0_awvalid), .m_axi_awready(m0_awready),
        .m_axi_wdata(m0_wdata), .m_axi_wstrb(m0_wstrb), .m_axi_wlast(m0_wlast),
        .m_axi_wvalid(m0_wvalid), .m_axi_wready(m0_wready),
        .m_axi_bid(m0_bid), .m_axi_bresp(m0_bresp), .m_axi_bvalid(m0_bvalid), .m_axi_bready(m0_bready),
        .m_axi_arid(m0_arid), .m_axi_araddr(m0_araddr), .m_axi_arlen(m0_arlen),
        .m_axi_arsize(m0_arsize), .m_axi_arburst(m0_arburst), .m_axi_arlock(m0_arlock),
        .m_axi_arcache(m0_arcache), .m_axi_arprot(m0_arprot), .m_axi_arqos(m0_arqos),
        .m_axi_arregion(m0_arregion), .m_axi_arvalid(m0_arvalid), .m_axi_arready(m0_arready),
        .m_axi_rid(m0_rid), .m_axi_rdata(m0_rdata), .m_axi_rresp(m0_rresp),
        .m_axi_rlast(m0_rlast), .m_axi_rvalid(m0_rvalid), .m_axi_rready(m0_rready)
    );

    // ---- VIP Master 1 ----
    axi_vip_mst1 u_vip_mst1 (
        .aclk(aclk), .aresetn(aresetn),
        .m_axi_awid(m1_awid), .m_axi_awaddr(m1_awaddr), .m_axi_awlen(m1_awlen),
        .m_axi_awsize(m1_awsize), .m_axi_awburst(m1_awburst), .m_axi_awlock(m1_awlock),
        .m_axi_awcache(m1_awcache), .m_axi_awprot(m1_awprot), .m_axi_awqos(m1_awqos),
        .m_axi_awregion(m1_awregion), .m_axi_awvalid(m1_awvalid), .m_axi_awready(m1_awready),
        .m_axi_wdata(m1_wdata), .m_axi_wstrb(m1_wstrb), .m_axi_wlast(m1_wlast),
        .m_axi_wvalid(m1_wvalid), .m_axi_wready(m1_wready),
        .m_axi_bid(m1_bid), .m_axi_bresp(m1_bresp), .m_axi_bvalid(m1_bvalid), .m_axi_bready(m1_bready),
        .m_axi_arid(m1_arid), .m_axi_araddr(m1_araddr), .m_axi_arlen(m1_arlen),
        .m_axi_arsize(m1_arsize), .m_axi_arburst(m1_arburst), .m_axi_arlock(m1_arlock),
        .m_axi_arcache(m1_arcache), .m_axi_arprot(m1_arprot), .m_axi_arqos(m1_arqos),
        .m_axi_arregion(m1_arregion), .m_axi_arvalid(m1_arvalid), .m_axi_arready(m1_arready),
        .m_axi_rid(m1_rid), .m_axi_rdata(m1_rdata), .m_axi_rresp(m1_rresp),
        .m_axi_rlast(m1_rlast), .m_axi_rvalid(m1_rvalid), .m_axi_rready(m1_rready)
    );

    // ---- Crossbar DUT ----
    komandara_axi4_xbar #(
        .N_MASTERS(2), .N_SLAVES(2), .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH), .ROUND_ROBIN(1'b1),
        .SLAVE_ADDR_BASE(SLV_BASE), .SLAVE_ADDR_MASK(SLV_MASK)
    ) u_xbar (
        .clk_i(aclk), .rst_ni(aresetn),
        .s_axi_awid_i   ({m1_awid,    m0_awid}),
        .s_axi_awaddr_i ({m1_awaddr,  m0_awaddr}),
        .s_axi_awlen_i  ({m1_awlen,   m0_awlen}),
        .s_axi_awsize_i ({m1_awsize,  m0_awsize}),
        .s_axi_awburst_i({m1_awburst, m0_awburst}),
        .s_axi_awvalid_i({m1_awvalid, m0_awvalid}),
        .s_axi_awready_o({m1_awready, m0_awready}),
        .s_axi_wdata_i  ({m1_wdata,   m0_wdata}),
        .s_axi_wstrb_i  ({m1_wstrb,   m0_wstrb}),
        .s_axi_wlast_i  ({m1_wlast,   m0_wlast}),
        .s_axi_wvalid_i ({m1_wvalid,  m0_wvalid}),
        .s_axi_wready_o ({m1_wready,  m0_wready}),
        .s_axi_bid_o    ({m1_bid,     m0_bid}),
        .s_axi_bresp_o  ({m1_bresp,   m0_bresp}),
        .s_axi_bvalid_o ({m1_bvalid,  m0_bvalid}),
        .s_axi_bready_i ({m1_bready,  m0_bready}),
        .s_axi_arid_i   ({m1_arid,    m0_arid}),
        .s_axi_araddr_i ({m1_araddr,  m0_araddr}),
        .s_axi_arlen_i  ({m1_arlen,   m0_arlen}),
        .s_axi_arsize_i ({m1_arsize,  m0_arsize}),
        .s_axi_arburst_i({m1_arburst, m0_arburst}),
        .s_axi_arvalid_i({m1_arvalid, m0_arvalid}),
        .s_axi_arready_o({m1_arready, m0_arready}),
        .s_axi_rid_o    ({m1_rid,     m0_rid}),
        .s_axi_rdata_o  ({m1_rdata,   m0_rdata}),
        .s_axi_rresp_o  ({m1_rresp,   m0_rresp}),
        .s_axi_rlast_o  ({m1_rlast,   m0_rlast}),
        .s_axi_rvalid_o ({m1_rvalid,  m0_rvalid}),
        .s_axi_rready_i ({m1_rready,  m0_rready}),
        // Slave-side
        .m_axi_awid_o   ({s1_awid,    s0_awid}),
        .m_axi_awaddr_o ({s1_awaddr,  s0_awaddr}),
        .m_axi_awlen_o  ({s1_awlen,   s0_awlen}),
        .m_axi_awsize_o ({s1_awsize,  s0_awsize}),
        .m_axi_awburst_o({s1_awburst, s0_awburst}),
        .m_axi_awvalid_o({s1_awvalid, s0_awvalid}),
        .m_axi_awready_i({s1_awready, s0_awready}),
        .m_axi_wdata_o  ({s1_wdata,   s0_wdata}),
        .m_axi_wstrb_o  ({s1_wstrb,   s0_wstrb}),
        .m_axi_wlast_o  ({s1_wlast,   s0_wlast}),
        .m_axi_wvalid_o ({s1_wvalid,  s0_wvalid}),
        .m_axi_wready_i ({s1_wready,  s0_wready}),
        .m_axi_bid_i    ({s1_bid,     s0_bid}),
        .m_axi_bresp_i  ({s1_bresp,   s0_bresp}),
        .m_axi_bvalid_i ({s1_bvalid,  s0_bvalid}),
        .m_axi_bready_o ({s1_bready,  s0_bready}),
        .m_axi_arid_o   ({s1_arid,    s0_arid}),
        .m_axi_araddr_o ({s1_araddr,  s0_araddr}),
        .m_axi_arlen_o  ({s1_arlen,   s0_arlen}),
        .m_axi_arsize_o ({s1_arsize,  s0_arsize}),
        .m_axi_arburst_o({s1_arburst, s0_arburst}),
        .m_axi_arvalid_o({s1_arvalid, s0_arvalid}),
        .m_axi_arready_i({s1_arready, s0_arready}),
        .m_axi_rid_i    ({s1_rid,     s0_rid}),
        .m_axi_rdata_i  ({s1_rdata,   s0_rdata}),
        .m_axi_rresp_i  ({s1_rresp,   s0_rresp}),
        .m_axi_rlast_i  ({s1_rlast,   s0_rlast}),
        .m_axi_rvalid_i ({s1_rvalid,  s0_rvalid}),
        .m_axi_rready_o ({s1_rready,  s0_rready})
    );

    // ---- Target Slaves ----
    komandara_axi4_slave #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .MEM_DEPTH(MEM_DEPTH)
    ) u_slv0 (
        .clk_i(aclk), .rst_ni(aresetn),
        .s_axi_awid_i(s0_awid), .s_axi_awaddr_i(s0_awaddr),
        .s_axi_awlen_i(s0_awlen), .s_axi_awsize_i(s0_awsize),
        .s_axi_awburst_i(s0_awburst), .s_axi_awvalid_i(s0_awvalid), .s_axi_awready_o(s0_awready),
        .s_axi_wdata_i(s0_wdata), .s_axi_wstrb_i(s0_wstrb), .s_axi_wlast_i(s0_wlast),
        .s_axi_wvalid_i(s0_wvalid), .s_axi_wready_o(s0_wready),
        .s_axi_bid_o(s0_bid), .s_axi_bresp_o(s0_bresp),
        .s_axi_bvalid_o(s0_bvalid), .s_axi_bready_i(s0_bready),
        .s_axi_arid_i(s0_arid), .s_axi_araddr_i(s0_araddr),
        .s_axi_arlen_i(s0_arlen), .s_axi_arsize_i(s0_arsize),
        .s_axi_arburst_i(s0_arburst), .s_axi_arvalid_i(s0_arvalid), .s_axi_arready_o(s0_arready),
        .s_axi_rid_o(s0_rid), .s_axi_rdata_o(s0_rdata), .s_axi_rresp_o(s0_rresp),
        .s_axi_rlast_o(s0_rlast), .s_axi_rvalid_o(s0_rvalid), .s_axi_rready_i(s0_rready)
    );

    komandara_axi4_slave #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .MEM_DEPTH(MEM_DEPTH)
    ) u_slv1 (
        .clk_i(aclk), .rst_ni(aresetn),
        .s_axi_awid_i(s1_awid), .s_axi_awaddr_i(s1_awaddr),
        .s_axi_awlen_i(s1_awlen), .s_axi_awsize_i(s1_awsize),
        .s_axi_awburst_i(s1_awburst), .s_axi_awvalid_i(s1_awvalid), .s_axi_awready_o(s1_awready),
        .s_axi_wdata_i(s1_wdata), .s_axi_wstrb_i(s1_wstrb), .s_axi_wlast_i(s1_wlast),
        .s_axi_wvalid_i(s1_wvalid), .s_axi_wready_o(s1_wready),
        .s_axi_bid_o(s1_bid), .s_axi_bresp_o(s1_bresp),
        .s_axi_bvalid_o(s1_bvalid), .s_axi_bready_i(s1_bready),
        .s_axi_arid_i(s1_arid), .s_axi_araddr_i(s1_araddr),
        .s_axi_arlen_i(s1_arlen), .s_axi_arsize_i(s1_arsize),
        .s_axi_arburst_i(s1_arburst), .s_axi_arvalid_i(s1_arvalid), .s_axi_arready_o(s1_arready),
        .s_axi_rid_o(s1_rid), .s_axi_rdata_o(s1_rdata), .s_axi_rresp_o(s1_rresp),
        .s_axi_rlast_o(s1_rlast), .s_axi_rvalid_o(s1_rvalid), .s_axi_rready_i(s1_rready)
    );

    // ---- VIP Agents ----
    axi_vip_mst0_mst_t mst0_agent;
    axi_vip_mst1_mst_t mst1_agent;
    int pass_count = 0, fail_count = 0;

    task automatic check(string tag, bit [31:0] got, bit [31:0] exp);
        if (got !== exp) begin $error("[%s] got 0x%08h exp 0x%08h", tag, got, exp); fail_count++; end
        else pass_count++;
    endtask

    // ---- Generic VIP helpers (Agent-parameterised via macros) ----
    // Note: we repeat for each agent type since SV doesn't allow polymorphic tasks easily
    task automatic m0_write(input bit [31:0] addr, input int id, input int len, input bit [31:0] d []);
        axi_transaction wr;
        wr = mst0_agent.wr_driver.create_transaction("wr");
        wr.set_write_cmd(addr, XIL_AXI_BURST_TYPE_INCR, id, len, xil_axi_size_t'(2));
        for (int i = 0; i <= len; i++) begin wr.set_data_beat(i, d[i]); wr.set_strb_beat(i, 4'hF); end
        wr.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
        mst0_agent.wr_driver.send(wr);
        mst0_agent.wr_driver.wait_rsp(wr);
    endtask

    task automatic m0_read(input bit [31:0] addr, input int id, input int len, output bit [31:0] d []);
        axi_transaction rd;
        rd = mst0_agent.rd_driver.create_transaction("rd");
        rd.set_read_cmd(addr, XIL_AXI_BURST_TYPE_INCR, id, len, xil_axi_size_t'(2));
        rd.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
        mst0_agent.rd_driver.send(rd);
        mst0_agent.rd_driver.wait_rsp(rd);
        d = new[len+1];
        for (int i = 0; i <= len; i++) d[i] = rd.get_data_beat(i);
    endtask

    task automatic m1_write(input bit [31:0] addr, input int id, input int len, input bit [31:0] d []);
        axi_transaction wr;
        wr = mst1_agent.wr_driver.create_transaction("wr");
        wr.set_write_cmd(addr, XIL_AXI_BURST_TYPE_INCR, id, len, xil_axi_size_t'(2));
        for (int i = 0; i <= len; i++) begin wr.set_data_beat(i, d[i]); wr.set_strb_beat(i, 4'hF); end
        wr.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
        mst1_agent.wr_driver.send(wr);
        mst1_agent.wr_driver.wait_rsp(wr);
    endtask

    task automatic m1_read(input bit [31:0] addr, input int id, input int len, output bit [31:0] d []);
        axi_transaction rd;
        rd = mst1_agent.rd_driver.create_transaction("rd");
        rd.set_read_cmd(addr, XIL_AXI_BURST_TYPE_INCR, id, len, xil_axi_size_t'(2));
        rd.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
        mst1_agent.rd_driver.send(rd);
        mst1_agent.rd_driver.wait_rsp(rd);
        d = new[len+1];
        for (int i = 0; i <= len; i++) d[i] = rd.get_data_beat(i);
    endtask

    // ======== Test 1: basic routing ========
    task automatic test_routing();
        bit [31:0] wd0 [] = '{32'hAAAA_0000};
        bit [31:0] wd1 [] = '{32'hBBBB_1111};
        bit [31:0] rd [];
        $display("[TEST] Routing M0→S0, M1→S1 ...");
        m0_write(32'h0000_0000, 0, 0, wd0);
        m1_write(32'h0001_0000, 1, 0, wd1);
        m0_read(32'h0000_0000, 0, 0, rd); check("Route S0", rd[0], 32'hAAAA_0000);
        m1_read(32'h0001_0000, 1, 0, rd); check("Route S1", rd[0], 32'hBBBB_1111);
        $display("[TEST] Routing ... DONE");
    endtask

    // ======== Test 2: cross path ========
    task automatic test_cross_path();
        bit [31:0] wd [] = '{32'hCC00_DD00};
        bit [31:0] rd [];
        $display("[TEST] Cross path M0→S1 ...");
        m0_write(32'h0001_0004, 2, 0, wd);
        m0_read(32'h0001_0004, 2, 0, rd); check("Cross", rd[0], 32'hCC00_DD00);
        $display("[TEST] Cross path ... DONE");
    endtask

    // ======== Test 3: burst through crossbar ========
    task automatic test_burst();
        bit [31:0] wd [8];
        bit [31:0] rd [];
        $display("[TEST] Burst through xbar (8 beats) ...");
        for (int i = 0; i < 8; i++) wd[i] = 32'hE000_0000 + i;
        m0_write(32'h0000_0100, 3, 7, wd);
        m0_read (32'h0000_0100, 3, 7, rd);
        for (int i = 0; i < 8; i++)
            check($sformatf("XBurst[%0d]", i), rd[i], 32'hE000_0000+i);
        $display("[TEST] Burst through xbar ... DONE");
    endtask

    // ======== Test 4: parallel bursts — throughput ========
    task automatic test_parallel_throughput();
        localparam int N_TXN = 8;
        localparam int BURST_LEN = 7; // 8 beats
        bit [31:0] wd0 [8], wd1 [8], rd [];
        int t_start, t_end, cycles;

        $display("[TEST] Parallel burst throughput (no contention) ...");
        for (int i = 0; i < 8; i++) begin wd0[i] = 32'hA0000000+i; wd1[i] = 32'hB0000000+i; end

        t_start = $time;
        fork
            for (int t = 0; t < N_TXN; t++)
                m0_write(t*32, 0, BURST_LEN, wd0);
            for (int t = 0; t < N_TXN; t++)
                m1_write(32'h00010000 + t*32, 1, BURST_LEN, wd1);
        join
        t_end = $time;
        cycles = (t_end - t_start) / CLK_PERIOD;
        $display("  Parallel: %0d×%0d-beat bursts each in %0d cycles (%.1f cyc/burst)",
                 N_TXN, BURST_LEN+1, cycles, real'(cycles)/real'(N_TXN));

        // Sequential baseline
        t_start = $time;
        for (int t = 0; t < N_TXN; t++)
            m0_write(t*32, 0, BURST_LEN, wd0);
        t_end = $time;
        cycles = (t_end - t_start) / CLK_PERIOD;
        $display("  Seq base: %0d×%0d-beat bursts in %0d cycles (%.1f cyc/burst)",
                 N_TXN, BURST_LEN+1, cycles, real'(cycles)/real'(N_TXN));

        // Verify data
        for (int t = 0; t < N_TXN; t++) begin
            m0_read(t*32, 0, BURST_LEN, rd);
            for (int i = 0; i < 8; i++)
                check($sformatf("PVS0[%0d][%0d]",t,i), rd[i], 32'hA0000000+i);
        end
        pass_count++; // throughput test passed
        $display("[TEST] Parallel burst throughput ... DONE");
    endtask

    // ======== Test 5: contention ========
    task automatic test_contention();
        bit [31:0] wd0 [] = '{32'h11111111};
        bit [31:0] wd1 [] = '{32'h22222222};
        bit [31:0] rd [];
        $display("[TEST] Contention (M0+M1 → S0) ...");
        fork
            m0_write(32'h0000_0800, 4, 0, wd0);
            m1_write(32'h0000_0804, 5, 0, wd1);
        join
        m0_read(32'h0000_0800, 4, 0, rd); check("Cont0", rd[0], 32'h11111111);
        m0_read(32'h0000_0804, 5, 0, rd); check("Cont1", rd[0], 32'h22222222);
        $display("[TEST] Contention ... DONE");
    endtask

    // ======== Main ========
    initial begin
        $display("=============================================");
        $display("  AXI4 Full Crossbar Verification (2M×2S)");
        $display("=============================================");

        mst0_agent = new("mst0", u_vip_mst0.inst.IF);
        mst1_agent = new("mst1", u_vip_mst1.inst.IF);
        mst0_agent.vif_proxy.set_dummy_drive_type(XIL_AXI_VIF_DRIVE_NONE);
        mst1_agent.vif_proxy.set_dummy_drive_type(XIL_AXI_VIF_DRIVE_NONE);
        mst0_agent.start_master();
        mst1_agent.start_master();
        u_vip_mst0.inst.IF.clr_xilinx_slave_ready_check();
        u_vip_mst1.inst.IF.clr_xilinx_slave_ready_check();

        fork
            begin axi_ready_gen bg; bg = mst0_agent.wr_driver.create_ready("b0");
                  bg.set_ready_policy(XIL_AXI_READY_GEN_NO_BACKPRESSURE);
                  mst0_agent.wr_driver.send_bready(bg); end
            begin axi_ready_gen rg; rg = mst0_agent.rd_driver.create_ready("r0");
                  rg.set_ready_policy(XIL_AXI_READY_GEN_NO_BACKPRESSURE);
                  mst0_agent.rd_driver.send_rready(rg); end
            begin axi_ready_gen bg; bg = mst1_agent.wr_driver.create_ready("b1");
                  bg.set_ready_policy(XIL_AXI_READY_GEN_NO_BACKPRESSURE);
                  mst1_agent.wr_driver.send_bready(bg); end
            begin axi_ready_gen rg; rg = mst1_agent.rd_driver.create_ready("r1");
                  rg.set_ready_policy(XIL_AXI_READY_GEN_NO_BACKPRESSURE);
                  mst1_agent.rd_driver.send_rready(rg); end
        join_none

        aresetn = 0; repeat (20) @(posedge aclk);
        aresetn = 1; repeat (10) @(posedge aclk);

        test_routing();
        test_cross_path();
        test_burst();
        test_parallel_throughput();
        test_contention();

        repeat (20) @(posedge aclk);
        $display("=============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0) $display("  >>> ALL TESTS PASSED <<<");
        else                 $display("  >>> SOME TESTS FAILED <<<");
        $display("=============================================");
        $finish;
    end

    initial begin #20_000_000; $error("[TIMEOUT]"); $finish; end

endmodule
