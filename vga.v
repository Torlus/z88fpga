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
input			[3:0]			vram_do;

output		[13:0]		vram_a;
output							hsync;
output							vsync;
output		[11:0]		rgb;

wire			[5:0]			line;        // 64 lines
wire			[7:0]			nibble;      // 160 nibbles
wire								pixel;
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
assign nibble = (hcount[9:2] >= 8'd036 && hcount[9:2] <= 8'd195) ? (hcount[9:2]-8'd036) : 8'b11111111;

assign vram_a = {line[5:0], nibble[7:0]};

assign pixel = (hcount[1]) ?
	(hcount[0]) ? vram_do[2] : vram_do[3]
	: (hcount[0]) ? vram_do[0] : vram_do[1];

assign rgb = (line == 6'b111111 || nibble == 8'b11111111) ?
	`BLACK
	: (pixel) ? `BLACK : `WHITE;

endmodule
