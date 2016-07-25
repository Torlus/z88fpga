// -----------------------------------------------------------------------------
//  VGA
// -----------------------------------------------------------------------------
//
// CLK 25.175 MHz
//
// LINE
// SYNC - BACKPORCH - BORDER - VISIBLE - BORDER - FRONTPORCH
// 96   - 40        - 8      - 640     - 8      - 8
//
// FIELD
// SYNC - BACKPORCH - BORDER - VISIBLE - BORDER - FRONTPORCH
// 2    - 25        - 8      - 480     - 8      - 2
//

module vga (
vclk, reset_n, lcdon,
vram_a, vram_do,
hsync, vsync, rgb
);

input								vclk;
input								reset_n;
input								lcdon;
input		      			vram_do;

output		[15:0]		vram_a;
output							hsync;
output							vsync;
output		[11:0]		rgb;

wire			[5:0]			line;        // 64 lines of
wire			[9:0]			pixel;       // 640 pixels

`define BLACK 12'b000000000000
`define WHITE 12'b111111111111

reg 			[9:0]			hcount;
reg				[9:0]			vcount;
reg 								hsync;
reg 								vsync;

// Counters
always @(posedge vclk) begin
  if (!reset_n || !lcdon) begin
		hcount <= 10'd0;
		vcount <= 10'd0;
	end else begin
		if (hcount == 10'd799) begin
			hcount <= 10'd0;
      if (vcount == 10'd524) begin
        vcount <= 10'd0;
      end else begin
			  vcount <= vcount + 10'd1;
      end
		end else begin
			hcount <= hcount + 10'd1;
		end
	end
end

// Sync
always @(posedge vclk) begin
  if(!reset_n || !lcdon) begin
		hsync <= 1'b1;
		vsync <= 1'b1;
	end else begin
  	hsync <= ~(hcount[9:0] < 96);  // pixels 0-95 : sync
  	vsync <= ~(vcount[9:1] == 0);  // lines 0-1 : sync
	end
end

// start display at nibble : (96+40+8)/4=36
assign line   = (vcount[9:6] == 3'b100) ? vcount[5:0] : 6'b111111;
assign pixel  = (hcount[9:0] >= 10'd144 && hcount[9:0] <= 10'd784) ? (hcount[9:0]-10'd144) : 10'b1111111111;

assign vram_a = {line[5:0], pixel[9:0]};

assign rgb = (line == 6'b111111 || pixel == 10'b1111111111) ?
	`BLACK
	: (vram_do) ? `BLACK : `WHITE;

endmodule
