module z88 (
  // Outputs
  ram_a, ram_di, ram_ce_n, ram_oe_n, ram_we_n,
  rom_a, rom_ce_n, rom_oe_n,
  vram_wp_a, vram_wp_we, vram_wp_di,
  vram_rp_a,
  href, vsync, rgb,
  frame,

  // Inputs
  clk, reset_n,
  ps2clk, ps2dat,
  ram_do,
  rom_do,
  vram_rp_do,
  flap
);

// BMP debug output
output          frame;

// Clocks, Reset switch, Flap switch
input           clk;
input           reset_n;
input           flap;  // normaly closed =0, open =1

// PS/2
input           ps2clk;
input           ps2dat;

// VGA
output          href;
output          vsync;
output  [11:0]  rgb;

// Internal RAM
output  [18:0]  ram_a;
output  [7:0]   ram_di;
input   [7:0]   ram_do;
output          ram_ce_n;
output          ram_oe_n;
output          ram_we_n;

// Internal ROM
output  [18:0]  rom_a;
input   [7:0]   rom_do;
output          rom_ce_n;
output          rom_oe_n;

// Dual-port VRAM
output  [13:0]  vram_wp_a;
output          vram_wp_we;
output  [3:0]   vram_wp_di;

output  [13:0]  vram_rp_a;
input   [3:0]   vram_rp_do;

// Z80
wire    [7:0]   z80_do;

// Z88 PCB glue
wire            z88_mck;      // master clock
wire            z88_sck;      // standby clock
wire            z88_pm1;      // Z80 clock
wire            z88_m1_n;
wire            z88_mreq_n;
wire            z88_iorq_n;
wire            z88_rd_n;
wire            z88_halt_n;
wire            z88_reset_n;
wire            z88_flap;
wire            z88_int_n;
wire            z88_nmi_n;
wire            z88_busrq_n;
wire    [21:0]  z88_ma;
wire    [15:0]  z88_ca;
wire    [7:0]   z80_cdi;
wire    [7:0]   vid_cdi;
wire    [7:0]   z88_cdi;
wire            z88_ipce_n;
wire            z88_irce_n;
wire            z88_se1_n;
wire            z88_se2_n;
wire            z88_se3_n;
wire            z88_roe_n;
wire            z88_wrb_n;
wire            z88_rin_n;
wire            z88_rout_n;
wire    [63:0]  z88_kbmat;
wire            z88_lcdon;
wire    [12:0]  z88_pb0;
wire    [9:0]   z88_pb1;
wire    [8:0]   z88_pb2;
wire    [10:0]  z88_pb3;
wire    [10:0]  z88_sbr;
wire    [1:0]   z88_clkcnt;
wire    [21:0]  z88_va;
wire            z88_t1s;
wire            z88_t5ms;

// Clocks
assign z88_mck = clk;

// Z80 instance
tv80s z80 (
  .m1_n(z88_m1_n),
  .mreq_n(z88_mreq_n),
  .iorq_n(z88_iorq_n),
  .rd_n(z88_rd_n),
  .wr_n(),                  // not wired
  .rfsh_n(),                // not wired
  .halt_n(z88_halt_n),
  .busak_n(),               // not wired
  .A(z88_ca),
  .dout(z80_do),
  .reset_n(z88_rout_n),
  .clk(clk),
  .wait_n(1'b1),            // not wired
  .int_n(z88_int_n),
  .nmi_n(z88_nmi_n),
  .busrq_n(1'b1),           // not wired
  .di(z80_cdi),
  .cen(z88_pm1)
);

assign z88_nmi_n = 1'b1;

assign z88_reset_n = reset_n;

// Blink instance
blink theblink (
  .rout_n(z88_rout_n),
  .rin_n(z88_reset_n),
  .flp(z88_flap),
  .mck(z88_mck),
  .sck(z88_sck),
  .pm1(z88_pm1),
  .cdi(z88_cdi),
  .z80_cdo(z80_cdi),
  .vid_cdo(vid_cdi),
  .ca(z88_ca),
  .va(z88_va),
  .ma(z88_ma),
  .hlt_n(z88_halt_n),
  .nmib_n(z88_nmi_n),
  .intb_n(z88_int_n),
  .ior_n(z88_iorq_n),
  .mrq_n(z88_mreq_n),
  .cm1_n(z88_m1_n),
  .crd_n(z88_rd_n),
  .wrb_n(z88_wrb_n),
  .roe_n(z88_roe_n),
  .ipce_n(z88_ipce_n),
  .irce_n(z88_irce_n),
  .se1_n(z88_se1_n),
  .se2_n(z88_se2_n),
  .se3_n(z88_se3_n),
  .kbmat(z88_kbmat),
  .lcdon(z88_lcdon),
  .pb0w(z88_pb0),
  .pb1w(z88_pb1),
  .pb2w(z88_pb2),
  .pb3w(z88_pb3),
  .sbrw(z88_sbr),
  .clkcnt(z88_clkcnt),
  .t_1s(z88_t1s),
  .t_5ms(z88_t5ms)
);

// Screen instance
screen thescreen (
  .mck(z88_mck),
  .clkcnt(z88_clkcnt),
  .rin_n(z88_reset_n),
  .lcdon(z88_lcdon),
  .cdi(vid_cdi),
  .pb0(z88_pb0),
  .pb1(z88_pb1),
  .pb2(z88_pb2),
  .pb3(z88_pb3),
  .sbr(z88_sbr),
  .va(z88_va),
  .vram_a(vram_wp_a),
  .vram_do(vram_wp_di),
  .vram_we(vram_wp_we),
  .t_1s(z88_t1s),
  .t_5ms(z88_t5ms),
  .frame(frame)
);

// Internal RAM (Slot 0)
assign ram_a = z88_ma[18:0];
assign ram_di = z80_do;
assign ram_we_n = z88_wrb_n;
assign ram_oe_n = z88_roe_n;
assign ram_ce_n = z88_irce_n;

// Internal ROM (Slot 0)
assign rom_a = z88_ma[18:0];
assign rom_oe_n = z88_roe_n;
assign rom_ce_n = z88_ipce_n;

assign z88_cdi = (!z88_ipce_n && !z88_roe_n) ? rom_do
                : (!z88_irce_n & !z88_roe_n) ? ram_do
                : (!z88_iorq_n & z88_rd_n) ? z80_do
                : (!z88_mreq_n & z88_rd_n) ? z80_do
                : 8'b11111111;

// PS/2 keyboard
ps2 theps2 (
  .reset_n(z88_rout_n),
  .ps2clk(ps2clk),
  .ps2dat(ps2dat),
  .kbmat_out(z88_kbmat)
);

// VGA output
vga thevga (
  .clk25(clk),            // /!\ 25.175MHz clock
  .reset_n(z88_rout_n),
  .lcdon(z88_lcdon),
  .vram_a(vram_rp_a),
  .vram_di(vram_rp_do),
  .href(href),
  .vsync(vsync),
  .rgb(rgb)
  );

endmodule
