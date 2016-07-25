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
output  [12:0]  o_vram_a;
output  [7:0]   o_vram_do;
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
reg     [13:0]  spix;  // pixel shift register
reg     [2:0]   npix;  // number of pixels in buffer

reg     [12:0]  vram_a;
// reg  [3:0]   vram_do;
reg             vram_we;
reg             frame;
reg     [7:0]   vrdo;
assign o_vram_do = vrdo;

// For Quartus
assign o_vram_a = vram_a;
// assign o_vram_do = vram_do;
assign o_vram_we = vram_we;
assign o_frame = frame;
assign va = r_va;

// Shortcuts
wire    [5:0]   slin;       // screen line (64)
wire            cursor;     // lores cursor header
wire            nullch;     // do not increment nibble counter
assign slin = vram_a[12:7]; // Counter in VRAM_A
assign cursor = hrs & rev & fls;
assign nullch = hrs & rev & !fls & gry;

// Screen effects
wire [7:0] rot_e;
wire [7:0] und_e;
wire [7:0] rev_e;
wire [7:0] gry_e;
wire [7:0] scr;
// Rotate bits
assign rot_e = {cdi[0],cdi[1],cdi[2],cdi[3],cdi[4],cdi[5],cdi[6],cdi[7]};
// Underline, full line if lores and eighth line
assign und_e = (und && !hrs && slin[2:0] == 3'b111) ? 8'b11111111 : rot_e;
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
    spix <= 14'b0;
    npix <= 3'b0;
    vram_a <= 12'd0;
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

      // Output to VRAM done
      vram_we <= 1'b0;            // write to vram done
      if (npix[2]) begin          // 8 pixels or more in buffer
        npix[2] <= 1'b0;          // 8 pixels less in buffer
        vram_a[6:0] <= vram_a[6:0] + 7'd1; // inc byte displayed
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
    end

    // 3) Read SBA MSB
    // ---------------
    if (!sbar && clkcnt == 2'b01) begin
      // Z80 is not active, grab sba high (bit 6 and 7 unused for hardware)
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
      : (und && sba[8]) ? {pb3[10:0], sba[7:0], slin[2:0]}      // HRS=1; Hires1 (RAM)
        : {pb2[8:0], und, sba[8:0], slin[2:0]};                 // Hires0 (ROM)
    end

    // 5) Apply effects, shift pixels in buffer
    // ----------------------------------------
    if (sbar && clkcnt == 2'b00) begin
      // Z80 is not active, grab pixels and output first nibble
      if (!hrs || cursor) begin
        // LRS or cursor
        spix <= {scr[7:2],spix[13:6]};
        npix <= npix + 3'd3; // 6 pixels shifted to buffer
      end else begin
        // HRS or null
        if (!nullch) begin
          // HRS
          spix <= {scr[7:0],spix[13:8]};
          npix <= npix + 3'd4; // 8 pixels shifted to buffer
        end
      end
    end

    // 6) Output buffer and Increment counters
    // ---------------------------------------
    if (sbar && clkcnt == 2'b01) begin
      // Next cycle read sba
      sbar <= 1'b0;

      // Output
      vram_we <= 1'b1;  // write to vram
      if (npix == 3'd4) begin vrdo <= spix[13:6]; end
      if (npix == 3'd5) begin vrdo <= spix[11:4]; end
      if (npix == 3'd6) begin vrdo <= spix[9:2]; end
      if (npix == 3'd7) begin vrdo <= spix[7:0]; end

      // Increment line/column counters
      if (scol == 7'd107) begin
        scol <= 7'd0;
        vram_a[6:0] <= 7'd0;
        spix <= 14'b0;
        npix <= 3'b0;
        if (slin == 6'd63) begin
          vram_a[12:7] <= 6'd0;
          frame <= 1'b1; // frame flag for BMP output
        end else begin
          vram_a[12:7] <= vram_a[12:7] + 6'd1; // slin++
        end
      end else begin
        // Increment screen column
        scol <= scol + 1'b1;
      end
    end
  end
end

endmodule
