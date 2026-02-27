module prim_count #(
  parameter int Width = 1
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             clr_i,
  input  logic             set_i,
  input  logic [Width-1:0] set_cnt_i,
  input  logic             incr_en_i,
  input  logic             decr_en_i,
  input  logic [Width-1:0] step_i,
  input  logic             commit_i,
  output logic [Width-1:0] cnt_o,
  output logic [Width-1:0] cnt_after_commit_o,
  output logic             err_o
);

  logic [Width-1:0] cnt_n;

  always_comb begin
    cnt_n = cnt_o;
    if (clr_i) begin
      cnt_n = '0;
    end else if (set_i) begin
      cnt_n = set_cnt_i;
    end else begin
      if (incr_en_i) begin
        cnt_n = cnt_n + step_i;
      end
      if (decr_en_i) begin
        cnt_n = cnt_n - step_i;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cnt_o <= '0;
    end else if (commit_i) begin
      cnt_o <= cnt_n;
    end
  end

  assign cnt_after_commit_o = cnt_n;
  assign err_o = 1'b0;

endmodule : prim_count
