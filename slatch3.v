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

reg  r_ack0;
reg  r_ack1;
reg  r_ack2;

assign q = r;

assign ack0 = r_ack0;
assign ack1 = r_ack1;
assign ack2 = r_ack2;


always @(posedge clk)
begin
  if (!res_n) begin
    r <= di;
    r_ack0 <= 1'b0;
    r_ack1 <= 1'b0;
    r_ack2 <= 1'b0;
  end else begin
    if (!req0) begin r_ack0 <= 1'b0; end
    if (!req1) begin r_ack1 <= 1'b0; end
    if (!req2) begin r_ack2 <= 1'b0; end

    if (req0 & !r_ack0) begin r <= d0; r_ack0 <= 1'b1; end
    else if (req1 & !r_ack1) begin r <= d1; r_ack1 <= 1'b1; end
    else if (req2 & !r_ack2) begin r <= d2; r_ack2 <= 1'b1; end
  end
end

endmodule
