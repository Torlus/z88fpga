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

// Clocks
assign pm1 = (pm1s) ? mck : 1'b0; // Halt stops CPU, Int low restarts.

// General
reg     [15:0]  tck;  // tick counter
reg             pm1s; // Z80 clock switch
reg     [7:0]   r_cdo;

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
reg     [7:0]   sta;  // Interrupt status (RD)
reg             iak;  // Auto ack. int/sta flag
reg             intb; // Int. flag

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
    (com[2] == 1'b0) ?
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

// Shortcuts
wire reg_rd;
wire reg_wr;

assign reg_rd = !ior_n & crd_n;
assign reg_wr = !ior_n & !crd_n;

// LCD Registers
always @(posedge mck)
begin
  if (rin_n == 1'b0) begin
    pb0 <= 13'b0000000000000;
    pb1 <= 10'b0000000000;
    pb2 <= 9'b000000000;
    pb3 <= 11'b00000000000;
    sbr <= 11'b00000000000;
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
  if (rin_n == 1'b0) begin
    sr0 <= 8'h00;
    sr1 <= 8'h00;
    sr2 <= 8'h00;
    sr3 <= 8'h00;
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



// Blink Heart
always @(posedge mck)
begin
  if (rin_n == 1'b0) begin
    tck <= 16'h0000;
    pm1s <= 1'b1;
    com <= 8'h00;
    r_cdo <= 8'h00;
    int1 <= 8'h00;
    sta <= 8'h00;
    intb <= 1'b0;
    iak <= 1'b0;
    tsta <= 3'b000;
    tmk <= 3'b000;
    tim0 <= 8'h00;        // in fact timer is reset only on hard reset (flap opened TBD)
    tim1 <= 6'h00;
    timm <= 21'h000000;
  end else begin
    if (mck == 1'b1) begin
      if (tck != 49152) begin
        tck <= tck+1;
        if (!ior_n & !cm1_n) begin
          // Z80 has acknowledged int_n
          intb <= 1'b0;
          if (int1[7]) begin
            int1[7] <= 1'b0;
          end
        end else begin
          if (intb) begin
            // Int restart Z80 clock
            pm1s <= 1'b1;
          end else begin
            if  (!hlt_n) begin
              if (ca[15:8] != 8'h3F) begin
                // Halt does Snooze, Z80 clock stopped
                pm1s <= 1'b0;
              end else begin
                pm1s <= 1'b0;
                // Halt and A15-8=3F does Coma : switch off mck and use sck (TBD)
                // (Note : Register I is copied on A15-8 during Halt)
              end
            end else begin
              if (!ior_n & crd_n) begin
                // IO register write
                case(ca[7:0])
                  8'hB0: com <= cdi;
                  8'hB1: int1 <= cdi;
                  8'hB4: tsta <= tsta & ~cdi[2:0];
                  8'hB5: tmk <= cdi[2:0];
                  8'hB6: sta <= sta & {1'b1, ~cdi[6:5], 1'b1, ~cdi[3:2], 2'b10};
                  default: ;
                endcase
              end else begin
                if (!ior_n & !crd_n) begin
                  if (iak) begin
                    sta[1] <= 1'b0; // ack. Timer int.
                    iak <= 1'b0;    // int. ack. done.
                  end else begin
                    // IO register read
                    case(ca[7:0])
                      8'hB1: begin
                        r_cdo <= sta;
                        iak <= 1'b1;
                      end
                      8'hB2: begin
                        r_cdo <= kbd;
                        // KWait set and no key pressed will snooze
                        pm1s <= ~int1[7] | kbd[7] | kbd[6] | kbd[5] | kbd[4] | kbd[3] | kbd[2] | kbd[1] | kbd[0];
                        // Key interrupt flag (acknoledged by Tack B6)
                        sta[2] <= int1[7] | ~kbd[7] | ~kbd[6] | ~kbd[5] | ~kbd[4] | ~kbd[3] | ~kbd[2] | ~kbd[1] | ~kbd[0];
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
            end
          end
        end
      end else begin
        tck <= 16'h0000;
        if (com[4]) begin   // restim
          // Timer reset has to be set then reset
          tim0 <= 8'h00;
          tim1 <= 6'h00;
          timm <= 21'h00;
          tsta <= 3'b000;
        end else begin
          if (tim0 != 199) begin    // 5ms tick
            tim0 <= tim0 + 1'b1;
            tsta <= 3'b001;
            sta[1] <= int1[0] & int1[1] & tmk[0]; // timer int. flag
            intb <= int1[0] & int1[1] & tmk[0];   // fires int. if enabled
          end else begin
            if (tim1 != 59) begin   // second
              tim0 <= 8'h00;
              tim1 <= tim1 + 1'b1;
              tsta <= 3'b011;
              sta[1] <= int1[0] & int1[1] & tmk[1];
              intb <= int1[0] & int1[1] & tmk[1];
            end else begin          // minute
              tim1 <= 6'h00;
              timm <= timm + 1'b1;
              tsta <= 3'b111;
              sta[1]<= int1[0] & int1[1] & tmk[2];
              intb <= int1[0] & int1[1] & tmk[2];
            end
          end
        end
      end
    end
  end
end

endmodule
