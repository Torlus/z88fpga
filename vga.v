// -----------------------------------------------------------------------------
//  VGA
// -----------------------------------------------------------------------------
module vga (
clk25, reset_n, lcdon,
vram_a, vram_di,
href, vsync, rgb
);

input											clk25;
input											reset_n;
input											lcdon;
input			[3:0]						vram_di;

output		[13:0]					vram_a;
output										href;
output										vsync;
output		[11:0]					rgb;

`define BLACK 12'b000000000000
`define WHITE 12'b111111111111

reg 			[9:0]						hcount;
reg				[9:0]						vcount;

always @(posedge clk25) begin
	if (!reset_n || !lcdon) begin
		hcount <= 10'd0;
		vcount <= 10'd0;
	end else begin
		if(hcount < 10'd799) begin
			hcount <= hcount + 1'b1;
		end else if (hcount >= 10'd799) begin
			hcount <= 10'd0;
		end
		if(vcount < 10'd525 && hcount==10'd799) begin
			vcount <= vcount + 1'b1;
		end else if (vcount >= 10'd525) begin
			vcount <= 10'd0;
		end
	end
end

always @(posedge clk25) begin
	if(!reset_n || !lcdon) begin
		href<=1'b0;
		vsync<=1'b0;
	end else begin
		if(hcount <= 10'd656 || hcount >= 10'd752) begin
			href<=1'b1;
		end else begin
			href<=1'b0;
		end
		if(vcount <= 10'd490 || vcount >= 10'd492) begin
			vsync<=1'b1;
		end else begin
			vsync<=1'b0;
		end
	end
end

wire				[5:0]			line;
wire				[7:0]			nibble;
wire									pixel;

assign line = (vcount <= 10'd63) ? vcount[5:0] : 6'b111111;
assign nibble = (hcount[9:2] <= 8'd159) ? hcount[9:2] : 8'b11111111;

assign vram_a = {line[5:0], nibble[7:0]};

assign pixel = (hcount[1]) ?
	(hcount[0]) ? vram_di[3] : vram_di[2]
	: (hcount[0]) ? vram_di[1] : vram_di[0];

assign rgb = (line == 6'b111111 || nibble == 8'b11111111) ?
	`WHITE
	: (pixel) ? `BLACK : `WHITE;

endmodule
