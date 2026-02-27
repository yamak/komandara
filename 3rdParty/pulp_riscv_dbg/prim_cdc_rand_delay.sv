module prim_cdc_rand_delay #(
  parameter int DataWidth = 1,
  parameter bit Enable = 1'b0
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic [DataWidth-1:0] src_data_i,
  input  logic [DataWidth-1:0] prev_data_i,
  output logic [DataWidth-1:0] dst_data_o
);

  logic unused_sig;
  assign unused_sig = clk_i ^ rst_ni ^ Enable ^ ^prev_data_i;
  assign dst_data_o = src_data_i;

endmodule : prim_cdc_rand_delay
