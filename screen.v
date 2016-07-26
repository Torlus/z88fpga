// -----------------------------------------------------------------------------
//  Z88 SCREEN
// -----------------------------------------------------------------------------
module screen(
// Inputs:
mck, rin_n, lcdon, clkcnt,
cdi,
pb0, pb1, pb2, pb3, sbr,
t_1s, t_5ms,

// Outputs:
va,
o_vram_a, o_vram_do, o_vram_we,
o_frame
);

// BMP debug output
output          o_frame;

// Clocks and control
input           mck;
input           rin_n;
input           lcdon;
input   [1:0]   clkcnt;
input           t_1s;
input           t_5ms;

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
output  [13:0]  o_vram_a;
output  [3:0]   o_vram_do;
output          o_vram_we;

// Internal screen registers
reg     [6:0]   scol; // screen column (108)
                      // Screen Base Attribute from the Screen Base File
reg             hrs;  // hires (8 pixels wide char else 6)
reg             rev;  // reverse char (XOR)
reg             fls;  // flash (1 second flashing)
reg             gry;  // grey (5ms flashing probably)
reg             und;  // underline (sba[9] when HRS)
reg     [8:0]   sba;  // screen base attribute (char to render)
reg             sbar; // sba read flag
reg     [21:0]  r_va; // memory address register
reg     [1:0]   pix6b;  // pixel buffer for lores (6 pixels wide)
reg     [3:0]   pix4b;  // pixel buffer for second step output
reg             pix6f;  // flag for 2 pixels remaining in pix6b
reg             pix4f;  // flag for 4 pixels remaining in pix4b

reg          vram_we;
reg  [13:0]  vram_a;
reg  [3:0]   vram_do;

reg          frame;


assign o_vram_a = vram_a;
assign o_vram_do = vram_do;
assign o_vram_we = vram_we;
assign o_frame = frame;

assign va = r_va;

// Shortcuts
wire    [5:0]   slin; // screen line (64)
wire            cursor; // lores cursor header
wire            nullch; // do not increment nibble counter

assign slin = vram_a[13:8];
assign cursor = hrs & rev & fls;
assign nullch = hrs & rev & !fls & gry;

// Screen effects
wire [7:0] und_e;
wire [7:0] rev_e;
wire [7:0] gry_e;
wire [7:0] scr;
// Underline, full line if lores and eighth line
assign und_e = (und && !hrs && slin[2:0] == 3'b111) ? 8'b11111111 : cdi[7:0];
// Reverse,
assign rev_e = (rev) ? {~und_e}  : und_e;
// Grey, quick flashing
assign gry_e = (gry) ? rev_e & {t_5ms,t_5ms,t_5ms,t_5ms,t_5ms,t_5ms,t_5ms,t_5ms} : rev_e;
// Flash, 1 second flashing
assign scr = (fls) ? gry_e & {t_1s,t_1s,t_1s,t_1s,t_1s,t_1s,t_1s,t_1s} : gry_e;

// screen rendering main
always @(posedge mck)
begin
  if (!rin_n | !lcdon) begin
    sbar <= 1'b0;
    scol <= 7'd0;
    pix6f <= 1'b0;
    pix4f <= 1'b0;
    vram_a <= 14'd0;
    vram_we <= 1'b0;
    // frame flag for BMP debug output
    frame <= 1'b0;
  end else begin

    // 1) Set SBA
    // ----------
    if (!sbar && clkcnt == 2'b10) begin
      // Z80 is active, data bus not to be used
      // screen base attribute address LSB (even) for next pulse
      r_va <= {sbr[10:0], slin[5:3], scol[6:0], 1'b0};

      // Flush second nibble (remaining 4 pixels)
      if (pix4f) begin
        vram_do <= pix4b;  // Output remaining pixels (or do nothing if null char or only 2 pixels left)
        vram_we <= 1'b1;
      end

      // BMP done
      frame <= 1'b0;
    end

    // 2) Read SBA LSB
    // ---------------
    if (!sbar && clkcnt == 2'b00) begin
      // Z80 is not active, grab sba low
      sba[7:0] <= cdi;
      // screen base attribute address MSB (odd) for next pulse
      r_va[0] <= 1'b1;
      // Output done
      vram_we <= 1'b0;
      // Increment nibble counter if (!null and pixel buffer just flushed)
      if (!nullch && pix4f) begin
      vram_a[7:0] <= vram_a[7:0] + 8'd1;
      pix4f <= 1'b0;
      end
    end

    // 3) Read SBA MSB
    // ---------------
    if (!sbar && clkcnt == 2'b01) begin
      // Z80 is not active, grab sba high
      hrs <= cdi[5];
      rev <= cdi[4];
      fls <= cdi[3];
      gry <= cdi[2];
      und <= cdi[1];
      sba[8] <= cdi[0];
      sbar <= 1'b1;
    end

    // 4) Set pixel data address
    // -------------------------
    if (sbar && clkcnt == 2'b10) begin
      // Z80 is active, data bus not to be used
      // pixel data address for next pulse
      r_va <= (!hrs) ?
        (sba[8:6] == 3'b111) ? {pb0[12:0], sba[5:0], slin[2:0]} // HRS=0; Lores0 (ROM)
        : {pb1[9:0], sba[8:0], slin[2:0]}                       // Lores1 (RAM)
      : (und && sba[8]) ? {pb3[10:0], sba[7:0], slin[2:0]}  // HRS=1; Hires1 (RAM)
        : {pb2[8:0], und, sba[8:0], slin[2:0]};                      // Hires0 (ROM)
    end

    // 5) Output pixel nibble
    // ----------------------
    if (sbar && clkcnt == 2'b00) begin
      // Z80 is not active, grab pixels and output first nibble
      if (!hrs || cursor) begin
        // LRS or cursor
        if (pix6f) begin
          // 2 pixels remaining in buffer, output them with 2 left pixels
          vram_do <= {pix6b[1:0], scr[5:4]};
          vram_we <= 1'b1;
          pix4b <= scr[3:0];
          pix4f <= 1'b1;
          pix6f <= 1'b0;
        end else begin
          // buffer empty, ouput 4 left pixels
          vram_do <= scr[5:2];
          vram_we <= 1'b1;
          pix6b[1:0] <= scr[1:0];
          pix4f <= 1'b0;
          pix6f <= 1'b1;
        end
      end else begin
        // HRS or null
        if (!nullch) begin
          // HRS, output first nibble, second in buffer
          vram_do <= scr[7:4];
          vram_we <= 1'b1;
          pix4b <= scr[3:0];
          pix4f <= 1'b1;
          pix6f <= 1'b0;
        end else begin
          // Null
          pix4f <= 1'b0;
          pix6f <= 1'b0;
        end
      end
    end

    // 6) Increment counters
    // -------------------------------------------
    if (sbar && clkcnt == 2'b01) begin
      // Next cycle read sba
      sbar <= 1'b0;
      // Output done
      vram_we <= 1'b0;
      // Increment line/column counters and nibble counter
      if (scol == 7'd107) begin
        scol <= 7'd0;
        vram_a[7:0] <= 8'd0;
        pix4f <= 1'b0;
        pix6f <= 1'b0;
        if (slin == 6'd63) begin
          vram_a[13:8] <= 6'd0;
          frame <= 1'b1; // frame flag for BMP output
        end else begin
          vram_a[13:8] <= vram_a[13:8] + 6'd1;
        end
      end else begin
        // Increment column
        scol <= scol + 1'b1;
        // Increment vram address if required
        if (!nullch) begin
          vram_a[7:0] <= vram_a[7:0] + 8'd1;
        end
      end
    end
  end
end

endmodule
