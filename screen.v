// -----------------------------------------------------------------------------
//  Z88 SCREEN
// -----------------------------------------------------------------------------
module screen(
// Inputs:
mck, rin_n, lcdon, clkcnt,
cdi,
pb0, pb1, pb2, pb3, sbr,

// Outputs:
va,
vram_a, vram_do, vram_we
);

// Clocks and control
input           mck;
input           rin_n;
input           lcdon;
input   [1:0]   clkcnt;

// Blink screen registers
input   [12:0]  pb0;  // Lores0 (ROM, 64 chars map)
input   [9:0]   pb1;  // Lores1 (RAM, 512-64 char map)
input   [8:0]   pb2;  // Hires0 (ROM, 256 char map)
input   [10:0]  pb3;  // Hires1 (RAM, 1024-256 char map)
input   [10:0]  sbr;  // SBR Screen Base Register

// Z88 memory
input   [7:0]   cdi;
output  [21:0]  va;

// VRAM buffer
output  [13:0]  vram_a;
output  [3:0]   vram_do;
output          vram_we;

// Internal screen registers
reg     [5:0]   slin; // screen line (64)
reg     [6:0]   scol; // screen column (108)
reg     [13:0]  sba;  // screen base attribute (char to render)
reg             sbar; // sba read flag
reg     [21:0]  r_va; // memory address register
reg     [7:0]   pix;  // pixel buffer

assign va = r_va;

always @(posedge mck)
begin
  if (!rin_n | !lcdon) begin
    sbar <= 1'b0;
    slin <= 6'd0;
    scol <= 7'd0;
    pix <= 8'd0;
  end else begin
    if (!sbar && clkcnt == 2'b10) begin
      // Z80 is active, data bus not to be used
      // screen base attribute address LSB (even) for next pulse
      r_va <= {sbr[10:0], slin[5:3], scol[6:0], 1'b0};
    end
    if (!sbar && clkcnt == 2'b00) begin
      // Z80 is not active, grab sba low
      sba[7:0] <= cdi;
      // screen base attribute address MSB (odd) for next pulse
      r_va[0] <= 1'b1;
    end
    if (!sbar && clkcnt == 2'b01) begin
      // Z80 is not active, grab sba high
      sba[13:8] <= cdi[5:0];
      sbar <= 1'b1;
    end
    if (sbar && clkcnt == 2'b10) begin
      // Z80 is active, data bus not to be used
      // pixel data address for next pulse
      r_va <= (sba[13] == 0) ?
        (sba[8:6] == 3'b111) ? {pb0[12:0], sba[5:0], slin[2:0]} // HRS=0; Lores0 (ROM)
        : {pb1[9:0], sba[8:0], slin[2:0]}                       // Lores1 (RAM)
      : (sba[9:8] == 2'b11) ? {pb3[10:0], sba[7:0], slin[2:0]}  // HRS=1; Hires1 (RAM)
        : {pb2[8:0], sba[9:0], slin[2:0]};                      // Hires0 (ROM)
    end
    if (sbar && clkcnt == 2'b00) begin
      // Z80 is not active, grab pixels
      pix <= cdi;
      // Increment line/column counters
      if (scol == 7'd108) begin
        scol <= 7'd0;
        if (slin == 6'd63) begin
          slin <= 6'd0;
        end else begin
          slin <= slin + 1'b1;
        end
      end else begin
        scol <= scol + 1'b1;
      end
    end
    if  (sbar && clkcnt == 2'b01) begin
      // Next cycle read sba
      sbar <= 1'b0;
    end
  end
end

endmodule
