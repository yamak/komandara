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
// Testbench: AXI4 Full Master — DUT master drives Xilinx AXI VIP slave
// ============================================================================

`timescale 1ns / 1ps

module tb_axi4_master;

    import axi_vip_pkg::*;
    import axi_vip_slv_pkg::*;

    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int ID_WIDTH   = 4;
    localparam int CLK_PERIOD = 10;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // DUT → VIP AXI wires
    logic [ID_WIDTH-1:0] awid;  logic [31:0] awaddr;
    logic [7:0] awlen; logic [2:0] awsize; logic [1:0] awburst;
    logic       awlock; logic [3:0] awcache; logic [2:0] awprot;
    logic [3:0] awqos; logic [3:0] awregion;
    logic       awvalid, awready;

    logic [31:0] wdata; logic [3:0] wstrb;
    logic        wlast, wvalid, wready;

    logic [ID_WIDTH-1:0] bid; logic [1:0] bresp;
    logic        bvalid, bready;

    logic [ID_WIDTH-1:0] arid;  logic [31:0] araddr;
    logic [7:0] arlen; logic [2:0] arsize; logic [1:0] arburst;
    logic       arlock; logic [3:0] arcache; logic [2:0] arprot;
    logic [3:0] arqos; logic [3:0] arregion;
    logic       arvalid, arready;

    logic [ID_WIDTH-1:0] rid; logic [31:0] rdata; logic [1:0] rresp;
    logic        rlast, rvalid, rready;

    // Tie off unused master outputs
    assign awlock = 1'b0; assign awcache = 4'b0; assign awprot = 3'b0;
    assign awqos  = 4'b0; assign awregion = 4'b0;
    assign arlock = 1'b0; assign arcache = 4'b0; assign arprot = 3'b0;
    assign arqos  = 4'b0; assign arregion = 4'b0;

    // DUT upstream signals
    logic        wr_cmd_valid, wr_cmd_ready;
    logic [ID_WIDTH-1:0] wr_cmd_id;
    logic [31:0] wr_cmd_addr;
    logic [7:0]  wr_cmd_len; logic [2:0] wr_cmd_size; logic [1:0] wr_cmd_burst;

    logic        wr_data_valid, wr_data_ready;
    logic [31:0] wr_data; logic [3:0] wr_strb; logic wr_last;

    logic        wr_rsp_valid, wr_rsp_ready;
    logic [1:0]  wr_rsp_resp; logic [ID_WIDTH-1:0] wr_rsp_id;

    logic        rd_cmd_valid, rd_cmd_ready;
    logic [ID_WIDTH-1:0] rd_cmd_id;
    logic [31:0] rd_cmd_addr;
    logic [7:0]  rd_cmd_len; logic [2:0] rd_cmd_size; logic [1:0] rd_cmd_burst;

    logic        rd_data_valid, rd_data_ready;
    logic [31:0] rd_data_out; logic [1:0] rd_resp_out; logic rd_last_out;
    logic [ID_WIDTH-1:0] rd_id_out;

    // DUT
    komandara_axi4_master #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) u_dut (
        .clk_i(aclk), .rst_ni(aresetn),
        .wr_cmd_valid_i(wr_cmd_valid), .wr_cmd_ready_o(wr_cmd_ready),
        .wr_cmd_id_i(wr_cmd_id), .wr_cmd_addr_i(wr_cmd_addr),
        .wr_cmd_len_i(wr_cmd_len), .wr_cmd_size_i(wr_cmd_size), .wr_cmd_burst_i(wr_cmd_burst),
        .wr_data_valid_i(wr_data_valid), .wr_data_ready_o(wr_data_ready),
        .wr_data_i(wr_data), .wr_strb_i(wr_strb), .wr_last_i(wr_last),
        .wr_rsp_valid_o(wr_rsp_valid), .wr_rsp_ready_i(wr_rsp_ready),
        .wr_rsp_resp_o(wr_rsp_resp), .wr_rsp_id_o(wr_rsp_id),
        .rd_cmd_valid_i(rd_cmd_valid), .rd_cmd_ready_o(rd_cmd_ready),
        .rd_cmd_id_i(rd_cmd_id), .rd_cmd_addr_i(rd_cmd_addr),
        .rd_cmd_len_i(rd_cmd_len), .rd_cmd_size_i(rd_cmd_size), .rd_cmd_burst_i(rd_cmd_burst),
        .rd_data_valid_o(rd_data_valid), .rd_data_ready_i(rd_data_ready),
        .rd_data_o(rd_data_out), .rd_resp_o(rd_resp_out),
        .rd_last_o(rd_last_out), .rd_id_o(rd_id_out),
        .m_axi_awid_o(awid), .m_axi_awaddr_o(awaddr),
        .m_axi_awlen_o(awlen), .m_axi_awsize_o(awsize), .m_axi_awburst_o(awburst),
        .m_axi_awvalid_o(awvalid), .m_axi_awready_i(awready),
        .m_axi_wdata_o(wdata), .m_axi_wstrb_o(wstrb), .m_axi_wlast_o(wlast),
        .m_axi_wvalid_o(wvalid), .m_axi_wready_i(wready),
        .m_axi_bid_i(bid), .m_axi_bresp_i(bresp),
        .m_axi_bvalid_i(bvalid), .m_axi_bready_o(bready),
        .m_axi_arid_o(arid), .m_axi_araddr_o(araddr),
        .m_axi_arlen_o(arlen), .m_axi_arsize_o(arsize), .m_axi_arburst_o(arburst),
        .m_axi_arvalid_o(arvalid), .m_axi_arready_i(arready),
        .m_axi_rid_i(rid), .m_axi_rdata_i(rdata), .m_axi_rresp_i(rresp),
        .m_axi_rlast_i(rlast), .m_axi_rvalid_i(rvalid), .m_axi_rready_o(rready)
    );

    // VIP Slave
    axi_vip_slv u_vip_slv (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
        .s_axi_awsize(awsize), .s_axi_awburst(awburst), .s_axi_awlock(awlock),
        .s_axi_awcache(awcache), .s_axi_awprot(awprot), .s_axi_awqos(awqos),
        .s_axi_awregion(awregion), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen),
        .s_axi_arsize(arsize), .s_axi_arburst(arburst), .s_axi_arlock(arlock),
        .s_axi_arcache(arcache), .s_axi_arprot(arprot), .s_axi_arqos(arqos),
        .s_axi_arregion(arregion), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready)
    );

    // -------- VIP slave agent + memory model --------
    axi_vip_slv_slv_t slv_agent;
    bit [31:0] mem_model [bit [31:0]]; // associative

    int pass_count = 0, fail_count = 0;

    task automatic check(string tag, bit [31:0] got, bit [31:0] exp);
        if (got !== exp) begin $error("[%s] got 0x%08h exp 0x%08h", tag, got, exp); fail_count++; end
        else pass_count++;
    endtask

    // -------- Reactive helpers --------
    task automatic handle_wr_reactive(axi_transaction wr_txn);
        automatic bit [31:0] base_addr  = wr_txn.get_addr();
        automatic int unsigned burst_len = wr_txn.get_len();
        automatic int unsigned num_bytes = 1 << wr_txn.get_size();
        automatic xil_axi_burst_t burst_type = wr_txn.get_burst();
        automatic bit [31:0] addr = base_addr;
        for (int i = 0; i <= burst_len; i++) begin
            automatic bit [31:0] d = wr_txn.get_data_beat(i);
            mem_model[addr] = d;
            case (burst_type)
                XIL_AXI_BURST_TYPE_INCR: addr = addr + num_bytes;
                XIL_AXI_BURST_TYPE_WRAP: begin
                    automatic bit [31:0] ws = (burst_len + 1) * num_bytes;
                    automatic bit [31:0] lo = base_addr & ~(ws - 1);
                    addr = lo | ((addr + num_bytes) & (ws - 1));
                end
                default: ;
            endcase
        end
        wr_txn.set_bresp(XIL_AXI_RESP_OKAY);
        slv_agent.wr_driver.send(wr_txn);
    endtask

    task automatic handle_rd_reactive(axi_transaction rd_txn);
        automatic bit [31:0] base_addr  = rd_txn.get_addr();
        automatic int unsigned burst_len = rd_txn.get_len();
        automatic int unsigned num_bytes = 1 << rd_txn.get_size();
        automatic xil_axi_burst_t burst_type = rd_txn.get_burst();
        automatic bit [31:0] addr = base_addr;
        for (int i = 0; i <= burst_len; i++) begin
            automatic bit [31:0] d = mem_model.exists(addr) ? mem_model[addr] : 32'h0;
            rd_txn.set_data_beat(i, d);
            rd_txn.set_rresp(XIL_AXI_RESP_OKAY, i);
            case (burst_type)
                XIL_AXI_BURST_TYPE_INCR: addr = addr + num_bytes;
                XIL_AXI_BURST_TYPE_WRAP: begin
                    automatic bit [31:0] ws = (burst_len + 1) * num_bytes;
                    automatic bit [31:0] lo = base_addr & ~(ws - 1);
                    addr = lo | ((addr + num_bytes) & (ws - 1));
                end
                default: ;
            endcase
        end
        slv_agent.rd_driver.send(rd_txn);
    endtask

    // -------- Reactive handlers --------
    initial begin
        slv_agent = new("slv_agent", u_vip_slv.inst.IF);
        slv_agent.start_slave();

        fork
            forever begin : wr_handler
                axi_transaction wr_txn;
                slv_agent.wr_driver.get_wr_reactive(wr_txn);
                handle_wr_reactive(wr_txn);
            end
            forever begin : rd_handler
                axi_transaction rd_txn;
                slv_agent.rd_driver.get_rd_reactive(rd_txn);
                handle_rd_reactive(rd_txn);
            end
        join_none
    end

    // -------- Drive-side helpers --------
    task automatic do_write_burst(
        input bit [31:0] addr, input int id, input int len,
        input bit [1:0] burst, input bit [31:0] data []
    );
        // Issue command
        @(posedge aclk);
        wr_cmd_valid <= 1; wr_cmd_addr <= addr; wr_cmd_id <= id[ID_WIDTH-1:0];
        wr_cmd_len <= len[7:0]; wr_cmd_size <= 3'($clog2(DATA_WIDTH/8));
        wr_cmd_burst <= burst;
        do @(posedge aclk); while (!wr_cmd_ready);
        wr_cmd_valid <= 0;
        // Stream data
        for (int i = 0; i <= len; i++) begin
            wr_data_valid <= 1; wr_data <= data[i];
            wr_strb <= 4'hF; wr_last <= (i == len);
            do @(posedge aclk); while (!wr_data_ready);
        end
        wr_data_valid <= 0;
        // Wait for response
        wr_rsp_ready <= 1;
        do @(posedge aclk); while (!wr_rsp_valid);
        wr_rsp_ready <= 0;
    endtask

    task automatic do_read_burst(
        input bit [31:0] addr, input int id, input int len,
        input bit [1:0] burst, output bit [31:0] data []
    );
        @(posedge aclk);
        rd_cmd_valid <= 1; rd_cmd_addr <= addr; rd_cmd_id <= id[ID_WIDTH-1:0];
        rd_cmd_len <= len[7:0]; rd_cmd_size <= 3'($clog2(DATA_WIDTH/8));
        rd_cmd_burst <= burst;
        do @(posedge aclk); while (!rd_cmd_ready);
        rd_cmd_valid <= 0;
        // Consume data
        data = new[len+1];
        rd_data_ready <= 1;
        for (int i = 0; i <= len; i++) begin
            do @(posedge aclk); while (!rd_data_valid);
            data[i] = rd_data_out;
        end
        rd_data_ready <= 0;
    endtask

    // ======== Tests ========
    task automatic test_single_wr_rd();
        bit [31:0] wd [] = '{32'hCAFE_BABE};
        bit [31:0] rd [];
        $display("[TEST] Master single write/read ...");
        do_write_burst(32'h0000_0000, 0, 0, 2'b01, wd);
        do_read_burst (32'h0000_0000, 0, 0, 2'b01, rd);
        check("MstSingle", rd[0], 32'hCAFE_BABE);
        $display("[TEST] Master single write/read ... DONE");
    endtask

    task automatic test_burst_wr_rd();
        bit [31:0] wd [4];
        bit [31:0] rd [];
        $display("[TEST] Master burst (4 beats) ...");
        for (int i = 0; i < 4; i++) wd[i] = 32'hF000_0000 + i;
        do_write_burst(32'h0000_0100, 1, 3, 2'b01, wd);
        do_read_burst (32'h0000_0100, 1, 3, 2'b01, rd);
        for (int i = 0; i < 4; i++)
            check($sformatf("MstBurst[%0d]", i), rd[i], 32'hF000_0000+i);
        $display("[TEST] Master burst ... DONE");
    endtask

    task automatic test_back_to_back();
        bit [31:0] wd1 [] = '{32'h1111_AAAA};
        bit [31:0] wd2 [] = '{32'h2222_BBBB};
        bit [31:0] rd [];
        $display("[TEST] Master back-to-back ...");
        do_write_burst(32'h0000_0200, 2, 0, 2'b01, wd1);
        do_write_burst(32'h0000_0204, 3, 0, 2'b01, wd2);
        do_read_burst (32'h0000_0200, 2, 0, 2'b01, rd);
        check("B2B0", rd[0], 32'h1111_AAAA);
        do_read_burst (32'h0000_0204, 3, 0, 2'b01, rd);
        check("B2B1", rd[0], 32'h2222_BBBB);
        $display("[TEST] Master back-to-back ... DONE");
    endtask

    // ======== Main ========
    initial begin
        wr_cmd_valid  = 0; wr_data_valid = 0; wr_rsp_ready = 0;
        rd_cmd_valid  = 0; rd_data_ready = 0;

        $display("=============================================");
        $display("  AXI4 Full Master Verification");
        $display("=============================================");

        aresetn = 0; repeat (20) @(posedge aclk);
        aresetn = 1; repeat (10) @(posedge aclk);

        test_single_wr_rd();
        test_burst_wr_rd();
        test_back_to_back();

        repeat (20) @(posedge aclk);
        $display("=============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0) $display("  >>> ALL TESTS PASSED <<<");
        else                 $display("  >>> SOME TESTS FAILED <<<");
        $display("=============================================");
        $finish;
    end

    initial begin #10_000_000; $error("[TIMEOUT]"); $finish; end

endmodule
