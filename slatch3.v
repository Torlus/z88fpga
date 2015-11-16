module slatch3 (
  // Outputs
  q, ack0, ack1, ack2,

  // Inputs
  clk, res_n, di, req0, d0, req1, d1, req2, d2
);

output  q;
output  ack0;
output  ack1;
output  ack2;

input   clk;
input   res_n;
input   di;   // Initial value

input   req0;
input   d0;
input   req1;
input   d1;
input   req2;
input   d2;

reg     r;

assign q = r;

always @(posedge clk)
begin
  if (!res_n) begin
    r <= di;
    ack0 <= 1'b0;
    ack1 <= 1'b0;
    ack2 <= 1'b0;
  end else begin
    if (!req0) begin ack0 <= 1'b0; end
    if (!req1) begin ack1 <= 1'b0; end
    if (!req2) begin ack2 <= 1'b0; end

    if (req0 & !ack0) begin r <= d0; ack0 <= 1'b1; end
    else if (req1 & !ack1) begin r <= d1; ack1 <= 1'b1; end
    else if (req2 & !ack2) begin r <= d2; ack2 <= 1'b1; end
  end
end

endmodule
