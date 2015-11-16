module blink (
  // Outputs
  rout_n, cdo, wrb_n, ipce_n, irce_n, se1_n, se2_n, se3_n, ma, pm1,
  intb_n, nmib_n, roe_n,
  // Inputs
  ca, crd_n, cdi, mck, sck, rin_n, hlt_n, mrq_n, ior_n, cm1_n, kbmat
  );

// Clocks
input           mck;      // 9.83MHz Master Clock
input           sck;      // 25.6KHz Standby Clock
output          pm1;      // Z80 clock driven by blink

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

// Clocks
assign pm1 = (pm1s) ? z80_clk : 1'b0; // Halt stops CPU, Int low restarts.

// General
reg     [15:0]  tck;  // tick counter
reg             pm1s; // Z80 clock switch
reg     [7:0]   r_cdo; // I/O Port read buffer

// Common control register
reg     [7:0]   com;      // IO $B0

// Bank switching (WR only)
reg     [7:0]   sr0;
reg     [7:0]   sr1;
reg     [7:0]   sr2;
reg     [7:0]   sr3;

// Display (WR only)
reg     [12:0]  pb0;  // Lores0 (RAM, 64 char, 512B)
reg     [9:0]   pb1;  // Lores1 (ROM, 448 char, 3.5K)
reg     [8:0]   pb2;  // Hires0 (RAM, 768 char, 6K)
reg     [10:0]  pb3;  // Hires1 (ROM, 256 char, 2K)
reg     [10:0]  sbr;  // Screen Base File (RAM, 128 attr*8, 2K)

// Interrupts
reg     [7:0]   int1; // Interrupt control (WR)
// reg     [7:0]   sta;  // Interrupt status (RD)
wire    [7:0]   sta;


// Timer interrupts
reg     [2:0]   tsta; // Timer interrupt status (RD)
reg     [2:0]   tmk;  // Timer interrupt mask (WR)

// Real Time Clock (RD)
reg     [7:0]   tim0; // 5ms ticks (0-199)
reg     [5:0]   tim1; // seconds (0-59)
reg     [20:0]  timm; // minutes (0-2^21)

// Memory addressing
assign ma =
  (ca[15:14] == 2'b11) ? { sr3, ca[13:0] }                // C000-FFFF
  :  (ca[15:14] == 2'b10) ? { sr2, ca[13:0] }             // 8000-BFFF
  :  (ca[15:14] == 2'b01) ? { sr1, ca[13:0] }             // 4000-7FFF
  :  (ca[15:13] == 3'b001) ? { sr0, 1'b1, ca[12:0] }      // 2000-3FFF
  :  (ca[15:13] == 3'b000) ?                              // 0000-1FFF
    (com[2  ] == 1'b0) ?
    { 8'b00000000, 1'b0, ca[12:0] }                       // Bank $00 !RAMS
    : { 8'b00100000, 1'b0, ca[12:0] }                     // Bank $20 RAMS
  : 22'b11_1111_1111_1111_1111_1111;

// Control bus
assign ipce_n =
  (ma[21:19] == 3'b000 & !mrq_n) ? 1'b0 : 1'b1;

assign irce_n =
  (ma[21:19] == 3'b001 & !mrq_n) ? 1'b0 : 1'b1;

assign wrb_n = (!mrq_n & crd_n) ? 1'b0 : 1'b1;
assign roe_n = (!mrq_n & !crd_n) ? 1'b0 : 1'b1;
assign cdo = (!ior_n) ? r_cdo : cdi;

// Keyboard
reg     [63:0]  kbmat;
wire    [7:0]   kbcol[0:7];
wire    [7:0]   kbd;

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

// Shortcuts
wire reg_rd;
wire reg_wr;
assign reg_rd = !ior_n & !crd_n;
assign reg_wr = !ior_n & crd_n;

integer i;

// FIXME
assign nmib_n = 1'b1;

// LCD Registers
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

// Segment Registers
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
reg     [2:0]   tsta_set_ack;
reg     [2:0]   tsta_clr_req;
reg     [2:0]   tsta_clr_ack;

always @(posedge mck)
begin
  if (!rin_n) begin
    tsta <= 3'd0;
    tsta_set_ack <= 3'd0;
    tsta_clr_ack <= 3'd0;
  end else begin
    for(i = 0; i < 3; i = i + 1) begin
      if (!tsta_set_req[i]) begin
        tsta_set_ack[i] <= 1'b0;
      end
      if (!tsta_clr_req[i]) begin
        tsta_clr_ack[i] <= 1'b0;
      end
      if (tsta_set_req[i] & !tsta_set_ack[i]) begin
        tsta_set_ack[i] <= 1'b1;
        tsta[i] <= 1'b1;
      end else if (tsta_clr_req[i] & !tsta_clr_ack[i]) begin
        tsta_clr_ack[i] <= 1'b1;
        tsta[i] <= 1'b0;
      end
    end
  end
end


// RTC: Tick counter and interrupts
always @(posedge mck)
begin
  if (!rin_n | com[4]) begin
    tck <= 16'd0;
    tim0 <= 8'd0;        // in fact timer is reset only on hard reset (flap opened TBD)
    tim1 <= 6'd0;
    timm <= 21'd0;
    tsta_set_req <= 3'd0;
  end else begin
    tsta_set_req <= 3'd0;
    tck <= tck + 16'd1;
    if (tck == 16'd49152) begin
      tck <= 16'd0;
      tsta_set_req[0] <= 1'b1;
      tim0 <= tim0 + 8'd1;
      if (tim0 == 8'd199) begin
        tim0 <= 8'd0;
        tsta_set_req[1] <= 1'b1;
        tim1 <= tim1 + 6'd1;
        if (tim1 == 6'd59) begin
          tim1 <= 6'd0;
          tsta_set_req[2] <= 1'b1;
          timm <= timm + 21'd1;
        end
      end
    end
  end
end

// RTC: IO Registers
always @(posedge mck)
begin
  if (!rin_n) begin
    tsta_clr_req <= 3'd0;
    tmk <= 3'd0;
  end else begin
    tsta_clr_req <= 3'd0;
    if (reg_wr) begin // IO Register Write
      case(ca[7:0])
        8'hB4: begin
          for(i = 0; i < 3; i = i + 1) begin
            if (cdi[i]) begin
              tsta_clr_req[i] <= 1'b1;
            end
          end
        end
        8'hB5: tmk <= cdi[2:0];
        default: ;
      endcase
    end
  end
end

// Register reads (r_cdo control)
always @(posedge mck)
begin
  if (!rin_n) begin
    r_cdo <= 8'd0;
    pm1s_clr_req2 <= 1'b0;
  end else begin
    pm1s_clr_req2 <= 1'b0;
    if (reg_rd) begin // IO Register Read
      case(ca[7:0])
        8'hB1: r_cdo <= sta;
        8'hB2: begin
          r_cdo <= kbd;
          if (int1[7]) begin
            int1[7] <= ~int1[7];     // clear Kwait
            pm1s_clr_req2 <= 1'b1;   // Snooze
          end
        end
        8'hB5: r_cdo <= {5'b00000, tsta};
        8'hD0: r_cdo <= tim0;                   // 5ms tick
        8'hD1: r_cdo <= {2'b00, tim1};          // seconds
        8'hD2: r_cdo <= timm[7:0];              // minutes
        8'hD3: r_cdo <= timm[15:8];             // 256 minutes
        8'hD4: r_cdo <= {3'b000, timm[20:16]};  // 64K minutes
        default: ;
      endcase
    end
  end
end

// PM1S as a RS-latch
reg             pm1s_set_req;
reg             pm1s_set_ack;
reg             pm1s_clr_req;
reg             pm1s_clr_ack;
reg             pm1s_clr_req2;
reg             pm1s_clr_ack2;

always @(posedge mck)
begin
  if (!rin_n) begin
    pm1s <= 1'b1;
    pm1s_set_ack <= 1'b0;
    pm1s_clr_ack <= 1'b0;
    pm1s_clr_ack2 <= 1'b0;
  end else begin
    if (!pm1s_set_req) begin
      pm1s_set_ack <= 1'b0;
    end
    if (!pm1s_clr_req) begin
      pm1s_clr_ack <= 1'b0;
    end
    if (!pm1s_clr_req2) begin
      pm1s_clr_ack2 <= 1'b0;
    end

    if (pm1s_set_req & !pm1s_set_ack) begin
      pm1s_set_ack <= 1'b1;
      pm1s <= 1'b1;
    end else if (pm1s_clr_req & !pm1s_clr_ack) begin
      pm1s_clr_ack <= 1'b1;
      pm1s <= 1'b0;
    end else if (pm1s_clr_req2 & !pm1s_clr_ack2) begin
      pm1s_clr_ack2 <= 1'b1;
      pm1s <= 1'b0;
    end
  end
end

assign sta = { 5'b00000, kbd_int, rtc_int, 1'b0};

// Keyboard Status
reg kbds;

// Interrupts
wire rtc_int;
assign rtc_int = ((tsta & tmk) == 3'b000) ? 1'b0 : 1'b1;

wire kbd_int;
assign kbd_int = (kbds) ? 1'b1 : 1'b0; // Key pressed and Kwait fires an interrupt

// Interrupt signal
wire intb;
assign intb = (rtc_int & int1[0] & int1[1])
  | (kbd_int & int1[0] & int1[2]);
assign intb_n = !intb;

always @(posedge mck)
begin
  if (!rin_n) begin
    pm1s_set_req <= 1'b0;
    pm1s_clr_req <= 1'b0;
  end else begin
    pm1s_set_req <= 1'b0;
    pm1s_clr_req <= 1'b0;
    if (!hlt_n & !intb) begin
      pm1s_clr_req <= 1'b1;   // Do Snooze
      // Halt and A15-8=3F does Coma : switch off mck and use sck (TBD)
      // (Note : Register I is copied on A15-8 during Halt)
    end
    if (intb) begin
      pm1s_set_req <= 1'b1;   // Awake Z80 CPU
    end
  end
end


// Register Writes
always @(posedge mck)
begin
  if (!rin_n) begin
    com <= 8'h00;
    int1 <= 8'h00;
    kbds_clr_req <= 1'b0;
  end else begin
    kbds_clr_req <= 1'b0;
    if (reg_wr) begin
      // IO register write
      case(ca[7:0])
        8'hB0: com <= cdi;
        8'hB1: int1 <= cdi;
        8'hB6: begin
          // ACK main interrupt acknowledge
          if (cdi[2]) begin
            kbds_clr_req <= 1'b1;
          end
        end
        default: ;
      endcase
    end
  end
end

// Keyboard Status as a RS-latch
reg             kbds_set_req;
reg             kbds_set_ack;
reg             kbds_clr_req;
reg             kbds_clr_ack;

always @(posedge mck)
begin
  if (!rin_n) begin
    kbds <= 1'b0;
    kbds_set_ack <= 1'b0;
    kbds_clr_ack <= 1'b0;
  end else begin
    if (!kbds_set_req) begin
      kbds_set_ack <= 1'b0;
    end
    if (!kbds_clr_req) begin
      kbds_clr_ack <= 1'b0;
    end

    if (kbds_set_req & !kbds_set_ack) begin
      kbds_set_ack <= 1'b1;
      kbds <= 1'b1;
    end else if (kbds_clr_req & !kbds_clr_ack) begin
      kbds_clr_ack <= 1'b1;
      kbds <= 1'b0;
    end
  end
end

// Keyboard Status change
// TODO (?) Debounce
always @(posedge mck)
begin
  if (!rin_n) begin
    kbds_set_req <= 1'b0;
  end else begin
    kbds_set_req <= 1'b0;
    if (kbd != 8'hFF & !ior_n) begin
      kbds_set_req <= 1'b1;
    end
  end
end

endmodule
