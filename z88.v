module z88 (
  // Outputs
  ram_a, ram_do, ram_ce_n, ram_oe_n, ram_we_n,
  rom_a, rom_ce_n, rom_oe_n,

  // Inputs
  clk, reset_n,
  ram_di,
  rom_di
);

// Clock and Reset
input           clk;
input           reset_n;

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

wire    [21:0]  z80_a_full;
wire            z80_romsel;
wire            z80_ramsel;

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

assign z80_reset_n = reset_n;
assign z80_clk = clk;
assign z80_wait_n = 1'b1;
assign z80_int_n = 1'b1;
assign z80_nmi_n = 1'b1;
assign z80_busrq_n = 1'b1;

assign z80_a_full =
  (z80_a[15:14] == 2'b11) ? { sr3, z80_a[13:0] }
  :  (z80_a[15:14] == 2'b10) ? { sr2, z80_a[13:0] }
  :  (z80_a[15:14] == 2'b01) ? { sr1, z80_a[13:0] }
  :  (z80_a[15:13] == 3'b001) ? { sr0, 1'b1, z80_a[12:0] }
  :  (z80_a[15:13] == 3'b000) ?
    (com[2] == 1'b0) ? { 8'b00000000, 1'b0, z80_a[12:0] }
    : { 8'b00010000, 1'b0, z80_a[12:0] }
  : 22'b11_1111_1111_1111_1111_1111;

assign z80_romsel =
  (z80_a_full[21:19] == 3'b000) ? 1'b1 : 1'b0;

assign z80_ramsel =
  (z80_a_full[21:19] == 3'b001) ? 1'b1 : 1'b0;


assign ram_a = z80_a_full[18:0];
assign ram_do = z80_do;
assign ram_we_n = (!z80_mreq_n & !z80_wr_n) ? 1'b0 : 1'b1;
assign ram_oe_n = (!z80_mreq_n & !z80_rd_n) ? 1'b0 : 1'b1;
assign ram_ce_n = (!z80_mreq_n & z80_ramsel) ? 1'b0 : 1'b1;

assign rom_a = z80_a_full[18:0];
assign rom_oe_n = (!z80_mreq_n & !z80_rd_n) ? 1'b0 : 1'b1;
assign rom_ce_n = (!z80_mreq_n & z80_romsel) ? 1'b0 : 1'b1;

assign z80_di =
  z80_romsel ? rom_di
  : z80_ramsel ? ram_di
  : 8'b11111111;

always @(posedge clk)
begin
  if (reset_n == 1'b0) begin
    com <= 8'b00000000;
  end else if (clk == 1'b1) begin
    if (!z80_iorq_n & !z80_wr_n) begin
      // IO register write
      case(z80_a[7:0])
        8'hB0: com <= z80_do;
        default: ;
      endcase
    end else if (!z80_iorq_n & !z80_rd_n) begin
      // IO register read
    end
  end
end

endmodule
