module blink
(
    // Global reset
    input         rst,
    // 50MHz Master Clock
    input         clk,
    // 10MHz equivalent clock
    input   [4:0] clk_ena,
    // 3.3MHz equivalent clock
    output  [2:0] clk_ph,
    output  [2:0] clk_ph_adv,
    // Standby
    output        pm1s,

    // Z80 bus
    input         z80_hlt_n,    // HALT Coma/Standby command
    input         z80_crd_n,    // RD from Z80
    input         z80_cm1_n,    // M1 (=WR or =RFSH) from Z80
    input         z80_mrq_n,    // MREQ
    input         z80_ior_n,    // ior_nQ
    input  [15:0] z80_addr,     // Z80 address bus
    input   [7:0] z80_wdata,    // Z80 data bus (write)
    output  [7:0] z80_rdata,    // Z80 data bus (read)
    output        z80_nmi_n,    // NMI
    output        z80_int_n,    // INT

    // LCD control
    input  [21:0] lcd_addr,
    output        lcd_on,
    output [12:0] lcd_pb0,
    output  [9:0] lcd_pb1,
    output  [8:0] lcd_pb2,
    output [10:0] lcd_pb3,
    output [10:0] lcd_sbr,

    // External bus
    output        ext_oe_n,     // RAM/ROM output enable
    output        ext_we_n,     // Write enable
    output        ram_cs_n,     // Slot 0 RAM access
    output        rom_cs_n,     // Slot 0 ROM access
    output  [3:1] ext_cs_n,     // Slots 1-3 access
    output [21:0] ext_addr,     // Physical memory (22 bits address bus)

    // Keyboard
    input  [63:0] kbmat,
    output  [7:0] kbdval,
    output        kbds,
    output        key,

    // Clocks
    output        t_1s,     // 1s for cursor, flash effect
    output        t_5ms,    // 5ms for grey effect

    // Flap
    input         flp       // Flap switch (high if opened for card insertion or hard reset)
);

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


// Screen


reg     [7:0]   r_cdi;

// Clock phases
reg   [2:0]   r_clk_ph_adv; // Advanced by 2 cycles
reg   [2:0]   r_clk_ph;

always @(posedge rst or posedge clk) begin

    if (rst) begin
        r_clk_ph_adv <= 3'b001;
        r_clk_ph     <= 3'b000;
    end
    else begin
        if (clk_ena[2]) begin
            r_clk_ph_adv <= { r_clk_ph_adv[1:0], r_clk_ph_adv[2] };
        end
        if (clk_ena[4]) begin
            r_clk_ph <= r_clk_ph_adv;
        end
    end
end

assign clk_ph     = r_clk_ph;
assign clk_ph_adv = r_clk_ph_adv;
assign pm1s       = 1'b1;

// General
reg     [15:0]  tck;  // tick counter
reg     [7:0]   r_cdo; // I/O Port read buffer

// Common control register
reg     [7:0]   com /* verilator public */;      // IO $B0

// Bank switching (WR only)
reg     [7:0]   sr0 /* verilator public */;
reg     [7:0]   sr1 /* verilator public */;
reg     [7:0]   sr2 /* verilator public */;
reg     [7:0]   sr3 /* verilator public */;

// Screen
reg     [12:0]  pb0;  // Lores0 (RAM, 64 char, 512B)
reg     [9:0]   pb1;  // Lores1 (ROM, 448 char, 3.5K)
reg     [8:0]   pb2;  // Hires0 (RAM, 768 char, 6K)
reg     [10:0]  pb3;  // Hires1 (ROM, 256 char, 2K)
reg     [10:0]  sbr;  // Screen Base File (RAM, 128 attr*8, 2K)

assign  lcd_on  = com[0];
assign  lcd_pb0 = pb0;
assign  lcd_pb1 = pb1;
assign  lcd_pb2 = pb2;
assign  lcd_pb3 = pb3;
assign  lcd_sbr = sbr;

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
// Only even banks can be bound in sr0
// An odd bank will bind upper half of previous (even) bank

reg [21:0] r_za;

always @(posedge rst or posedge clk) begin : Z80_MMU

    if (rst) begin
        r_za <= 22'd0;
    end
    else if (clk_ena[4]) begin

        if (r_clk_ph[0]) begin
            casez (z80_addr[15:13])
                // 0000-1FFF : Bank $00 !RAMS, Bank $20 RAMS
                3'b000 : r_za <= { 2'b00, com[2], 6'b0, z80_addr[12:0] };
                // 2000-3FFF : Only even banks, sr[0] select lower/upper part
                3'b001 : r_za <= { sr0[7:1], 1'b0, sr0[0], z80_addr[12:0] };
                // 4000-7FFF
                3'b01? : r_za <= { sr1[7:0], z80_addr[13:0] };
                // 8000-BFFF
                3'b10? : r_za <= { sr2[7:0], z80_addr[13:0] };
                // C000-FFFF
                3'b11? : r_za <= { sr3[7:0], z80_addr[13:0] };
            endcase
        end
    end
end

// Z80 Access Cycle
wire w_zac = r_clk_ph[2];

reg        r_ext_oe_n;
reg        r_ext_we_n;
reg        r_rom_cs_n;
reg        r_ram_cs_n;
reg  [3:1] r_ext_cs_n;
reg [21:0] r_ext_addr;

always @(posedge rst or posedge clk) begin : EXT_BUS

    if (rst) begin
        r_ext_oe_n <= 1'b1;
        r_ext_we_n <= 1'b1;
        r_rom_cs_n <= 1'b1;
        r_ram_cs_n <= 1'b1;
        r_ext_cs_n <= 3'b111;
        r_ext_addr <= 22'd0;
    end
    else begin
        if (r_clk_ph_adv[2]) begin
            // Z80 access
            r_ext_oe_n    <= z80_mrq_n |  z80_crd_n;
            r_ext_we_n    <= z80_mrq_n | ~z80_crd_n;
            r_rom_cs_n    <= (r_za[21:19] == 3'b000) ? z80_mrq_n : 1'b1;
            r_ram_cs_n    <= (r_za[21:19] == 3'b001) ? z80_mrq_n : 1'b1;
            r_ext_cs_n[1] <= (r_za[21:20] == 2'b01) ? z80_mrq_n : 1'b1;
            r_ext_cs_n[2] <= (r_za[21:20] == 2'b10) ? z80_mrq_n : 1'b1;
            r_ext_cs_n[3] <= (r_za[21:20] == 2'b11) ? z80_mrq_n : 1'b1;
            r_ext_addr    <= r_za;
        end
        else begin
            // LCD access
            r_ext_oe_n    <= 1'b0;
            r_ext_we_n    <= 1'b1;
            r_rom_cs_n    <= (lcd_addr[21:19] == 3'b000) ? 1'b0 : 1'b1;
            r_ram_cs_n    <= (lcd_addr[21:19] == 3'b001) ? 1'b0 : 1'b1;
            r_ext_cs_n[1] <= (lcd_addr[21:20] == 2'b01) ? 1'b0 : 1'b1;
            r_ext_cs_n[2] <= (lcd_addr[21:20] == 2'b10) ? 1'b0 : 1'b1;
            r_ext_cs_n[3] <= (lcd_addr[21:20] == 2'b11) ? 1'b0 : 1'b1;
            r_ext_addr    <= lcd_addr;
        end
    end
end

assign ext_oe_n = r_ext_oe_n;
assign ext_we_n = r_ext_we_n;
assign rom_cs_n = r_rom_cs_n;
assign ram_cs_n = r_ram_cs_n;
assign ext_cs_n = r_ext_cs_n;
assign ext_addr = r_ext_addr;

assign z80_rdata = (!z80_ior_n) ? r_cdo : r_cdi;

// Z80 Data Bus latch
always @(posedge rst or posedge clk) begin

  if (rst) begin
    r_cdi <= 8'h00;
  end else if (w_zac) begin
    r_cdi <= z80_wdata;
  end
end

// Keyboard
wire    [7:0]   kbcol[0:7];   // matrix AND z80_addr[8:15]
wire    [7:0]   kbd;          // register

assign kbcol[0] = !z80_addr[ 8] ? kbmat[ 7: 0] : 8'b00000000;
assign kbcol[1] = !z80_addr[ 9] ? kbmat[15: 8] : 8'b00000000;
assign kbcol[2] = !z80_addr[10] ? kbmat[23:16] : 8'b00000000;
assign kbcol[3] = !z80_addr[11] ? kbmat[31:24] : 8'b00000000;
assign kbcol[4] = !z80_addr[12] ? kbmat[39:32] : 8'b00000000;
assign kbcol[5] = !z80_addr[13] ? kbmat[47:40] : 8'b00000000;
assign kbcol[6] = !z80_addr[14] ? kbmat[55:48] : 8'b00000000;
assign kbcol[7] = !z80_addr[15] ? kbmat[63:56] : 8'b00000000;

assign kbd = ~kbcol[0] & ~kbcol[1] & ~kbcol[2] & ~kbcol[3]
  & ~kbcol[4] & ~kbcol[5] & ~kbcol[6] & ~kbcol[7];

assign key = (kbmat[63:0] != 64'b0) ? 1'b1 : 1'b0;

// Debug
assign kbdval = ~kbmat[7:0] & ~kbmat[15:8] & ~kbmat[23:16] & ~kbmat[31:24]
   & ~kbmat[39:32] & ~kbmat[47:40] & ~kbmat[55:48] & ~kbmat[63:56];


// Shortcuts
wire w_reg_rd = ~z80_ior_n & ~z80_crd_n & w_zac;
wire w_reg_wr = ~z80_ior_n &  z80_crd_n & w_zac;

integer i;

// LCD Registers Write
always @(posedge rst or posedge clk) begin : LCD_REGS_WR

  if (rst) begin
    pb0 <= 13'd0;
    pb1 <= 10'd0;
    pb2 <= 9'd0;
    pb3 <= 11'd0;
    sbr <= 11'd0;
  end
  else if (clk_ena[4]) begin
    if (w_reg_wr) begin // IO Register Write
      case(z80_addr[7:0])
        8'h70: pb0 <= {z80_addr[12:8], z80_wdata};
        8'h71: pb1 <= {z80_addr[ 9:8], z80_wdata};
        8'h72: pb2 <= {z80_addr[   8], z80_wdata};
        8'h73: pb3 <= {z80_addr[10:8], z80_wdata};
        8'h74: sbr <= {z80_addr[10:8], z80_wdata};
        default: ;
      endcase
    end
  end
end

// Segment Registers Write
always @(posedge rst or posedge clk) begin : SEG_REGS_WR

  if (rst) begin
    sr0 <= 8'd0;
    sr1 <= 8'd0;
    sr2 <= 8'd0;
    sr3 <= 8'd0;
  end
  else if (clk_ena[4]) begin
    if (w_reg_wr) begin // IO Register Write
      case(z80_addr[7:0])
        8'hD0: sr0 <= z80_wdata;
        8'hD1: sr1 <= z80_wdata;
        8'hD2: sr2 <= z80_wdata;
        8'hD3: sr3 <= z80_wdata;
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
  .clk(clk), .res_n(~rst), .di(1'b0), .q(tsta[0]),
  .req0(tsta_set_req[0]), .d0(1'b1),
  .req1(tsta_clr_req[0]), .d1(1'b0),
  .req2(1'b0), .d2(1'b0),
  .ack0(tsta_set_ack[0]), .ack1(tsta_clr_ack[0]), .ack2()
);
slatch3 tsta1 (
  .clk(clk), .res_n(~rst), .di(1'b0), .q(tsta[1]),
  .req0(tsta_set_req[1]), .d0(1'b1),
  .req1(tsta_clr_req[1]), .d1(1'b0),
  .req2(1'b0), .d2(1'b0),
  .ack0(tsta_set_ack[1]), .ack1(tsta_clr_ack[1]), .ack2()
);
slatch3 tsta2 (
  .clk(clk), .res_n(~rst), .di(1'b0), .q(tsta[2]),
  .req0(tsta_set_req[2]), .d0(1'b1),
  .req1(tsta_clr_req[2]), .d1(1'b0),
  .req2(1'b0), .d2(1'b0),
  .ack0(tsta_set_ack[2]), .ack1(tsta_clr_ack[2]), .ack2()
);

// RTC counters and timer interrupts
always @(posedge clk) begin : TIMER
  reg v_tick;
  reg v_tim0;
  reg v_tim1;

  if ((rst & flp) || com[4]) begin
    // Timer is reset on hard reset or when RESTIM
    tck <= 16'd0;
    tim0 <= 8'd0;
    tim1 <= 6'd0;
    timm <= 21'd0;
    tsta_set_req <= 3'd0;
    v_tick <= 1'b0;
    v_tim0 <= 1'b0;
    v_tim1 <= 1'b0;
  end
  else if (clk_ena[4]) begin
    tsta_set_req <= 3'd0;
    if (v_tick) begin
      tck <= 16'd0;
      tsta_set_req[0] <= 1'b1;
      if (v_tim0) begin
        tim0 <= 8'd0;
        tsta_set_req[1] <= 1'b1;
        if (v_tim1) begin
          tim1 <= 6'd0;
          tsta_set_req[2] <= 1'b1;
          timm <= timm + 21'd1;
        end
        else begin
          tim1 <= tim1 + 6'd1;
        end
      end
      else begin
        tim0 <= tim0 + 8'd1;
      end
    end
    else begin
      tck <= tck + 16'd1;
    end
    v_tick <= (tck == 16'd49151) ? 1'b1 : 1'b0;
    v_tim0 <= (tim0 == 8'd199) ? 1'b1 : 1'b0;
    v_tim1 <= (tim1 == 6'd59) ? 1'b1 : 1'b0;
  end
end

// Lines for Screen effects : grey and flash
assign t_1s = tim0[7];
assign t_5ms = tck[11];

// TSTA (wr)
always @(posedge rst or posedge clk) begin
  if (rst) begin
    tsta_clr_req <= 3'd0;
  end
  else if (clk_ena[4]) begin
    tsta_clr_req <= 3'd0;
    if (w_reg_wr && z80_addr[7:0] == 8'hB4) begin
      for(i = 0; i < 3; i = i + 1) begin
        if (z80_wdata[i]) begin
          tsta_clr_req[i] <= 1'b1;
        end
      end
    end
  end
end

// TMK (wr)
always @(posedge rst or posedge clk) begin

  if (rst) begin
    tmk <= 3'd0;
  end
  else if (clk_ena[4]) begin
    if (w_reg_wr && z80_addr[7:0] == 8'hB5) begin
      tmk <= z80_wdata[2:0];
    end
  end
end

// Interrupt registers reads (r_cdo control)
always @(posedge rst or posedge clk) begin

  if (rst) begin
    r_cdo <= 8'd0;
  end
  else if (clk_ena[4])  begin
    if (w_reg_rd) begin // IO Register Read
      case(z80_addr[7:0])
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
wire flps;  // flap open
wire rtcs;  // RTC (tick, sec, min)
assign rtcs = ((tsta & tmk) == 3'b000) ? 1'b0 : 1'b1;
assign intw = (rtcs & int1[0] & int1[1])
   | (flps & int1[0] & int1[5]);
assign z80_int_n = ~intw;        // to Z80
// NMI low on flap open, power failure or card insertion (not implemented)
assign z80_nmi_n = ~flp;

// COM, INT, ACK (wr)
always @(posedge rst or posedge clk) begin
  if (rst) begin
    com <= 8'h00;
    int1 <= 7'h00;
    kbds_clr_req <= 1'b0;
    flap_clr_req <= 1'b0;
  end
  else if (clk_ena[4]) begin
    kbds_clr_req <= 1'b0;
    flap_clr_req <= 1'b0;
    if (w_reg_wr) begin
      // IO register write
      case(z80_addr[7:0])
        8'hB0: com <= z80_wdata; // COM
        8'hB1: begin // INT
          int1 <= z80_wdata[6:0]; // INT[6:0]
          //int7_set_req <= z80_wdata[7]; // KWAIT = INT[7]
        end
        8'hB6: begin // ACK
          kbds_clr_req <= z80_wdata[2]; // ack. keyboard int.
          flap_clr_req <= z80_wdata[5]; // ack. flap int.
        end
        default: ;
      endcase
    end
  end
end

// Keyboard interrupt latch change
always @(posedge rst or posedge clk) begin

  if (rst) begin
    kbds_set_req <= 1'b0;
  end
  else if (clk_ena[4]) begin
    kbds_set_req <= 1'b0; //(key & ~pm1s); // wake up
  end
end

// Flap Latch change
always @(posedge rst or posedge clk) begin

  if (rst) begin
    flap_set_req <= 1'b0;
  end
  else if (clk_ena[4]) begin
    flap_set_req <= flp;
  end
end

// Keyboard Interrupt Status (kbds) as a RS latch
reg             kbds_set_req;
wire            kbds_set_ack;
reg             kbds_clr_req;
wire            kbds_clr_ack;

slatch3 kbdsl (
  .clk(clk), .res_n(~rst), .di(1'b0), .q(kbds),
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
  .clk(clk), .res_n(~rst), .di(1'b0), .q(flps),
  .req0(flap_set_req), .d0(1'b1),
  .req1(flap_clr_req), .d1(1'b0),
  .req2(1'b0), .d2(1'b0),
  .ack0(flap_set_ack), .ack1(flap_clr_ack), .ack2()
);

endmodule
