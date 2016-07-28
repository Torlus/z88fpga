module blink (
  // Outputs
  rout_n, z80_cdo, vid_cdo, wrb_n, ipce_n, irce_n, se1_n, se2_n, se3_n, ma, pm1,
  intb_n, nmib_n, roe_n,
  lcdon, pb0w, pb1w, pb2w, pb3w, sbrw, clkcnt,
  t_1s, t_5ms, pm1s, kbds,
  //Debug
  kbdval, key,
  // Inputs
  ca, va, crd_n, cdi, mck, sck, rin_n, flp, hlt_n, mrq_n, ior_n, cm1_n, kbmat
);

// Debug
output  [7:0]   kbdval;
output          pm1s;
output          kbds;
output          key;

// Clocks
input           mck;      // 9.83MHz Master Clock
input           sck;      // 25.6KHz Standby Clock
output          pm1;      // Z80 clock driven by blink
output  [1:0]   clkcnt;
output          t_1s;     // 1s for cursor, flash effect
output          t_5ms;    // 5ms for grey effect

// Reset
input           rin_n;    // Reset button
output          rout_n;   // Z80 reset

// Flap
input           flp;      // Flap switch (high if opened for card insertion or hard reset)

// Logical memory (16 bits Z80 address bus)
input   [15:0]  ca;       // Z80 address bus

// Physical memory (22 bits address bus)
output  [21:0]  ma;       // slot 0 (internal) to slot 3

// Video address
input   [21:0]  va;

// Data bus
input   [7:0]   cdi;
output  [7:0]   z80_cdo;
output  [7:0]   vid_cdo;

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
input   [63:0]     kbmat;

// Screen
output          lcdon;
output  [12:0]  pb0w;
output  [9:0]   pb1w;
output  [8:0]   pb2w;
output  [10:0]  pb3w;
output  [10:0]  sbrw;

assign se1_n = 1'b1;
assign se2_n = 1'b1;
assign se3_n = 1'b1;

// Reset
assign rout_n = rin_n;

wire    [21:0]  za;
reg     [7:0]   r_cdi;

wire    [21:0]  w_ma;
assign ma = w_ma;

// Z80 Clock (PM1)
reg   [1:0]   z80_clkcnt;
reg           z80_clk;
always @(posedge mck)
begin
  if (!rin_n) begin
    z80_clkcnt <= 2'b00;
    z80_clk <= 1'b0;
  end else begin
    z80_clkcnt <= z80_clkcnt + 2'd1;
    z80_clk <= 1'b0;
    if (z80_clkcnt == 2'b10) begin
      z80_clkcnt <= 2'b00;
      z80_clk <= 1'b1;
    end
  end
end

assign clkcnt = z80_clkcnt;

assign pm1 = (pm1s) ? z80_clk : 1'b0; // Halt stops CPU, Int low restarts.

// General
reg     [15:0]  tck;  // tick counter
wire            pm1s; // Z80 clock switch
assign pm1s = 1'b1;
reg     [7:0]   r_cdo; // I/O Port read buffer

// Common control register
reg     [7:0]   com;      // IO $B0

// Bank switching (WR only)
reg     [7:0]   sr0;
reg     [7:0]   sr1;
reg     [7:0]   sr2;
reg     [7:0]   sr3;

// Screen
reg     [12:0]  pb0;  // Lores0 (RAM, 64 char, 512B)
reg     [9:0]   pb1;  // Lores1 (ROM, 448 char, 3.5K)
reg     [8:0]   pb2;  // Hires0 (RAM, 768 char, 6K)
reg     [10:0]  pb3;  // Hires1 (ROM, 256 char, 2K)
reg     [10:0]  sbr;  // Screen Base File (RAM, 128 attr*8, 2K)

wire            lcdon;
wire    [12:0]  pb0w;
wire    [9:0]   pb1w;
wire    [8:0]   pb2w;
wire    [10:0]  pb3w;
wire    [10:0]  sbrw;

assign  lcdon = com[0];
assign  pb0w = pb0;
assign  pb1w = pb1;
assign  pb2w = pb2;
assign  pb3w = pb3;
assign  sbrw = sbr;

// Interrupts
reg     [6:0]   int1; // Interrupt control (WR)
//wire            int7; // int1[7] = KWAIT (WR)
wire    [7:0]   sta;  // Interrupt status (RD)


// Timer interrupts
wire    [2:0]   tsta; // Timer interrupt status (RD)
reg     [2:0]   tmk;  // Timer interrupt mask (WR)

// Real Time Clock (RD)
reg     [7:0]   tim0; // 5ms ticks (0-199)
reg     [5:0]   tim1; // seconds (0-59)
reg     [20:0]  timm; // minutes (0-2^21)

// Memory addressing
assign za =
  (ca[15:14] == 2'b11) ? { sr3, ca[13:0] }                // C000-FFFF
  :  (ca[15:14] == 2'b10) ? { sr2, ca[13:0] }             // 8000-BFFF
  :  (ca[15:14] == 2'b01) ? { sr1, ca[13:0] }             // 4000-7FFF
  :  (ca[15:13] == 3'b001) ? { sr0, 1'b1, ca[12:0] }      // 2000-3FFF
  :  (ca[15:13] == 3'b000) ? { 2'b00, com[2], 6'b0, ca[12:0] } // 0000-1FFF : Bank $00 !RAMS, Bank $20 RAMS
  : 22'b11_1111_1111_1111_1111_1111;

// Z80 Access Cycle
wire zac;
assign zac = (z80_clkcnt == 2'd2);

assign w_ma = zac ? za : va;

// Control bus
assign ipce_n =
  (w_ma[21:19] == 3'b000 & !mrq_n & zac) ? 1'b0
  : (w_ma[21:19] == 3'b000 & !zac) ? 1'b0 : 1'b1;

assign irce_n =
  (w_ma[21:19] == 3'b001 & !mrq_n & zac) ? 1'b0
  : (w_ma[21:19] == 3'b001 & !zac) ? 1'b0 : 1'b1;

assign wrb_n = (!mrq_n & crd_n & zac) ? 1'b0 : 1'b1;
assign roe_n = (!mrq_n & !crd_n & zac) ? 1'b0 : zac;
assign z80_cdo = (!ior_n) ? r_cdo : r_cdi;
assign vid_cdo = cdi;

// Z80 Data Bus latch
always @(posedge mck)
begin
  if (!rin_n) begin
    r_cdi <= 8'h00;
  end else if (zac) begin
    r_cdi <= cdi;
  end
end

// Keyboard
wire    [7:0]   kbcol[0:7];   // matrix AND ca[8:15]
wire    [7:0]   kbd;          // register
wire            key;          // any key pressed

assign kbcol[0] = !ca[ 8] ? kbmat[ 7: 0] : 8'b00000000;
assign kbcol[1] = !ca[ 9] ? kbmat[15: 8] : 8'b00000000;
assign kbcol[2] = !ca[10] ? kbmat[23:16] : 8'b00000000;
assign kbcol[3] = !ca[11] ? kbmat[31:24] : 8'b00000000;
assign kbcol[4] = !ca[12] ? kbmat[39:32] : 8'b00000000;
assign kbcol[5] = !ca[13] ? kbmat[47:40] : 8'b00000000;
assign kbcol[6] = !ca[14] ? kbmat[55:48] : 8'b00000000;
assign kbcol[7] = !ca[15] ? kbmat[63:56] : 8'b00000000;

assign kbd = ~kbcol[0] & ~kbcol[1] & ~kbcol[2] & ~kbcol[3]
  & ~kbcol[4] & ~kbcol[5] & ~kbcol[6] & ~kbcol[7];

assign key = (kbmat[63:0] != 63'b0) ? 1'b1 : 1'b0;

// Debug
assign kbdval = ~kbmat[7:0] & ~kbmat[15:8] & ~kbmat[23:16] & ~kbmat[31:24]
   & ~kbmat[39:32] & ~kbmat[47:40] & ~kbmat[55:48] & ~kbmat[63:56];


// Shortcuts
wire reg_rd;
wire reg_wr;
assign reg_rd = !ior_n & !crd_n & zac;
assign reg_wr = !ior_n & crd_n & zac;

integer i;

// LCD Registers Write
always @(posedge mck)
begin
  if (!rin_n) begin
    pb0 <= 13'd0;
    pb1 <= 10'd0;
    pb2 <= 9'd0;
    pb3 <= 11'd0;
    sbr <= 11'd0;
  end else begin
    if (reg_wr) begin // IO Register Write
      case(ca[7:0])
        8'h70: pb0 <= {ca[12:8], cdi};
        8'h71: pb1 <= {ca[9:8], cdi};
        8'h72: pb2 <= {ca[8], cdi};
        8'h73: pb3 <= {ca[10:8], cdi};
        8'h74: sbr <= {ca[10:8], cdi};
        default: ;
      endcase
    end
  end
end

// Segment Registers Write
always @(posedge mck)
begin
  if (!rin_n) begin
    sr0 <= 8'd0;
    sr1 <= 8'd0;
    sr2 <= 8'd0;
    sr3 <= 8'd0;
  end else begin
    if (reg_wr) begin // IO Register Write
      case(ca[7:0])
        8'hD0: sr0 <= cdi;
        8'hD1: sr1 <= cdi;
        8'hD2: sr2 <= cdi;
        8'hD3: sr3 <= cdi;
        default: ;
      endcase
    end
  end
end

// TSTA is a multiple sources register
// In this case, let's make it a synchronous RS latch:
// - set_req is controlled by the Timer logic.
// - clr_req is controlled by the Register Write logic.
// - the corresponding "acks" are controlled by the latch itself
reg     [2:0]   tsta_set_req;
wire    [2:0]   tsta_set_ack;
reg     [2:0]   tsta_clr_req;
wire    [2:0]   tsta_clr_ack;

slatch3 tsta0 (
  .clk(mck), .res_n(rin_n), .di(1'b0), .q(tsta[0]),
  .req0(tsta_set_req[0]), .d0(1'b1),
  .req1(tsta_clr_req[0]), .d1(1'b0),
  .req2(1'b0), .d2(1'b0),
  .ack0(tsta_set_ack[0]), .ack1(tsta_clr_ack[0]), .ack2()
);
slatch3 tsta1 (
  .clk(mck), .res_n(rin_n), .di(1'b0), .q(tsta[1]),
  .req0(tsta_set_req[1]), .d0(1'b1),
  .req1(tsta_clr_req[1]), .d1(1'b0),
  .req2(1'b0), .d2(1'b0),
  .ack0(tsta_set_ack[1]), .ack1(tsta_clr_ack[1]), .ack2()
);
slatch3 tsta2 (
  .clk(mck), .res_n(rin_n), .di(1'b0), .q(tsta[2]),
  .req0(tsta_set_req[2]), .d0(1'b1),
  .req1(tsta_clr_req[2]), .d1(1'b0),
  .req2(1'b0), .d2(1'b0),
  .ack0(tsta_set_ack[2]), .ack1(tsta_clr_ack[2]), .ack2()
);

// RTC counters and interrupts
always @(posedge mck)
begin
  if ((!rin_n & flp) || com[4]) begin
    // Timer is reset on hard reset or when RESTIM
    tck <= 16'd0;
    tim0 <= 8'd0;
    tim1 <= 6'd0;
    timm <= 21'd0;
    tsta_set_req <= 3'd0;
  end else begin
    tsta_set_req <= 3'd0;
    if (tck == 16'd49152) begin
      tck <= 16'd0;
      tsta_set_req[0] <= 1'b1;
      if (tim0 == 8'd199) begin
        tim0 <= 8'd0;
        tsta_set_req[1] <= 1'b1;
        if (tim1 == 6'd59) begin
          tim1 <= 6'd0;
          tsta_set_req[2] <= 1'b1;
          timm <= timm + 21'd1;
        end else begin
          tim1 <= tim1 + 6'd1;
        end
      end else begin
        tim0 <= tim0 + 8'd1;
      end
    end else begin
      tck <= tck + 16'd1;
    end
  end
end

// Lines for Screen effects : grey and flash
assign t_1s = tim0[7];
assign t_5ms = tck[11];

// TSTA (wr)
always @(posedge mck)
begin
  if (!rin_n) begin
    tsta_clr_req <= 3'd0;
  end else begin
    tsta_clr_req <= 3'd0;
    if (reg_wr && ca[7:0] == 8'hB4) begin
      for(i = 0; i < 3; i = i + 1) begin
        if (cdi[i]) begin
          tsta_clr_req[i] <= 1'b1;
        end
      end
    end
  end
end

// TMK (wr)
always @(posedge mck)
begin
  if (!rin_n) begin
    tmk <= 3'd0;
  end else begin
    if (reg_wr && ca[7:0] == 8'hB5) begin
      tmk <= cdi[2:0];
    end
  end
end

// Interrupt registers reads (r_cdo control)
always @(posedge mck)
begin
  if (!rin_n) begin
    r_cdo <= 8'd0;
  end else begin
    if (reg_rd) begin // IO Register Read
      case(ca[7:0])
        // STA : interrupt status
        8'hB1: r_cdo <= sta;
        // KBD : key pressed (TODO: reading KBD when KWAIT set will snooze)
        8'hB2: r_cdo <= kbd;
        // TSTA : Timer status
        8'hB5: r_cdo <= {5'b00000, tsta};
        // TIM0 : 5ms tick counter
        8'hD0: r_cdo <= tim0;
        // TIM1 : seconds counter
        8'hD1: r_cdo <= {2'b00, tim1};
        // TIM2 : minutes counter
        8'hD2: r_cdo <= timm[7:0];
        // TIM3 : 256 minutes counter
        8'hD3: r_cdo <= timm[15:8];
        // TIM4 : 64K minutes counter
        8'hD4: r_cdo <= {3'b000, timm[20:16]};
        // UIT : UART interrupt status (required but not implemented)
        8'hE5: r_cdo <= 8'h0;
        default: ;
      endcase
    end
  end
end

assign sta = {flp, 1'b0, flps, 2'b00, kbds, 1'b0, rtcs};

// Interrupt
wire intw;  // RTC int + KBD int + FLAP int
wire kbds;  // key pressed (only during snooze or coma)
wire flps;  // flap open
wire rtcs;  // RTC (tick, sec, min)
assign rtcs = ((tsta & tmk) == 3'b000) ? 1'b0 : 1'b1;
assign intw = (rtcs & int1[0] & int1[1])
   | (flps & int1[0] & int1[5]);
assign intb_n = ~intw;        // to Z80
// NMI low on flap open, power failure or card insertion (not implemented)
assign nmib_n = ~flp;

// COM, INT, ACK (wr)
always @(posedge mck)
begin
  if (!rin_n) begin
    com <= 8'h00;
    int1 <= 7'h00;
    kbds_clr_req <= 1'b0;
    flap_clr_req <= 1'b0;
  end else begin
    kbds_clr_req <= 1'b0;
    flap_clr_req <= 1'b0;
    if (reg_wr) begin
      // IO register write
      case(ca[7:0])
        8'hB0: com <= cdi; // COM
        8'hB1: begin // INT
          int1 <= cdi[6:0]; // INT[6:0]
          //int7_set_req <= cdi[7]; // KWAIT = INT[7]
        end
        8'hB6: begin // ACK
          kbds_clr_req <= cdi[2]; // ack. keyboard int.
          flap_clr_req <= cdi[5]; // ack. flap int.
        end
        default: ;
      endcase
    end
  end
end

// Keyboard interrupt latch change
always @(posedge mck)
begin
  if (!rin_n) begin
    kbds_set_req <= 1'b0;
  end else begin
    kbds_set_req <= 1'b0; //(key & ~pm1s); // wake up
  end
end

// Flap Latch change
always @(posedge mck)
begin
  if (!rin_n) begin
    flap_set_req <= 1'b0;
  end else begin
    flap_set_req <= flp;
  end
end

// Keyboard Interrupt Status (kbds) as a RS latch
reg             kbds_set_req;
wire            kbds_set_ack;
reg             kbds_clr_req;
wire            kbds_clr_ack;

slatch3 kbdsl (
  .clk(mck), .res_n(rin_n), .di(1'b0), .q(kbds),
  .req0(kbds_set_req), .d0(1'b1),
  .req1(kbds_clr_req), .d1(1'b0),
  .req2(1'b0), .d2(1'b0),
  .ack0(kbds_set_ack), .ack1(kbds_clr_ack), .ack2()
);

// Flap Interrupt Status (flps) as a RS latch
reg             flap_set_req;
wire            flap_set_ack;
reg             flap_clr_req;
wire            flap_clr_ack;

slatch3 flapl (
  .clk(mck), .res_n(rin_n), .di(1'b0), .q(flps),
  .req0(flap_set_req), .d0(1'b1),
  .req1(flap_clr_req), .d1(1'b0),
  .req2(1'b0), .d2(1'b0),
  .ack0(flap_set_ack), .ack1(flap_clr_ack), .ack2()
);

endmodule
