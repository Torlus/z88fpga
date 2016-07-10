module z88_de1 (
  SW, HEX0, HEX1, HEX2, HEX3,
  KEY, LEDR, LEDG,
  CLOCK_24, CLOCK_27, CLOCK_50, EXT_CLOCK,
  FL_ADDR, FL_DQ, FL_CE_N, FL_OE_N, FL_RST_N, FL_WE_N,
  SRAM_ADDR, SRAM_CE_N,	SRAM_DQ, SRAM_LB_N, SRAM_OE_N, SRAM_UB_N, SRAM_WE_N,
  VGA_R, VGA_G, VGA_B, VGA_VS, VGA_HS,
  PS2_CLK, PS2_DAT
);

input [9:0] SW;

output  [6:0] HEX0;
output  [6:0] HEX1;
output  [6:0] HEX2;
output  [6:0] HEX3;

input   [3:0] KEY;

output  [9:0] LEDR;
output  [7:0] LEDG;

input   [1:0] CLOCK_27;
input   [1:0] CLOCK_24;
input         CLOCK_50;
input         EXT_CLOCK;

output        PS2_CLK;
input         PS2_DAT;

output  [3:0] VGA_R;
output  [3:0] VGA_G;
output  [3:0] VGA_B;
output        VGA_HS;
output        VGA_VS;

output  [21:0]  FL_ADDR;
inout   [7:0]   FL_DQ;
output        FL_OE_N;
output        FL_RST_N;
output        FL_WE_N;
output        FL_CE_N;


output  [17:0]  SRAM_ADDR;
output        SRAM_CE_N;
inout   [15:0]  SRAM_DQ;
output        SRAM_LB_N;
output        SRAM_OE_N;
output        SRAM_UB_N;
output        SRAM_WE_N;

// Clocks, Reset switch, Flap switch
wire           clk;
wire           reset_n;
wire           flap;  // normaly closed =0, open =1
wire           t_1s;

// PS/2
wire           ps2clk;
wire           ps2dat;
wire [7:0]     ps2key;


// VGA
wire          href;
wire          vsync;
wire  [11:0]  rgb;

// Internal RAM
wire  [18:0]  ram_a;
wire  [7:0]   ram_di;
wire  [7:0]   ram_do;
wire          ram_ce_n;
wire          ram_oe_n;
wire          ram_we_n;

// Internal ROM
wire  [18:0]  rom_a;
wire  [7:0]   rom_do;
wire          rom_ce_n;
wire          rom_oe_n;

// Dual-port VRAM
wire  [13:0]  vram_wp_a;
wire          vram_wp_we;
wire  [3:0]   vram_wp_di;

wire  [13:0]  vram_rp_a;
wire   [3:0]  vram_rp_do;

wire          clk25;

assign  reset_n = SW[0];
assign  flap = SW[1];

reg [6:0] r_hex0;
reg [6:0] r_hex1;

always @(posedge ps2clk)
begin
    case (ps2key[7:4])
        4'b0000 : r_hex1 <= 7'b1111110;
        4'b0001 : r_hex1 <= 7'b0110000;
        4'b0010 : r_hex1 <= 7'b1101101;
        4'b0011 : r_hex1 <= 7'b1111001;
        4'b0100 : r_hex1 <= 7'b0110011;
        4'b0101 : r_hex1 <= 7'b1011011;
        4'b0110 : r_hex1 <= 7'b1011111;
        4'b0111 : r_hex1 <= 7'b1110000;
        4'b1000 : r_hex1 <= 7'b1111111;
        4'b1001 : r_hex1 <= 7'b1111011;
        4'b1010 : r_hex1 <= 7'b1110111;
        4'b1011 : r_hex1 <= 7'b0011111;
        4'b1100 : r_hex1 <= 7'b1001110;
        4'b1101 : r_hex1 <= 7'b0111101;
        4'b1110 : r_hex1 <= 7'b1001111;
        4'b1111 : r_hex1 <= 7'b1000111;
     endcase
     case (ps2key[3:0])
         4'b0000 : r_hex0 <= 7'b1111110;
         4'b0001 : r_hex0 <= 7'b0110000;
         4'b0010 : r_hex0 <= 7'b1101101;
         4'b0011 : r_hex0 <= 7'b1111001;
         4'b0100 : r_hex0 <= 7'b0110011;
         4'b0101 : r_hex0 <= 7'b1011011;
         4'b0110 : r_hex0 <= 7'b1011111;
         4'b0111 : r_hex0 <= 7'b1110000;
         4'b1000 : r_hex0 <= 7'b1111111;
         4'b1001 : r_hex0 <= 7'b1111011;
         4'b1010 : r_hex0 <= 7'b1110111;
         4'b1011 : r_hex0 <= 7'b0011111;
         4'b1100 : r_hex0 <= 7'b1001110;
         4'b1101 : r_hex0 <= 7'b0111101;
         4'b1110 : r_hex0 <= 7'b1001111;
         4'b1111 : r_hex0 <= 7'b1000111;
      endcase
end

assign  HEX0 = r_hex0;
assign  HEX1 = r_hex1;
assign  HEX2 = 7'd0;
assign  HEX3 = 7'd0;

assign  LEDR = SW[9:0];
assign  LEDG = {t_1s, 5'd0, flap, reset_n};

assign  PS2_CLK = ps2clk;
assign  ps2dat = PS2_DAT;

assign  VGA_HS = href;
assign  VGA_VS = vsync;
assign  VGA_R = rgb[3:0];
assign  VGA_G = rgb[7:4];
assign  VGA_B = rgb[11:8];

assign  FL_ADDR = { 3'b0, rom_a[18:0] };
assign  FL_OE_N = rom_oe_n;
assign  FL_CE_N = rom_ce_n;
assign  FL_RST_N = 1'b1;
assign  FL_WE_N = 1'b1;
assign  rom_do = FL_DQ;
assign  FL_DQ = 8'bZZZZZZZZ;


assign  SRAM_ADDR[17:0] = ram_a[18:1];
assign  SRAM_UB_N = (ram_a[0] == 1'b0) ? 1'b1 : 1'b0;
assign  SRAM_LB_N = (ram_a[0] == 1'b0) ? 1'b0 : 1'b1;
assign  SRAM_CE_N = ram_ce_n;
assign  SRAM_OE_N = ram_oe_n;
assign  SRAM_WE_N = ram_we_n;

assign  ram_do = (ram_a[0] == 1'b0) ? SRAM_DQ[7:0] : SRAM_DQ[15:8];
assign  SRAM_DQ = (!ram_we_n) ? { ram_di, ram_di } : 16'bZZZZZZZZ_ZZZZZZZZ;

z88_de1_pll pll (
  .inclk0(CLOCK_50),
  .c0(clk25),
  .c1(clk)
);

// ps2clk = 10MHz/512 = 19.5KHz
reg   [8:0] clk20k;
always @(posedge clk)
begin
  clk20k <= clk20k + 9'd1;
end
assign ps2clk = clk20k[8];

vram video (
  .data(vram_wp_di),
  .rdaddress(vram_rp_a),
  .rdclock(clk25),
  .wraddress(vram_wp_a),
  .wrclock(clk),
  .wren(vram_wp_we),
  .q(vram_rp_do),
);


z88 z88de1 (
  .ram_a(ram_a),
  .ram_di(ram_di),
  .ram_ce_n(ram_ce_n),
  .ram_oe_n(ram_oe_n),
  .ram_we_n(ram_we_n),

  .rom_a(rom_a),
  .rom_ce_n(rom_ce_n),
  .rom_oe_n(rom_oe_n),

  .vram_wp_a(vram_wp_a),
  .vram_wp_we(vram_wp_we),
  .vram_wp_di(vram_wp_di),
  .vram_rp_a(vram_rp_a),

  .clk25(clk25),
  .href(href),
  .vsync(vsync),
  .rgb(rgb),
  .frame(),
  .t_1s(t_1s),

  .clk(clk),
  .reset_n(reset_n),
  .ps2clk(ps2clk),
  .ps2dat(ps2dat),
  .ps2key(ps2key),
  .ram_do(ram_do),
  .rom_do(rom_do),
  .vram_rp_do(vram_rp_do),
  .flap(flap)
);

endmodule
