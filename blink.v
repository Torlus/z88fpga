module blink (
  // Outputs
  rout_n, cdo, wrb_n, ipce_n, irce_n, se1_n, se2_n, se3_n, ma, pm1,
  intb_n, nmib_n, roe_n,
  // Inputs
  ca, crd_n, cdi, mck, sck, rin_n, hlt_n, mrq_n, ior_n, cm1_n, kbmat,
  // Extra
  tick
  );

// Clocks
input           mck;      // 9.83MHz Master Clock
input           sck;      // 25.6KHz Standby Clock
output          pm1;      // Z80 clock driven by blink
input           tick;     // 5ms tick

// Reset
input           rin_n;    // Reset button
output          rout_n;   // Z80 reset

// Logical memory (16 bits Z80 address bus)
input   [15:0]  ca;       // Z80 address bus

// Physical memory (22 bits address bus)
output  [21:0]  ma;       // slot 0 (internal) to slot 3

// Data bus
input   [7:0]   cdi;
output  [7:0]   cdo;

// Control bus
input           hlt_n;    // HALT Coma/Standby command
input           crd_n;    // RD from Z80
input           cm1_n;    // M1 (=WR or =RFSH) from Z80
input           mrq_n;    // MREQ
input           ior_n;    // ior_nQ
output          ipce_n;   // Internal PROM Chip Enable
output          irce_n;   // Internal RAM Chip Enable
output          se1_n;    // Slot 1 select (CE)
output          se2_n;    // Slot 2 select (CE)
output          se3_n;    // Slot 3 select (CE)
// output          poe_n;    // OE refreshed during coma for dynamic RAM (all slots)
output          roe_n;    // OE for SRAM or ROM in Slot 0, 1, 2
// output          eoe_n;    // OE for EPROM programmer in Slot 3
output          wrb_n;    // WE (1=RD ; 0=WR)
output          nmib_n;   // NMI
output          intb_n;   // INT

// Cards, EPROM programmer, Battery and Speaker
// input           btl_n;    // Batt Low (<4.2V)
// input           flp;      // Flap open of slot connector
// input           sns_n;    // Sens Line for card insertion/removal and Batt <3.2V (induce NMI>>HLT)
// output          pgmb_n;   // PGM
// output          vpon;     // VPP
// output          spkr;     // Speaker

// LCD
// output   [3:0]  ldb;      // line data 0-3
// output          xscl;     // 300ns nibble pulse
// output          lp;       // 156us line pulse
// output          fr;       // 10ms frame reverse

// Serial port
// input           rxd;      // RX line
// input           cts;      // CTS handshaking
// input           dcd;      // DCD control
// output          txd;      // TX line
// output          rts;      // RTS handshaking

// Keyboard
input           kbmat;

// Reset
assign rout_n = rin_n;

// Clocks
assign pm1 = mck;

// General
reg     [7:0]   r_cdo;

// Common control register
reg     [7:0]   com;      // IO $B0
localparam
  com_lcdon   = 0,
  com_rams    = 2,
  com_restim  = 4;

// Bank switching (WR only)
reg     [7:0]   sr0;
reg     [7:0]   sr1;
reg     [7:0]   sr2;
reg     [7:0]   sr3;

assign ma =
  (ca[15:14] == 2'b11) ? { sr3, ca[13:0] }                // C000-FFFF
  :  (ca[15:14] == 2'b10) ? { sr2, ca[13:0] }             // 8000-BFFF
  :  (ca[15:14] == 2'b01) ? { sr1, ca[13:0] }             // 4000-7FFF
  :  (ca[15:13] == 3'b001) ? { sr0, 1'b1, ca[12:0] }      // 2000-3FFF
  :  (ca[15:13] == 3'b000) ?                              // 0000-1FFF
    (com[com_rams] == 1'b0) ?
    { 8'b00000000, 1'b0, ca[12:0] }                       // Bank $00 !RAMS
    : { 8'b00010000, 1'b0, ca[12:0] }                     // Bank $20 RAMS
  : 22'b11_1111_1111_1111_1111_1111;

assign ipce_n =
  (ma[21:19] == 3'b000 & !mrq_n) ? 1'b0 : 1'b1;

assign irce_n =
  (ma[21:19] == 3'b001 & !mrq_n) ? 1'b0 : 1'b1;

assign wrb_n = (!mrq_n & crd_n) ? 1'b0 : 1'b1;
assign roe_n = (!mrq_n & !crd_n) ? 1'b0 : 1'b1;
assign cdo = (!ior_n) ? r_cdo : cdi;

always @(posedge mck)
begin
  if (rin_n == 1'b0) begin
    com <= 8'b00000000;
  end else if (mck == 1'b1) begin
    if (!ior_n & crd_n) begin
      // IO register write
      case(ca[7:0])
        8'h70: pb0 <= {ca[12:8], cdi};
        8'h71: pb1 <= {ca[9:8], cdi};
        8'h72: pb2 <= {ca[8], cdi};
        8'h73: pb3 <= {ca[10:8], cdi};
        8'h74: sbr <= {ca[10:8], cdi};
        8'hB0: com <= cdi;
        8'hB1: int1 <= cdi;
        8'hB4: tack <= cdi[2:0];
        8'hB5: tmk <= cdi[2:0];
        8'hB6: ack <= cdi;
        8'hD0: sr0 <= cdi;
        8'hD1: sr1 <= cdi;
        8'hD2: sr2 <= cdi;
        8'hD3: sr3 <= cdi;
        default: ;
      endcase
    end else if (!ior_n & !crd_n) begin
      // IO register read
      case(ca[7:0])
        8'hB1: r_cdo <= sta;
        8'hB2: r_cdo <= kbd;
        8'hB5: r_cdo <= {5'b00000, tsta};
        8'hD0: r_cdo <= tim0;
        8'hD1: r_cdo <= {2'b00, tim1};
        8'hD2: r_cdo <= timm[7:0];
        8'hD3: r_cdo <= timm[15:8];
        8'hD4: r_cdo <= {3'b000, timm[20:16]};
        default: ;
      endcase
    end
  end
end

// Keyboard
reg     [63:0]  kbmat;
wire    [7:0]   kbcol[0:7];
wire    [7:0]   kbd;

assign kbcol[0] = ca[ 8] ? kbmat[ 7: 0] : 8'b00000000;
assign kbcol[1] = ca[ 9] ? kbmat[15: 8] : 8'b00000000;
assign kbcol[2] = ca[10] ? kbmat[23:16] : 8'b00000000;
assign kbcol[3] = ca[11] ? kbmat[31:24] : 8'b00000000;
assign kbcol[4] = ca[12] ? kbmat[39:32] : 8'b00000000;
assign kbcol[5] = ca[13] ? kbmat[47:40] : 8'b00000000;
assign kbcol[6] = ca[14] ? kbmat[55:48] : 8'b00000000;
assign kbcol[7] = ca[15] ? kbmat[63:56] : 8'b00000000;

assign kbd = kbcol[0] | kbcol[1] | kbcol[2] | kbcol[3]
  & kbcol[4] | kbcol[5] | kbcol[6] | kbcol[7];

// Display (WR only)
reg     [12:0]  pb0;  // Lores0 (RAM, 64 char, 512B)
reg     [9:0]   pb1;  // Lores1 (ROM, 448 char, 3.5K)
reg     [8:0]   pb2;  // Hires0 (RAM, 768 char, 6K)
reg     [10:0]  pb3;  // Hires1 (ROM, 256 char, 2K)
reg     [10:0]  sbr;  // Screen Base File (RAM, 128 attr*8, 2K)

// Interrupts
reg     [7:0]   int1; // Interrupt control (WR)
localparam
  int_gint    = 0,
  int_time    = 1;

reg     [7:0]   ack;  // Interrupt acknoledge (WR)
reg     [7:0]   sta;  // Interrupt status (RD)
localparam
  sta_time    = 1;

// Timer interrupts
reg     [2:0]   tack; // Timer interrupt acknowledge (WR)
localparam
  tack_tick   = 0,
  tack_sec    = 1,
  tack_min    = 2;

reg     [2:0]   tsta; // Timer interrupt status (RD)
localparam
  tsta_tick   = 0,
  tsta_sec    = 1,
  tsta_min    = 2;

reg     [2:0]   tmk;  // Timer interrupt mask (WR)
localparam
  tmk_tick    = 0,
  tmk_sec     = 1,
  tmk_min     = 2;

// Real Time Clock (RD)
reg     [7:0]   tim0; // 5ms ticks (0-199)
reg     [5:0]   tim1; // seconds (0-59)
reg     [20:0]  timm; // minutes (0-2^21)

always @(posedge tick)
begin
  if (com[com_restim]) begin
    com[com_restim] <= 1'b0;
    tim0 <= 8'h00;
    tim1 <= 6'h00;
    timm <= 21'h00;
  end else begin
    if (tim0 < 199) begin
      tim0 <= tim0 + 1'b1;
    end else if (tim0 >= 199) begin
      tim0 <= 8'h00;
      tim1 <= tim1 + 1'b1;
    end else if (tim1 >= 59) begin
      tim1 <= 6'h00;
      timm <= timm + 1'b1;
    end
  end
end

endmodule
