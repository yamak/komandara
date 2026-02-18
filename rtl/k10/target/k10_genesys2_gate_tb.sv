`timescale 1ns/1ps

module k10_genesys2_gate_tb;

    logic       IO_CLK_P;
    logic       IO_CLK_N;
    logic       IO_RST;
    logic [7:0] gp_i;
    logic [7:0] gp_o;
    logic       uart0_rx_i;
    logic       uart0_tx_o;

    k10_genesys2_top #(
        .MEM_SIZE_KB(64),
        .BOOT_ADDR  (32'h8000_0000)
    ) dut (
        .IO_CLK_P (IO_CLK_P),
        .IO_CLK_N (IO_CLK_N),
        .IO_RST   (IO_RST),
        .gp_i     (gp_i),
        .gp_o     (gp_o),
        .uart0_rx_i(uart0_rx_i),
        .uart0_tx_o(uart0_tx_o)
    );

    initial begin
        IO_CLK_P = 1'b0;
        forever #2.5 IO_CLK_P = ~IO_CLK_P;
    end

    assign IO_CLK_N = ~IO_CLK_P;

    initial begin
        IO_RST    = 1'b1;
        gp_i      = '0;
        uart0_rx_i = 1'b1;
        #500;
        IO_RST = 1'b0;
    end

    initial begin
        #2000000;
        $fatal(1, "[NETLIST_SMOKE] TIMEOUT: gp_o[1] did not assert");
    end

    initial begin
        wait (gp_o[1] === 1'b1);
        $display("[NETLIST_SMOKE] PASS: gp_o[1] asserted by SW IRQ write");
        #100;
        $finish;
    end

endmodule : k10_genesys2_gate_tb
