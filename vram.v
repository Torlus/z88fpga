module vram
(clk, ai, di, ao, do);

	input 						clk;
	input 	[13:0] 		ai;		// 160*64 nibbles (6 bits for line + 8 bits for 4 pixels block)
	input 	[3:0] 		di;		// nibbles in
	input 	[17:0] 		ao;   // 5120*8 bits
	output 						do;		// 1 bit out

	// 8K RAM (64 lines of 1024 pixels, 1 bit per pixel)
	reg 		[8192:0]	ram;
	reg								do;

	// Port In (nibbles sent by blink)
	always @ (posedge clk)
	begin
		ram[ai] <= di;
	end

	// Port Out (bit get by display interface VGA/HDMI)
	always @ (posedge clk)
	begin
		do <= ram[ao];
	end

endmodule
