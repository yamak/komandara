module k10_clock_wizard (
    input  logic IO_CLK_P,
    input  logic IO_CLK_N,
    input  logic IO_RST_N,
    output logic clk_sys,
    output logic rst_sys_n
);

    logic w_ibufg_out;
    logic w_pll_fb_out, w_pll_fb_in;
    logic w_pll_clk0_out;
    logic w_pll_locked;

    // LVDS input clock buffer
    IBUFGDS #(
        .DIFF_TERM   ("FALSE"),
        .IOSTANDARD  ("LVDS")
    ) u_clk_ibufg (
        .I (IO_CLK_P),
        .IB(IO_CLK_N),
        .O (w_ibufg_out)
    );

    // Advanced PLL instance for 50MHz clock derivation
    PLLE2_ADV #(
        .BANDWIDTH          ("OPTIMIZED"),
        .COMPENSATION       ("ZHOLD"),
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT      (5),
        .CLKOUT0_DIVIDE     (20),
        .CLKIN1_PERIOD      (5.0)
    ) u_sys_pll (
        .CLKIN1   (w_ibufg_out),
        .CLKIN2   (1'b0),
        .CLKINSEL (1'b1),
        .CLKFBOUT (w_pll_fb_out),
        .CLKFBIN  (w_pll_fb_in),
        .CLKOUT0  (w_pll_clk0_out),
        .CLKOUT1  (),
        .CLKOUT2  (),
        .CLKOUT3  (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .RST      (1'b0),
        .PWRDWN   (1'b0),
        .LOCKED   (w_pll_locked),
        .DADDR    (7'b0),
        .DCLK     (1'b0),
        .DEN      (1'b0),
        .DI       (16'b0),
        .DWE      (1'b0),
        .DO       (),
        .DRDY     ()
    );

    // Buffer the feedback clock
    BUFG u_bufg_fb (.I(w_pll_fb_out), .O(w_pll_fb_in));
    
    // Buffer the generated output clock
    BUFG u_bufg_clk0 (.I(w_pll_clk0_out), .O(clk_sys));

    // Synchronize subsystem reset release to PLL lock status
    assign rst_sys_n = w_pll_locked & IO_RST_N;

endmodule
