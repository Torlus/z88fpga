module z88 (
  // Outputs
  ram_a, ram_do, ram_ce_n, ram_oe_n, ram_we_n,
  rom_a, rom_ce_n, rom_oe_n,

  // Inputs
  clk, reset_n,
  ps2clk, ps2dat,
  ram_di,
  rom_di
);

// Clock and Reset
input           clk;
input           reset_n;

// PS/2
input           ps2clk;
input           ps2dat;

// RAM
output  [18:0]  ram_a;
output  [7:0]   ram_do;
input   [7:0]   ram_di;
output          ram_ce_n;
output          ram_oe_n;
output          ram_we_n;

// ROM
output  [18:0]  rom_a;
input   [7:0]   rom_di;
output          rom_ce_n;
output          rom_oe_n;

// Z80
wire            z80_m1_n;
wire            z80_mreq_n;
wire            z80_iorq_n;
wire            z80_rd_n;
wire            z80_wr_n;
wire            z80_halt_n;
wire            z80_busak_n;
wire    [15:0]  z80_a;
wire    [7:0]   z80_do;
wire            z80_reset_n;
wire            z80_clk;
wire            z80_wait_n;
wire            z80_int_n;
wire            z80_nmi_n;
wire            z80_busrq_n;
wire    [7:0]   z80_di;

// Blink
reg     [7:0]   com;    // IO $B0
`define RAMS 2
reg     [7:0]   sr0;
reg     [7:0]   sr1;
reg     [7:0]   sr2;
reg     [7:0]   sr3;

wire    [21:0]  bl_a;
wire            bl_ipce;
wire            bl_irce;

reg     [7:0]   ioport_do;

reg     [63:0]  kbmat;
wire    [7:0]   kbcol[0:7];
wire    [7:0]   kbd;

assign kbcol[0] = z80_a[ 8] ? kbmat[ 7: 0] : 8'b00000000;
assign kbcol[1] = z80_a[ 9] ? kbmat[15: 8] : 8'b00000000;
assign kbcol[2] = z80_a[10] ? kbmat[23:16] : 8'b00000000;
assign kbcol[3] = z80_a[11] ? kbmat[31:24] : 8'b00000000;
assign kbcol[4] = z80_a[12] ? kbmat[39:32] : 8'b00000000;
assign kbcol[5] = z80_a[13] ? kbmat[47:40] : 8'b00000000;
assign kbcol[6] = z80_a[14] ? kbmat[55:48] : 8'b00000000;
assign kbcol[7] = z80_a[15] ? kbmat[63:56] : 8'b00000000;

assign kbd = kbcol[0] | kbcol[1] | kbcol[2] | kbcol[3]
  & kbcol[4] | kbcol[5] | kbcol[6] | kbcol[7];

reg     [12:0]  pb0;  // Lores0 (RAM, 64 char, 512B)
reg     [9:0]   pb1;  // Lores1 (ROM, 448 char, 3.5K)
reg     [8:0]   pb2;  // Hires0 (RAM, 768 char, 6K)
reg     [10:0]  pb3;  // Hires1 (ROM, 256 char, 2K)
reg     [10:0]  sbr;  // Screen Base File (RAM, 128 attr*8, 2K)

// Z80 instance
tv80s z80 (
  .m1_n(z80_m1_n),
  .mreq_n(z80_mreq_n),
  .iorq_n(z80_iorq_n),
  .rd_n(z80_rd_n),
  .wr_n(z80_wr_n),
  .rfsh_n(),
  .halt_n(z80_halt_n),
  .busak_n(z80_busak_n),
  .A(z80_a),
  .dout(z80_do),
  .reset_n(z80_reset_n),
  .clk(z80_clk),
  .wait_n(z80_wait_n),
  .int_n(z80_int_n),
  .nmi_n(z80_nmi_n),
  .busrq_n(z80_busrq_n),
  .di(z80_di)
);

// PS/2 keyboard
ps2 ps2kb (
  .reset_n(reset_n),
  .ps2clk(ps2clk),
  .ps2dat(ps2dat),
  .kbmat_out(kbmat)
);

assign z80_reset_n = reset_n;
assign z80_clk = clk;
assign z80_wait_n = 1'b1;
assign z80_int_n = 1'b1;
assign z80_nmi_n = 1'b1;
assign z80_busrq_n = 1'b1;

assign bl_a =
  (z80_a[15:14] == 2'b11) ? { sr3, z80_a[13:0] }
  :  (z80_a[15:14] == 2'b10) ? { sr2, z80_a[13:0] }
  :  (z80_a[15:14] == 2'b01) ? { sr1, z80_a[13:0] }
  :  (z80_a[15:13] == 3'b001) ? { sr0, 1'b1, z80_a[12:0] }
  :  (z80_a[15:13] == 3'b000) ?
    (com[2] == 1'b0) ? { 8'b00000000, 1'b0, z80_a[12:0] }
    : { 8'b00010000, 1'b0, z80_a[12:0] }
  : 22'b11_1111_1111_1111_1111_1111;

assign bl_ipce =
  (bl_a[21:19] == 3'b000) ? 1'b1 : 1'b0;

assign bl_irce =
  (bl_a[21:19] == 3'b001) ? 1'b1 : 1'b0;


assign ram_a = bl_a[18:0];
assign ram_do = z80_do;
assign ram_we_n = (!z80_mreq_n & !z80_wr_n) ? 1'b0 : 1'b1;
assign ram_oe_n = (!z80_mreq_n & !z80_rd_n) ? 1'b0 : 1'b1;
assign ram_ce_n = (!z80_mreq_n & bl_irce) ? 1'b0 : 1'b1;

assign rom_a = bl_a[18:0];
assign rom_oe_n = (!z80_mreq_n & !z80_rd_n) ? 1'b0 : 1'b1;
assign rom_ce_n = (!z80_mreq_n & bl_ipce) ? 1'b0 : 1'b1;

assign z80_di =
  !z80_iorq_n ? ioport_do
  : bl_ipce ? rom_di
  : bl_irce ? ram_di
  : 8'b11111111;

always @(posedge clk)
begin
  if (reset_n == 1'b0) begin
    com <= 8'b00000000;
  end else if (clk == 1'b1) begin
    if (!z80_iorq_n & !z80_wr_n) begin
      // IO register write
      case(z80_a[7:0])
        8'h70: pb0 <= {z80_a[12:8], z80_do};
        8'h71: pb1 <= {z80_a[9:8], z80_do};
        8'h72: pb2 <= {z80_a[8], z80_do};
        8'h73: pb3 <= {z80_a[10:8], z80_do};
        8'h74: sbr <= {z80_a[10:8], z80_do};
        8'hB0: com <= z80_do;
        8'hD0: sr0 <= z80_do;
        8'hD1: sr1 <= z80_do;
        8'hD2: sr2 <= z80_do;
        8'hD3: sr3 <= z80_do;
        default: ;
      endcase
    end else if (!z80_iorq_n & !z80_rd_n) begin
      // IO register read
      case(z80_a[7:0])
        8'hB2: ioport_do <= kbd;
        8'hD0: ioport_do <= sr0;
        8'hD1: ioport_do <= sr1;
        8'hD2: ioport_do <= sr2;
        8'hD3: ioport_do <= sr3;
        default: ;
      endcase
    end
  end
end

endmodule
