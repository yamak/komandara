module prim_clock_inv #(
  parameter bit HasScanMode = 1'b0,
  parameter bit NoFpgaBufG = 1'b0
) (
  input  logic clk_i,
  output logic clk_no,
  input  logic scanmode_i
);

  logic unused_scanmode;
  logic unused_params;

  assign unused_scanmode = scanmode_i;
  assign unused_params = HasScanMode ^ NoFpgaBufG;
  assign clk_no = ~clk_i;

endmodule : prim_clock_inv
