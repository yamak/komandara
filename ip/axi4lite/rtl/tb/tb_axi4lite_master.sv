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
// Testbench: AXI4-Lite Master Verification with Xilinx AXI VIP
// ============================================================================
// Uses AXI VIP in SLAVE mode to respond to transactions from the DUT master.
// Reactive response threads service write/read transactions with a simple
// memory model. Tests: single R/W, back-to-back, protocol compliance.
// ============================================================================

`timescale 1ns / 1ps

module tb_axi4lite_master;

    import axi_vip_pkg::*;
    import axi_vip_slv_pkg::*;

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    localparam int ADDR_WIDTH  = 32;
    localparam int DATA_WIDTH  = 32;
    localparam int STRB_WIDTH  = DATA_WIDTH / 8;
    localparam int CLK_PERIOD  = 10;  // ns

    // --------------------------------------------------------
    // Clock & Reset
    // --------------------------------------------------------
    logic aclk    = 1'b0;
    logic aresetn = 1'b0;

    always #(CLK_PERIOD/2) aclk = ~aclk;

    // --------------------------------------------------------
    // Command / Response Interface
    // --------------------------------------------------------
    logic                      cmd_valid;
    logic                      cmd_ready;
    logic                      cmd_write;
    logic [ADDR_WIDTH-1:0]     cmd_addr;
    logic [DATA_WIDTH-1:0]     cmd_wdata;
    logic [STRB_WIDTH-1:0]     cmd_wstrb;
    logic [2:0]                cmd_prot;

    logic                      rsp_valid;
    logic                      rsp_ready;
    logic [DATA_WIDTH-1:0]     rsp_rdata;
    logic [1:0]                rsp_resp;

    // --------------------------------------------------------
    // AXI4-Lite Wires
    // --------------------------------------------------------
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [2:0]            awprot;
    logic                  awvalid, awready;

    logic [DATA_WIDTH-1:0] wdata;
    logic [3:0]            wstrb;
    logic                  wvalid, wready;

    logic [1:0]            bresp;
    logic                  bvalid, bready;

    logic [ADDR_WIDTH-1:0] araddr;
    logic [2:0]            arprot;
    logic                  arvalid, arready;

    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rvalid, rready;

    // --------------------------------------------------------
    // DUT — AXI4-Lite Master
    // --------------------------------------------------------
    komandara_axi4lite_master #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_dut (
        .clk_i             (aclk),
        .rst_ni            (aresetn),
        // Command
        .cmd_valid_i       (cmd_valid),
        .cmd_ready_o       (cmd_ready),
        .cmd_write_i       (cmd_write),
        .cmd_addr_i        (cmd_addr),
        .cmd_wdata_i       (cmd_wdata),
        .cmd_wstrb_i       (cmd_wstrb),
        .cmd_prot_i        (cmd_prot),
        // Response
        .rsp_valid_o       (rsp_valid),
        .rsp_ready_i       (rsp_ready),
        .rsp_rdata_o       (rsp_rdata),
        .rsp_resp_o        (rsp_resp),
        // AXI
        .m_axi_awaddr_o    (awaddr),
        .m_axi_awprot_o    (awprot),
        .m_axi_awvalid_o   (awvalid),
        .m_axi_awready_i   (awready),
        .m_axi_wdata_o     (wdata),
        .m_axi_wstrb_o     (wstrb),
        .m_axi_wvalid_o    (wvalid),
        .m_axi_wready_i    (wready),
        .m_axi_bresp_i     (bresp),
        .m_axi_bvalid_i    (bvalid),
        .m_axi_bready_o    (bready),
        .m_axi_araddr_o    (araddr),
        .m_axi_arprot_o    (arprot),
        .m_axi_arvalid_o   (arvalid),
        .m_axi_arready_i   (arready),
        .m_axi_rdata_i     (rdata),
        .m_axi_rresp_i     (rresp),
        .m_axi_rvalid_i    (rvalid),
        .m_axi_rready_o    (rready)
    );

    // --------------------------------------------------------
    // AXI VIP — Slave Instance
    // --------------------------------------------------------
    axi_vip_slv u_axi_vip_slv (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axi_awaddr  (awaddr),
        .s_axi_awprot  (awprot),
        .s_axi_awvalid (awvalid),
        .s_axi_awready (awready),
        .s_axi_wdata   (wdata),
        .s_axi_wstrb   (wstrb),
        .s_axi_wvalid  (wvalid),
        .s_axi_wready  (wready),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid),
        .s_axi_bready  (bready),
        .s_axi_araddr  (araddr),
        .s_axi_arprot  (arprot),
        .s_axi_arvalid (arvalid),
        .s_axi_arready (arready),
        .s_axi_rdata   (rdata),
        .s_axi_rresp   (rresp),
        .s_axi_rvalid  (rvalid),
        .s_axi_rready  (rready)
    );

    // --------------------------------------------------------
    // VIP Agent & Memory Model
    // --------------------------------------------------------
    axi_vip_slv_slv_t slv_agent;

    // Simple associative-array memory model for VIP slave
    bit [DATA_WIDTH-1:0] mem_model [bit [ADDR_WIDTH-1:0]];

    // Synchronization: agent started flag
    logic agent_started = 1'b0;

    // --------------------------------------------------------
    // Test Counters
    // --------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------
    task automatic check_resp(string tag, logic [1:0] got, logic [1:0] exp);
        if (got !== exp) begin
            $error("[%s] RESP mismatch: got %0b, expected %0b", tag, got, exp);
            fail_count++;
        end else begin
            pass_count++;
        end
    endtask

    task automatic check_data(string tag, logic [DATA_WIDTH-1:0] got,
                              logic [DATA_WIDTH-1:0] exp);
        if (got !== exp) begin
            $error("[%s] DATA mismatch: got 0x%08h, expected 0x%08h", tag, got, exp);
            fail_count++;
        end else begin
            pass_count++;
        end
    endtask

    // --------------------------------------------------------
    // Command Driver: issue a write command to DUT master
    // --------------------------------------------------------
    task automatic drive_write(input logic [ADDR_WIDTH-1:0] addr,
                               input logic [DATA_WIDTH-1:0] data,
                               input logic [STRB_WIDTH-1:0] strb = '1);
        @(posedge aclk);
        cmd_valid <= 1'b1;
        cmd_write <= 1'b1;
        cmd_addr  <= addr;
        cmd_wdata <= data;
        cmd_wstrb <= strb;
        cmd_prot  <= 3'b000;
        do @(posedge aclk); while (!cmd_ready);
        cmd_valid <= 1'b0;
    endtask

    // --------------------------------------------------------
    // Command Driver: issue a read command to DUT master
    // --------------------------------------------------------
    task automatic drive_read(input logic [ADDR_WIDTH-1:0] addr);
        @(posedge aclk);
        cmd_valid <= 1'b1;
        cmd_write <= 1'b0;
        cmd_addr  <= addr;
        cmd_wdata <= '0;
        cmd_wstrb <= '1;
        cmd_prot  <= 3'b000;
        do @(posedge aclk); while (!cmd_ready);
        cmd_valid <= 1'b0;
    endtask

    // --------------------------------------------------------
    // Response Consumer: wait for response from DUT master
    // --------------------------------------------------------
    task automatic wait_response(output logic [DATA_WIDTH-1:0] data,
                                 output logic [1:0]            resp);
        rsp_ready <= 1'b1;
        do @(posedge aclk); while (!rsp_valid);
        data = rsp_rdata;
        resp = rsp_resp;
        @(posedge aclk);
        rsp_ready <= 1'b0;
    endtask

    // --------------------------------------------------------
    // Reactive Write Response Thread
    // --------------------------------------------------------
    // Services incoming write transactions from the DUT master.
    // Stores data in the memory model and returns OKAY response.
    // --------------------------------------------------------
    initial begin
        axi_transaction wr_reactive;
        bit [ADDR_WIDTH-1:0] wr_addr;
        bit [DATA_WIDTH-1:0] wr_data;

        wait (agent_started);

        forever begin
            slv_agent.wr_driver.get_wr_reactive(wr_reactive);

            // Extract address and data
            wr_addr = wr_reactive.get_addr();
            wr_data = wr_reactive.get_data_beat(0);

            // Store in memory model
            mem_model[wr_addr] = wr_data;

            // Send OKAY write response
            wr_reactive.set_bresp(XIL_AXI_RESP_OKAY);
            slv_agent.wr_driver.send(wr_reactive);
        end
    end

    // --------------------------------------------------------
    // Reactive Read Response Thread
    // --------------------------------------------------------
    // Services incoming read transactions from the DUT master.
    // Returns data from the memory model with OKAY response.
    // --------------------------------------------------------
    initial begin
        axi_transaction rd_reactive;
        bit [ADDR_WIDTH-1:0] rd_addr;
        bit [DATA_WIDTH-1:0] rd_data;

        wait (agent_started);

        forever begin
            slv_agent.rd_driver.get_rd_reactive(rd_reactive);

            // Extract address
            rd_addr = rd_reactive.get_addr();

            // Lookup in memory model
            if (mem_model.exists(rd_addr))
                rd_data = mem_model[rd_addr];
            else
                rd_data = '0;

            // Set read data and response (beat 0 for AXI4-Lite)
            rd_reactive.set_data_beat(0, rd_data);
            rd_reactive.set_rresp(0, XIL_AXI_RESP_OKAY);
            slv_agent.rd_driver.send(rd_reactive);
        end
    end

    // ========================================================
    // Test: Single Write
    // ========================================================
    task automatic test_single_write();
        logic [DATA_WIDTH-1:0] rd_data;
        logic [1:0]            resp;

        $display("[TEST] Single Write ...");

        drive_write(32'h0000_0000, 32'hCAFE_BABE);
        wait_response(rd_data, resp);
        check_resp("SngWr resp", resp, 2'b00);

        $display("[TEST] Single Write ... DONE");
    endtask

    // ========================================================
    // Test: Single Read
    // ========================================================
    task automatic test_single_read();
        logic [DATA_WIDTH-1:0] rd_data;
        logic [1:0]            resp;

        $display("[TEST] Single Read ...");

        drive_read(32'h0000_0000);
        wait_response(rd_data, resp);
        check_resp("SngRd resp", resp, 2'b00);
        // Should return data written in previous test
        check_data("SngRd data", rd_data, 32'hCAFE_BABE);

        $display("[TEST] Single Read ... DONE");
    endtask

    // ========================================================
    // Test: Back-to-Back Writes
    // ========================================================
    task automatic test_back_to_back_writes();
        logic [DATA_WIDTH-1:0] rd_data;
        logic [1:0]            resp;

        $display("[TEST] Back-to-Back Writes ...");

        for (int i = 0; i < 8; i++) begin
            drive_write(i * 4, 32'hF000_0000 + i);
            wait_response(rd_data, resp);
            check_resp($sformatf("B2BW[%0d]", i), resp, 2'b00);
        end

        $display("[TEST] Back-to-Back Writes ... DONE");
    endtask

    // ========================================================
    // Test: Back-to-Back Reads
    // ========================================================
    task automatic test_back_to_back_reads();
        logic [DATA_WIDTH-1:0] rd_data;
        logic [1:0]            resp;

        $display("[TEST] Back-to-Back Reads ...");

        for (int i = 0; i < 8; i++) begin
            drive_read(i * 4);
            wait_response(rd_data, resp);
            check_resp($sformatf("B2BR[%0d] resp", i), resp, 2'b00);
            check_data($sformatf("B2BR[%0d] data", i), rd_data, 32'hF000_0000 + i);
        end

        $display("[TEST] Back-to-Back Reads ... DONE");
    endtask

    // ========================================================
    // Test: Write then Read (same address)
    // ========================================================
    task automatic test_write_then_read();
        logic [DATA_WIDTH-1:0] rd_data;
        logic [1:0]            resp;

        $display("[TEST] Write-then-Read ...");

        for (int i = 0; i < 4; i++) begin
            automatic logic [31:0] pattern = 32'hABCD_0000 + i;

            drive_write(i * 4, pattern);
            wait_response(rd_data, resp);
            check_resp($sformatf("WtR Wr[%0d]", i), resp, 2'b00);

            drive_read(i * 4);
            wait_response(rd_data, resp);
            check_resp($sformatf("WtR Rd[%0d] resp", i), resp, 2'b00);
            check_data($sformatf("WtR Rd[%0d] data", i), rd_data, pattern);
        end

        $display("[TEST] Write-then-Read ... DONE");
    endtask

    // ========================================================
    // Main Test Sequence
    // ========================================================
    initial begin
        // Defaults
        cmd_valid = 1'b0;
        cmd_write = 1'b0;
        cmd_addr  = '0;
        cmd_wdata = '0;
        cmd_wstrb = '0;
        cmd_prot  = '0;
        rsp_ready = 1'b0;

        $display("=============================================");
        $display("  Komandara AXI4-Lite Master Verification");
        $display("  Using Xilinx AXI VIP (Slave Mode)");
        $display("=============================================");

        // Create and start VIP slave agent
        slv_agent = new("slv_agent", u_axi_vip_slv.inst.IF);
        slv_agent.start_slave();

        // Signal reactive threads to start
        agent_started = 1'b1;

        // Reset sequence
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (10) @(posedge aclk);

        // ---- Run All Tests ----
        test_single_write();
        test_single_read();
        test_back_to_back_writes();
        test_back_to_back_reads();
        test_write_then_read();

        // ---- Summary ----
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

    // Timeout watchdog
    initial begin
        #5_000_000;
        $error("[TIMEOUT] Simulation timed out after 5 ms");
        $finish;
    end

endmodule
