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
// Testbench: AXI4-Lite Crossbar Verification (2M × 2S)
// ============================================================================
// Uses two Xilinx AXI VIP masters and two komandara_axi4lite_slave instances.
// Tests: routing, parallel paths, contention/arbitration, full throughput.
// ============================================================================

`timescale 1ns / 1ps

module tb_axi4lite_xbar;

    import axi_vip_pkg::*;
    import axi_vip_mst0_pkg::*;
    import axi_vip_mst1_pkg::*;

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    localparam int ADDR_WIDTH  = 32;
    localparam int DATA_WIDTH  = 32;
    localparam int N_MASTERS   = 2;
    localparam int N_SLAVES    = 2;
    localparam int CLK_PERIOD  = 10;
    localparam int REG_COUNT   = 16;

    // Address map: Slave 0 at 0x0000_0000, Slave 1 at 0x0001_0000
    localparam bit [2*32-1:0] SLV_BASE = {32'h0001_0000, 32'h0000_0000};
    localparam bit [2*32-1:0] SLV_MASK = {32'hFFFF_0000, 32'hFFFF_0000};

    // --------------------------------------------------------
    // Clock & Reset
    // --------------------------------------------------------
    logic aclk    = 1'b0;
    logic aresetn = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // --------------------------------------------------------
    // AXI wires: VIP master 0 ↔ crossbar slave port 0
    // --------------------------------------------------------
    logic [31:0] m0_awaddr;  logic [2:0] m0_awprot;
    logic        m0_awvalid, m0_awready;
    logic [31:0] m0_wdata;   logic [3:0] m0_wstrb;
    logic        m0_wvalid,  m0_wready;
    logic [1:0]  m0_bresp;   logic m0_bvalid, m0_bready;
    logic [31:0] m0_araddr;  logic [2:0] m0_arprot;
    logic        m0_arvalid, m0_arready;
    logic [31:0] m0_rdata;   logic [1:0] m0_rresp;
    logic        m0_rvalid,  m0_rready;

    // --------------------------------------------------------
    // AXI wires: VIP master 1 ↔ crossbar slave port 1
    // --------------------------------------------------------
    logic [31:0] m1_awaddr;  logic [2:0] m1_awprot;
    logic        m1_awvalid, m1_awready;
    logic [31:0] m1_wdata;   logic [3:0] m1_wstrb;
    logic        m1_wvalid,  m1_wready;
    logic [1:0]  m1_bresp;   logic m1_bvalid, m1_bready;
    logic [31:0] m1_araddr;  logic [2:0] m1_arprot;
    logic        m1_arvalid, m1_arready;
    logic [31:0] m1_rdata;   logic [1:0] m1_rresp;
    logic        m1_rvalid,  m1_rready;

    // --------------------------------------------------------
    // AXI wires: crossbar master port 0 ↔ slave 0
    // --------------------------------------------------------
    logic [31:0] s0_awaddr;  logic [2:0] s0_awprot;
    logic        s0_awvalid, s0_awready;
    logic [31:0] s0_wdata;   logic [3:0] s0_wstrb;
    logic        s0_wvalid,  s0_wready;
    logic [1:0]  s0_bresp;   logic s0_bvalid, s0_bready;
    logic [31:0] s0_araddr;  logic [2:0] s0_arprot;
    logic        s0_arvalid, s0_arready;
    logic [31:0] s0_rdata;   logic [1:0] s0_rresp;
    logic        s0_rvalid,  s0_rready;

    // --------------------------------------------------------
    // AXI wires: crossbar master port 1 ↔ slave 1
    // --------------------------------------------------------
    logic [31:0] s1_awaddr;  logic [2:0] s1_awprot;
    logic        s1_awvalid, s1_awready;
    logic [31:0] s1_wdata;   logic [3:0] s1_wstrb;
    logic        s1_wvalid,  s1_wready;
    logic [1:0]  s1_bresp;   logic s1_bvalid, s1_bready;
    logic [31:0] s1_araddr;  logic [2:0] s1_arprot;
    logic        s1_arvalid, s1_arready;
    logic [31:0] s1_rdata;   logic [1:0] s1_rresp;
    logic        s1_rvalid,  s1_rready;

    // --------------------------------------------------------
    // VIP Master 0
    // --------------------------------------------------------
    axi_vip_mst0 u_vip_mst0 (
        .aclk(aclk), .aresetn(aresetn),
        .m_axi_awaddr(m0_awaddr), .m_axi_awprot(m0_awprot),
        .m_axi_awvalid(m0_awvalid), .m_axi_awready(m0_awready),
        .m_axi_wdata(m0_wdata), .m_axi_wstrb(m0_wstrb),
        .m_axi_wvalid(m0_wvalid), .m_axi_wready(m0_wready),
        .m_axi_bresp(m0_bresp), .m_axi_bvalid(m0_bvalid), .m_axi_bready(m0_bready),
        .m_axi_araddr(m0_araddr), .m_axi_arprot(m0_arprot),
        .m_axi_arvalid(m0_arvalid), .m_axi_arready(m0_arready),
        .m_axi_rdata(m0_rdata), .m_axi_rresp(m0_rresp),
        .m_axi_rvalid(m0_rvalid), .m_axi_rready(m0_rready)
    );

    // --------------------------------------------------------
    // VIP Master 1
    // --------------------------------------------------------
    axi_vip_mst1 u_vip_mst1 (
        .aclk(aclk), .aresetn(aresetn),
        .m_axi_awaddr(m1_awaddr), .m_axi_awprot(m1_awprot),
        .m_axi_awvalid(m1_awvalid), .m_axi_awready(m1_awready),
        .m_axi_wdata(m1_wdata), .m_axi_wstrb(m1_wstrb),
        .m_axi_wvalid(m1_wvalid), .m_axi_wready(m1_wready),
        .m_axi_bresp(m1_bresp), .m_axi_bvalid(m1_bvalid), .m_axi_bready(m1_bready),
        .m_axi_araddr(m1_araddr), .m_axi_arprot(m1_arprot),
        .m_axi_arvalid(m1_arvalid), .m_axi_arready(m1_arready),
        .m_axi_rdata(m1_rdata), .m_axi_rresp(m1_rresp),
        .m_axi_rvalid(m1_rvalid), .m_axi_rready(m1_rready)
    );

    // --------------------------------------------------------
    // DUT — AXI4-Lite Crossbar (2M × 2S)
    // --------------------------------------------------------
    komandara_axi4lite_xbar #(
        .N_MASTERS       (N_MASTERS),
        .N_SLAVES        (N_SLAVES),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ROUND_ROBIN     (1'b1),
        .SLAVE_ADDR_BASE (SLV_BASE),
        .SLAVE_ADDR_MASK (SLV_MASK)
    ) u_xbar (
        .clk_i  (aclk),
        .rst_ni (aresetn),
        // Master-side (from VIP masters)
        .s_axi_awaddr_i  ({m1_awaddr,  m0_awaddr}),
        .s_axi_awprot_i  ({m1_awprot,  m0_awprot}),
        .s_axi_awvalid_i ({m1_awvalid, m0_awvalid}),
        .s_axi_awready_o ({m1_awready, m0_awready}),
        .s_axi_wdata_i   ({m1_wdata,   m0_wdata}),
        .s_axi_wstrb_i   ({m1_wstrb,   m0_wstrb}),
        .s_axi_wvalid_i  ({m1_wvalid,  m0_wvalid}),
        .s_axi_wready_o  ({m1_wready,  m0_wready}),
        .s_axi_bresp_o   ({m1_bresp,   m0_bresp}),
        .s_axi_bvalid_o  ({m1_bvalid,  m0_bvalid}),
        .s_axi_bready_i  ({m1_bready,  m0_bready}),
        .s_axi_araddr_i  ({m1_araddr,  m0_araddr}),
        .s_axi_arprot_i  ({m1_arprot,  m0_arprot}),
        .s_axi_arvalid_i ({m1_arvalid, m0_arvalid}),
        .s_axi_arready_o ({m1_arready, m0_arready}),
        .s_axi_rdata_o   ({m1_rdata,   m0_rdata}),
        .s_axi_rresp_o   ({m1_rresp,   m0_rresp}),
        .s_axi_rvalid_o  ({m1_rvalid,  m0_rvalid}),
        .s_axi_rready_i  ({m1_rready,  m0_rready}),
        // Slave-side (to our slave modules)
        .m_axi_awaddr_o  ({s1_awaddr,  s0_awaddr}),
        .m_axi_awprot_o  ({s1_awprot,  s0_awprot}),
        .m_axi_awvalid_o ({s1_awvalid, s0_awvalid}),
        .m_axi_awready_i ({s1_awready, s0_awready}),
        .m_axi_wdata_o   ({s1_wdata,   s0_wdata}),
        .m_axi_wstrb_o   ({s1_wstrb,   s0_wstrb}),
        .m_axi_wvalid_o  ({s1_wvalid,  s0_wvalid}),
        .m_axi_wready_i  ({s1_wready,  s0_wready}),
        .m_axi_bresp_i   ({s1_bresp,   s0_bresp}),
        .m_axi_bvalid_i  ({s1_bvalid,  s0_bvalid}),
        .m_axi_bready_o  ({s1_bready,  s0_bready}),
        .m_axi_araddr_o  ({s1_araddr,  s0_araddr}),
        .m_axi_arprot_o  ({s1_arprot,  s0_arprot}),
        .m_axi_arvalid_o ({s1_arvalid, s0_arvalid}),
        .m_axi_arready_i ({s1_arready, s0_arready}),
        .m_axi_rdata_i   ({s1_rdata,   s0_rdata}),
        .m_axi_rresp_i   ({s1_rresp,   s0_rresp}),
        .m_axi_rvalid_i  ({s1_rvalid,  s0_rvalid}),
        .m_axi_rready_o  ({s1_rready,  s0_rready})
    );

    // --------------------------------------------------------
    // Target Slave 0
    // --------------------------------------------------------
    komandara_axi4lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .REG_COUNT(REG_COUNT)
    ) u_slv0 (
        .clk_i(aclk), .rst_ni(aresetn),
        .s_axi_awaddr_i(s0_awaddr), .s_axi_awprot_i(s0_awprot),
        .s_axi_awvalid_i(s0_awvalid), .s_axi_awready_o(s0_awready),
        .s_axi_wdata_i(s0_wdata), .s_axi_wstrb_i(s0_wstrb),
        .s_axi_wvalid_i(s0_wvalid), .s_axi_wready_o(s0_wready),
        .s_axi_bresp_o(s0_bresp), .s_axi_bvalid_o(s0_bvalid), .s_axi_bready_i(s0_bready),
        .s_axi_araddr_i(s0_araddr), .s_axi_arprot_i(s0_arprot),
        .s_axi_arvalid_i(s0_arvalid), .s_axi_arready_o(s0_arready),
        .s_axi_rdata_o(s0_rdata), .s_axi_rresp_o(s0_rresp),
        .s_axi_rvalid_o(s0_rvalid), .s_axi_rready_i(s0_rready)
    );

    // --------------------------------------------------------
    // Target Slave 1
    // --------------------------------------------------------
    komandara_axi4lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .REG_COUNT(REG_COUNT)
    ) u_slv1 (
        .clk_i(aclk), .rst_ni(aresetn),
        .s_axi_awaddr_i(s1_awaddr), .s_axi_awprot_i(s1_awprot),
        .s_axi_awvalid_i(s1_awvalid), .s_axi_awready_o(s1_awready),
        .s_axi_wdata_i(s1_wdata), .s_axi_wstrb_i(s1_wstrb),
        .s_axi_wvalid_i(s1_wvalid), .s_axi_wready_o(s1_wready),
        .s_axi_bresp_o(s1_bresp), .s_axi_bvalid_o(s1_bvalid), .s_axi_bready_i(s1_bready),
        .s_axi_araddr_i(s1_araddr), .s_axi_arprot_i(s1_arprot),
        .s_axi_arvalid_i(s1_arvalid), .s_axi_arready_o(s1_arready),
        .s_axi_rdata_o(s1_rdata), .s_axi_rresp_o(s1_rresp),
        .s_axi_rvalid_o(s1_rvalid), .s_axi_rready_i(s1_rready)
    );

    // --------------------------------------------------------
    // VIP Agents
    // --------------------------------------------------------
    axi_vip_mst0_mst_t mst0_agent;
    axi_vip_mst1_mst_t mst1_agent;

    int pass_count = 0;
    int fail_count = 0;

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------
    task automatic check_data(string tag, logic [31:0] got, logic [31:0] exp);
        if (got !== exp) begin
            $error("[%s] DATA mismatch: got 0x%08h, exp 0x%08h", tag, got, exp);
            fail_count++;
        end else begin
            pass_count++;
        end
    endtask

    task automatic check_resp(string tag, xil_axi_resp_t got, xil_axi_resp_t exp);
        if (got !== exp) begin
            $error("[%s] RESP mismatch: got %0d, exp %0d", tag, got, exp);
            fail_count++;
        end else begin
            pass_count++;
        end
    endtask

    // ========================================================
    // Test 1: M0 → S0 write/read
    // ========================================================
    task automatic test_m0_to_s0();
        xil_axi_resp_t resp;
        bit [31:0] rd;
        $display("[TEST] M0 → S0 write/read ...");
        mst0_agent.AXI4LITE_WRITE_BURST(32'h0000_0000, 0, 32'hAAAA_0000, resp);
        check_resp("M0S0 Wr", resp, XIL_AXI_RESP_OKAY);
        mst0_agent.AXI4LITE_READ_BURST(32'h0000_0000, 0, rd, resp);
        check_resp("M0S0 Rd", resp, XIL_AXI_RESP_OKAY);
        check_data("M0S0 Rd data", rd, 32'hAAAA_0000);
        $display("[TEST] M0 → S0 write/read ... DONE");
    endtask

    // ========================================================
    // Test 2: M1 → S1 write/read
    // ========================================================
    task automatic test_m1_to_s1();
        xil_axi_resp_t resp;
        bit [31:0] rd;
        $display("[TEST] M1 → S1 write/read ...");
        mst1_agent.AXI4LITE_WRITE_BURST(32'h0001_0000, 0, 32'hBBBB_1111, resp);
        check_resp("M1S1 Wr", resp, XIL_AXI_RESP_OKAY);
        mst1_agent.AXI4LITE_READ_BURST(32'h0001_0000, 0, rd, resp);
        check_resp("M1S1 Rd", resp, XIL_AXI_RESP_OKAY);
        check_data("M1S1 Rd data", rd, 32'hBBBB_1111);
        $display("[TEST] M1 → S1 write/read ... DONE");
    endtask

    // ========================================================
    // Test 3: Cross path — M0 → S1, M1 → S0
    // ========================================================
    task automatic test_cross_path();
        xil_axi_resp_t resp;
        bit [31:0] rd;
        $display("[TEST] Cross path ...");
        // M0 writes to S1
        mst0_agent.AXI4LITE_WRITE_BURST(32'h0001_0004, 0, 32'hCC00_CC00, resp);
        check_resp("M0S1 Wr", resp, XIL_AXI_RESP_OKAY);
        // M1 writes to S0
        mst1_agent.AXI4LITE_WRITE_BURST(32'h0000_0004, 0, 32'hDD11_DD11, resp);
        check_resp("M1S0 Wr", resp, XIL_AXI_RESP_OKAY);
        // Read back
        mst0_agent.AXI4LITE_READ_BURST(32'h0001_0004, 0, rd, resp);
        check_data("M0S1 Rd", rd, 32'hCC00_CC00);
        mst1_agent.AXI4LITE_READ_BURST(32'h0000_0004, 0, rd, resp);
        check_data("M1S0 Rd", rd, 32'hDD11_DD11);
        $display("[TEST] Cross path ... DONE");
    endtask

    // ========================================================
    // Test 4: Parallel writes (no contention) — full throughput
    // ========================================================
    task automatic test_parallel_throughput();
        localparam int N_TXN = 16;
        xil_axi_resp_t resp0, resp1;
        bit [31:0] rd;
        int t_start, t_end, cycles;

        $display("[TEST] Parallel throughput (no contention) ...");

        t_start = $time;

        fork
            // Master 0 → Slave 0 : N_TXN writes
            begin
                for (int i = 0; i < N_TXN; i++)
                    mst0_agent.AXI4LITE_WRITE_BURST(i*4, 0, 32'hE000_0000+i, resp0);
            end
            // Master 1 → Slave 1 : N_TXN writes
            begin
                for (int i = 0; i < N_TXN; i++)
                    mst1_agent.AXI4LITE_WRITE_BURST(32'h0001_0000+i*4, 0, 32'hF000_0000+i, resp1);
            end
        join

        t_end = $time;
        cycles = (t_end - t_start) / CLK_PERIOD;
        $display("  Parallel: %0d writes each in %0d cycles (%.1f cycles/txn)",
                 N_TXN, cycles, real'(cycles) / real'(N_TXN));

        // Verify data
        for (int i = 0; i < N_TXN; i++) begin
            mst0_agent.AXI4LITE_READ_BURST(i*4, 0, rd, resp0);
            check_data($sformatf("ParS0[%0d]",i), rd, 32'hE000_0000+i);
        end
        for (int i = 0; i < N_TXN; i++) begin
            mst1_agent.AXI4LITE_READ_BURST(32'h0001_0000+i*4, 0, rd, resp1);
            check_data($sformatf("ParS1[%0d]",i), rd, 32'hF000_0000+i);
        end

        // --- Sequential baseline: M0 alone ---
        t_start = $time;
        for (int i = 0; i < N_TXN; i++)
            mst0_agent.AXI4LITE_WRITE_BURST(i*4, 0, 32'h1111_0000+i, resp0);
        t_end = $time;
        cycles = (t_end - t_start) / CLK_PERIOD;
        $display("  Seq base: %0d writes in %0d cycles (%.1f cycles/txn)",
                 N_TXN, cycles, real'(cycles) / real'(N_TXN));

        pass_count++;
        $display("[TEST] Parallel throughput ... DONE");
    endtask

    // ========================================================
    // Test 5: Contention — both masters → Slave 0
    // ========================================================
    task automatic test_contention();
        localparam int N_TXN = 8;
        xil_axi_resp_t resp0, resp1;
        bit [31:0] rd;

        $display("[TEST] Contention (M0+M1 → S0) ...");

        fork
            begin
                for (int i = 0; i < N_TXN; i++)
                    mst0_agent.AXI4LITE_WRITE_BURST(i*4, 0, 32'hAA00_0000+i, resp0);
            end
            begin
                for (int i = 0; i < N_TXN; i++)
                    mst1_agent.AXI4LITE_WRITE_BURST((i+N_TXN)*4, 0, 32'hBB00_0000+i, resp1);
            end
        join

        // Verify all writes landed in slave 0
        for (int i = 0; i < N_TXN; i++) begin
            mst0_agent.AXI4LITE_READ_BURST(i*4, 0, rd, resp0);
            check_data($sformatf("Cont M0[%0d]",i), rd, 32'hAA00_0000+i);
        end
        for (int i = 0; i < N_TXN; i++) begin
            mst0_agent.AXI4LITE_READ_BURST((i+N_TXN)*4, 0, rd, resp0);
            check_data($sformatf("Cont M1[%0d]",i), rd, 32'hBB00_0000+i);
        end

        $display("[TEST] Contention ... DONE");
    endtask

    // ========================================================
    // Main Test Sequence
    // ========================================================
    initial begin
        $display("=============================================");
        $display("  Komandara AXI4-Lite Crossbar Verification");
        $display("  2 Masters × 2 Slaves, Round-Robin");
        $display("=============================================");

        mst0_agent = new("mst0_agent", u_vip_mst0.inst.IF);
        mst1_agent = new("mst1_agent", u_vip_mst1.inst.IF);
        mst0_agent.start_master();
        mst1_agent.start_master();

        // Downgrade Xilinx ready-during-reset advisories
        u_vip_mst0.inst.IF.clr_xilinx_slave_ready_check();
        u_vip_mst1.inst.IF.clr_xilinx_slave_ready_check();

        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (10) @(posedge aclk);

        test_m0_to_s0();
        test_m1_to_s1();
        test_cross_path();
        test_parallel_throughput();
        test_contention();

        repeat (20) @(posedge aclk);
        $display("=============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        $display("=============================================");
        $finish;
    end

    initial begin
        #10_000_000;
        $error("[TIMEOUT] 10 ms");
        $finish;
    end

endmodule
