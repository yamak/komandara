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
// Testbench: AXI4 Full Slave — Xilinx AXI VIP master drives DUT slave
// ============================================================================

`timescale 1ns / 1ps

module tb_axi4_slave;

    import axi_vip_pkg::*;
    import axi_vip_mst_pkg::*;

    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int ID_WIDTH   = 4;
    localparam int CLK_PERIOD = 10;
    localparam int MEM_DEPTH  = 4096;

    // Clock & Reset
    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // AXI wires
    logic [ID_WIDTH-1:0]  awid;    logic [31:0] awaddr;
    logic [7:0]  awlen;  logic [2:0] awsize;  logic [1:0] awburst;
    logic        awlock; logic [3:0] awcache; logic [2:0] awprot;
    logic [3:0]  awqos;  logic [3:0] awregion;
    logic        awvalid, awready;

    logic [31:0] wdata;  logic [3:0] wstrb;
    logic        wlast,  wvalid, wready;

    logic [ID_WIDTH-1:0] bid; logic [1:0] bresp;
    logic        bvalid, bready;

    logic [ID_WIDTH-1:0] arid;   logic [31:0] araddr;
    logic [7:0]  arlen;  logic [2:0] arsize;  logic [1:0] arburst;
    logic        arlock; logic [3:0] arcache; logic [2:0] arprot;
    logic [3:0]  arqos;  logic [3:0] arregion;
    logic        arvalid, arready;

    logic [ID_WIDTH-1:0] rid; logic [31:0] rdata; logic [1:0] rresp;
    logic        rlast,  rvalid, rready;

    // VIP Master
    axi_vip_mst u_vip_mst (
        .aclk(aclk), .aresetn(aresetn),
        .m_axi_awid(awid),     .m_axi_awaddr(awaddr),   .m_axi_awlen(awlen),
        .m_axi_awsize(awsize), .m_axi_awburst(awburst), .m_axi_awlock(awlock),
        .m_axi_awcache(awcache), .m_axi_awprot(awprot), .m_axi_awqos(awqos),
        .m_axi_awregion(awregion), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_arid(arid),     .m_axi_araddr(araddr),   .m_axi_arlen(arlen),
        .m_axi_arsize(arsize), .m_axi_arburst(arburst), .m_axi_arlock(arlock),
        .m_axi_arcache(arcache), .m_axi_arprot(arprot), .m_axi_arqos(arqos),
        .m_axi_arregion(arregion), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp),
        .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    // DUT
    komandara_axi4_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .MEM_DEPTH(MEM_DEPTH)
    ) u_dut (
        .clk_i(aclk), .rst_ni(aresetn),
        .s_axi_awid_i(awid),       .s_axi_awaddr_i(awaddr),
        .s_axi_awlen_i(awlen),     .s_axi_awsize_i(awsize),
        .s_axi_awburst_i(awburst), .s_axi_awvalid_i(awvalid),
        .s_axi_awready_o(awready),
        .s_axi_wdata_i(wdata), .s_axi_wstrb_i(wstrb),
        .s_axi_wlast_i(wlast), .s_axi_wvalid_i(wvalid), .s_axi_wready_o(wready),
        .s_axi_bid_o(bid), .s_axi_bresp_o(bresp),
        .s_axi_bvalid_o(bvalid), .s_axi_bready_i(bready),
        .s_axi_arid_i(arid),       .s_axi_araddr_i(araddr),
        .s_axi_arlen_i(arlen),     .s_axi_arsize_i(arsize),
        .s_axi_arburst_i(arburst), .s_axi_arvalid_i(arvalid),
        .s_axi_arready_o(arready),
        .s_axi_rid_o(rid), .s_axi_rdata_o(rdata), .s_axi_rresp_o(rresp),
        .s_axi_rlast_o(rlast), .s_axi_rvalid_o(rvalid), .s_axi_rready_i(rready)
    );

    // -------- Agent --------
    axi_vip_mst_mst_t mst_agent;
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(string tag, bit [31:0] got, bit [31:0] exp);
        if (got !== exp) begin $error("[%s] got 0x%08h exp 0x%08h", tag, got, exp); fail_count++; end
        else pass_count++;
    endtask

    // -------- Helper: write burst --------
    task automatic axi4_write(
        input bit [31:0] addr, input int id, input int len,
        input xil_axi_burst_t burst, input bit [31:0] data[]
    );
        axi_transaction wr_txn;
        wr_txn = mst_agent.wr_driver.create_transaction("wr");
        wr_txn.set_write_cmd(addr, burst, id, len,
                         xil_axi_size_t'($clog2(DATA_WIDTH/8)));
        for (int i = 0; i <= len; i++) begin
            wr_txn.set_data_beat(i, data[i]);
            wr_txn.set_strb_beat(i, 4'hF);
        end
        wr_txn.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
        mst_agent.wr_driver.send(wr_txn);
        mst_agent.wr_driver.wait_rsp(wr_txn);
    endtask

    // -------- Helper: read burst --------
    task automatic axi4_read(
        input bit [31:0] addr, input int id, input int len,
        input xil_axi_burst_t burst, output bit [31:0] data[]
    );
        axi_transaction rd_txn;
        rd_txn = mst_agent.rd_driver.create_transaction("rd");
        rd_txn.set_read_cmd(addr, burst, id, len,
                        xil_axi_size_t'($clog2(DATA_WIDTH/8)));
        rd_txn.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
        mst_agent.rd_driver.send(rd_txn);
        mst_agent.rd_driver.wait_rsp(rd_txn);
        data = new[len+1];
        for (int i = 0; i <= len; i++)
            data[i] = rd_txn.get_data_beat(i);
    endtask

    // ======== Test 1: single write/read ========
    task automatic test_single();
        bit [31:0] wd [] = '{32'hDEAD_BEEF};
        bit [31:0] rd [];
        $display("[TEST] Single write/read ...");
        axi4_write(32'h0000_0000, 0, 0, XIL_AXI_BURST_TYPE_INCR, wd);
        $display("  Write done");
        axi4_read (32'h0000_0000, 0, 0, XIL_AXI_BURST_TYPE_INCR, rd);
        $display("  Read done");
        check("Single", rd[0], 32'hDEAD_BEEF);
        $display("[TEST] Single write/read ... DONE");
    endtask

    // ======== Test 2: INCR burst (len=7, 8 beats) ========
    task automatic test_incr_burst();
        bit [31:0] wd [8];
        bit [31:0] rd [];
        $display("[TEST] INCR burst (8 beats) ...");
        for (int i = 0; i < 8; i++) wd[i] = 32'hA000_0000 + i;
        axi4_write(32'h0000_0100, 1, 7, XIL_AXI_BURST_TYPE_INCR, wd);
        axi4_read (32'h0000_0100, 1, 7, XIL_AXI_BURST_TYPE_INCR, rd);
        for (int i = 0; i < 8; i++)
            check($sformatf("Incr[%0d]", i), rd[i], 32'hA000_0000+i);
        $display("[TEST] INCR burst ... DONE");
    endtask

    // ======== Test 3: WRAP burst (len=3, 4 beats) ========
    task automatic test_wrap_burst();
        bit [31:0] wd [4];
        bit [31:0] rd [];
        $display("[TEST] WRAP burst (4 beats) ...");
        for (int i = 0; i < 4; i++) wd[i] = 32'hB000_0000 + i;
        axi4_write(32'h0000_0200, 2, 3, XIL_AXI_BURST_TYPE_WRAP, wd);
        axi4_read (32'h0000_0200, 2, 3, XIL_AXI_BURST_TYPE_WRAP, rd);
        for (int i = 0; i < 4; i++)
            check($sformatf("Wrap[%0d]", i), rd[i], 32'hB000_0000+i);
        $display("[TEST] WRAP burst ... DONE");
    endtask

    // ======== Test 4: FIXED burst (len=3) ========
    task automatic test_fixed_burst();
        bit [31:0] wd [4];
        bit [31:0] rd [];
        $display("[TEST] FIXED burst (4 beats) ...");
        // FIXED: all beats hit same address -> last write wins
        for (int i = 0; i < 4; i++) wd[i] = 32'hC000_0000 + i;
        axi4_write(32'h0000_0300, 3, 3, XIL_AXI_BURST_TYPE_FIXED, wd);
        axi4_read (32'h0000_0300, 3, 0, XIL_AXI_BURST_TYPE_INCR, rd);
        check("Fixed last", rd[0], 32'hC000_0003); // last write wins
        $display("[TEST] FIXED burst ... DONE");
    endtask

    // ======== Test 5: back-to-back ========
    task automatic test_back_to_back();
        bit [31:0] wd1 [] = '{32'h1111_1111};
        bit [31:0] wd2 [] = '{32'h2222_2222};
        bit [31:0] rd [];
        $display("[TEST] Back-to-back ...");
        axi4_write(32'h0000_0400, 4, 0, XIL_AXI_BURST_TYPE_INCR, wd1);
        axi4_write(32'h0000_0404, 5, 0, XIL_AXI_BURST_TYPE_INCR, wd2);
        axi4_read (32'h0000_0400, 4, 0, XIL_AXI_BURST_TYPE_INCR, rd);
        check("B2B 0", rd[0], 32'h1111_1111);
        axi4_read (32'h0000_0404, 5, 0, XIL_AXI_BURST_TYPE_INCR, rd);
        check("B2B 1", rd[0], 32'h2222_2222);
        $display("[TEST] Back-to-back ... DONE");
    endtask

    // ======== Test 6: byte strobes ========
    task automatic test_byte_strobes();
        axi_transaction wr, rd_t;
        bit [31:0] rd_data;
        $display("[TEST] Byte strobes ...");
        // Write full word
        wr = mst_agent.wr_driver.create_transaction("wr_bs1");
        wr.set_write_cmd(32'h0000_0500, XIL_AXI_BURST_TYPE_INCR, 6, 0,
                         xil_axi_size_t'(2));
        wr.set_data_beat(0, 32'hAABBCCDD);
        wr.set_strb_beat(0, 4'b1111);
        wr.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
        mst_agent.wr_driver.send(wr);
        mst_agent.wr_driver.wait_rsp(wr);
        // Partial write: byte 0,1 only
        wr = mst_agent.wr_driver.create_transaction("wr_bs2");
        wr.set_write_cmd(32'h0000_0500, XIL_AXI_BURST_TYPE_INCR, 6, 0,
                         xil_axi_size_t'(2));
        wr.set_data_beat(0, 32'h00002211);
        wr.set_strb_beat(0, 4'b0011);
        wr.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
        mst_agent.wr_driver.send(wr);
        mst_agent.wr_driver.wait_rsp(wr);
        // Read back
        rd_t = mst_agent.rd_driver.create_transaction("rd_bs");
        rd_t.set_read_cmd(32'h0000_0500, XIL_AXI_BURST_TYPE_INCR, 6, 0,
                          xil_axi_size_t'(2));
        rd_t.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
        mst_agent.rd_driver.send(rd_t);
        mst_agent.rd_driver.wait_rsp(rd_t);
        rd_data = rd_t.get_data_beat(0);
        check("ByteStrb", rd_data, 32'hAABB2211);
        $display("[TEST] Byte strobes ... DONE");
    endtask

    // ======== Test 7: long burst (len=15, 16 beats) ========
    task automatic test_long_burst();
        bit [31:0] wd [16];
        bit [31:0] rd [];
        $display("[TEST] Long burst (16 beats) ...");
        for (int i = 0; i < 16; i++) wd[i] = 32'hD000_0000 + i;
        axi4_write(32'h0000_0600, 7, 15, XIL_AXI_BURST_TYPE_INCR, wd);
        axi4_read (32'h0000_0600, 7, 15, XIL_AXI_BURST_TYPE_INCR, rd);
        for (int i = 0; i < 16; i++)
            check($sformatf("Long[%0d]", i), rd[i], 32'hD000_0000+i);
        $display("[TEST] Long burst ... DONE");
    endtask

    // ======== Main ========
    initial begin
        $display("=============================================");
        $display("  AXI4 Full Slave Verification");
        $display("=============================================");

        mst_agent = new("mst_agent", u_vip_mst.inst.IF);
        mst_agent.vif_proxy.set_dummy_drive_type(XIL_AXI_VIF_DRIVE_NONE);
        mst_agent.start_master();

        u_vip_mst.inst.IF.clr_xilinx_slave_ready_check();

        // Non-blocking ready gen in background
        fork
            begin
                axi_ready_gen bready_gen = mst_agent.wr_driver.create_ready("bready");
                bready_gen.set_ready_policy(XIL_AXI_READY_GEN_NO_BACKPRESSURE);
                mst_agent.wr_driver.send_bready(bready_gen);
            end
            begin
                axi_ready_gen rready_gen = mst_agent.rd_driver.create_ready("rready");
                rready_gen.set_ready_policy(XIL_AXI_READY_GEN_NO_BACKPRESSURE);
                mst_agent.rd_driver.send_rready(rready_gen);
            end
        join_none

        aresetn = 0; repeat (20) @(posedge aclk);
        aresetn = 1; repeat (10) @(posedge aclk);

        test_single();
        test_incr_burst();
        test_wrap_burst();
        test_fixed_burst();
        test_back_to_back();
        test_byte_strobes();
        test_long_burst();

        repeat (20) @(posedge aclk);
        $display("=============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0) $display("  >>> ALL TESTS PASSED <<<");
        else                 $display("  >>> SOME TESTS FAILED <<<");
        $display("=============================================");
        $finish;
    end

    initial begin #5_000_000; $error("[TIMEOUT]"); $finish; end

endmodule
