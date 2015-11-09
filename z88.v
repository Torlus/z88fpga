module z88 (
  // Outputs
  ram_a, ram_do, ram_ce_n, ram_oe_n, ram_we_n,
  rom_a, rom_ce_n, rom_oe_n,

  // Inputs
  clk, reset_n,
  ps2clk, ps2dat,
  ram_di,
  rom_do
);

// Clocks and Reset
input           clk;
input           reset_n;

// PS/2
input           ps2clk;
input           ps2dat;

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
wire            z88_int_n;
wire            z88_nmi_n;
wire            z88_busrq_n;
wire    [21:0]  z88_ma;
wire    [15:0]  z88_ca;
wire    [7:0]   z88_cdo;
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
  .clk(z88_pm1),
  .wait_n(1'b1),                // not wired
  .int_n(z88_int_n),
  .nmi_n(z88_nmi_n),
  .busrq_n(1'b1),               // not wired
  .di(z88_cdo)
);

assign z88_nmi_n = 1'b1;

assign z88_reset_n = reset_n;

// Blink instance
blink theblink (
  .rout_n(z88_rout_n),
  .rin_n(z88_reset_n),
  .mck(z88_mck),
  .sck(z88_sck),
  .pm1(z88_pm1),
  .cdi(z88_cdi),
  .cdo(z88_cdo),
  .ca(z88_ca),
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
  .kbmat(z88_kbmat)
);

// Internal RAM (Slot 0)
assign ram_a = z88_ma[18:0];
assign ram_di = z88_cdo;
assign ram_we_n = z88_wrb_n;
assign ram_oe_n = z88_roe_n;
assign ram_ce_n = z88_irce_n;

// Internal ROM (Slot 0)
assign rom_a = z88_ma[18:0];
assign rom_oe_n = z88_roe_n;
assign rom_ce_n = z88_ipce_n;

assign z88_cdi = (!z88_ipce_n & !z88_roe_n) ? rom_do
                : (!z88_irce_n & !z88_roe_n) ? ram_do
                : (!z88_iorq_n & z88_rd_n) ? z80_do
                : (!z88_mreq_n & z88_rd_n) ? z80_do
                : 8'b11111111;

// PS/2 keyboard
ps2 ps2kb (
  .reset_n(z88_rout_n),
  .ps2clk(ps2clk),
  .ps2dat(ps2dat),
  .kbmat_out(z88_kbmat)
);

endmodule
