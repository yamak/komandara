module prim_clock_mux2 #(
  parameter bit NoFpgaBufG = 1'b0
) (
  input  logic clk0_i,
  input  logic clk1_i,
  input  logic sel_i,
  output logic clk_o
);

  logic unused_param;
  assign unused_param = NoFpgaBufG;
  assign clk_o = sel_i ? clk1_i : clk0_i;

endmodule : prim_clock_mux2
