package prim_util_pkg;

  function automatic int unsigned vbits(input int unsigned value);
    int unsigned temp;
    begin
      if (value <= 1) begin
        return 1;
      end

      temp = value - 1;
      vbits = 0;
      while (temp > 0) begin
        temp = temp >> 1;
        vbits = vbits + 1;
      end
    end
  endfunction

endpackage : prim_util_pkg
