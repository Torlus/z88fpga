// -----------------------------------------------------------------------------
//  VGA
// -----------------------------------------------------------------------------
module vga (
clk25, reset_n, lcdon,
vram_a, vram_do,
o_href, o_vsync, rgb
);

input											clk25;
input											reset_n;
input											lcdon;
input			[3:0]						vram_do;

output		[13:0]					vram_a;
output										o_href;
output										o_vsync;
output		[11:0]					rgb;

`define BLACK 12'b000000000000
`define WHITE 12'b111111111111

reg 			[9:0]						hcount;
reg				[8:0]						vcount;
reg 											href;
reg 											vsync;

wire            					hmax = (hcount==767);

assign 										o_href = ~href;
assign 										o_vsync = ~vsync;

always @(posedge clk25) begin
  if (!reset_n || !lcdon) begin
		hcount <= 10'd0;
		vcount <= 9'd0;
	end else begin
		if (hmax) begin
			hcount <= 10'd0;
			vcount <= vcount + 9'd1;
		end else begin
			hcount <= hcount + 10'd1;
		end
	end
end

always @(posedge clk25) begin
  if(!reset_n || !lcdon) begin
		href <= 1'b0;
		vsync <= 1'b0;
	end else begin
  	href <= (hcount[9:4]==0);   // active for 16 clocks
  	vsync <= (vcount==0);   // active for 768 clocks
	end
end

wire				[5:0]			line;
wire				[7:0]			nibble;
wire									pixel;

assign line = (vcount[8:6] == 3'b001) ? vcount[5:0] : 6'b111111;
assign nibble = (hcount[9:2] >= 8'd036 && hcount[9:2] <= 8'd195) ? (hcount[9:2]-8'd036) : 8'b11111111;

assign vram_a = {line[5:0], nibble[7:0]};

assign pixel = (hcount[1]) ?
	(hcount[0]) ? vram_do[2] : vram_do[3]
	: (hcount[0]) ? vram_do[0] : vram_do[1];

assign rgb = (line == 6'b111111 || nibble == 8'b11111111) ?
	`BLACK
	: (pixel) ? `BLACK : `WHITE;

//assign rgb = 12'b111100001111;
//assign  rgb = {hcount[3:0],hcount[7:4],vcount[3:0]};

endmodule
