module ps2(
  // Inputs
  reset_n, ps2clk, ps2dat,

  // Outputs
  kbmat_out
);

input           reset_n;
input           ps2clk;
input           ps2dat;

output  [63:0]  kbmat_out;

// ps2 conversion
reg     [7:0]   ps2key;     // scan code
reg             extkey;     // extended set flag (hE0)
reg             rlskey;     // release key flag (hF0)
reg             ps2ok;      // ps2 frame processed
reg     [3:0]   ps2bit;     // ps2 frame bit counter (0...10)

// z88 matrix of 64 keys A8(D0:D7), A9(D0:D7), ... A15(D0:D7)
reg     [63:0]  kbmat;      // shifted to kbd port according A8-A15

assign kbmat_out = kbmat;

always @(negedge ps2clk)
begin
  if (reset_n == 1'b0) begin
    ps2ok <= 1'b0;
    ps2bit <= 4'b0;
    ps2key <= 8'b0;
    extkey <= 1'b0;
    rlskey <= 1'b0;
  end else begin
    case(ps2bit[3:0])
      4'h00: ps2ok <= 1'b0; // start bit
      4'h01: ps2key[0] <= ps2dat;
      4'h02: ps2key[1] <= ps2dat;
      4'h03: ps2key[2] <= ps2dat;
      4'h04: ps2key[3] <= ps2dat;
      4'h05: ps2key[4] <= ps2dat;
      4'h06: ps2key[5] <= ps2dat;
      4'h07: ps2key[6] <= ps2dat;
      4'h08: ps2key[7] <= ps2dat;
      4'h09: begin
        case (ps2key[7:0])
          8'hE0: extkey <= 1'b1;
          8'hF0: rlskey <= 1'b1;
          default: ps2ok <= 1'b1;  // refresh kbmat
        endcase
      end
      default: ps2ok <= 1'b0; // stop bit
    endcase

    if (ps2bit == 4'h0A) begin
      ps2bit <= 4'h00;
    end else begin
      ps2bit <= ps2bit + 4'h01;
    end

  end
end

always @(posedge ps2ok)
begin
  case(ps2key[7:0])
    //  A8 column
    8'h3E: kbmat[0]  <= ~extkey & ~rlskey;   // 8
    8'h3D: kbmat[1]  <= ~extkey & ~rlskey;   // 7
    8'h31: kbmat[2]  <= ~extkey & ~rlskey;   // N
    8'h33: kbmat[3]  <= ~extkey & ~rlskey;   // H
    8'h35: kbmat[4]  <= ~extkey & ~rlskey;   // Y
    8'h36: kbmat[5]  <= ~extkey & ~rlskey;   // 6
    8'h5A: kbmat[6]  <= ~extkey & ~rlskey;   // Enter
    8'h66: kbmat[7]  <= ~extkey & ~rlskey;   // Del
    //  A9 column
    8'h43: kbmat[8]  <= ~extkey & ~rlskey;   // I
    8'h3C: kbmat[9]  <= ~extkey & ~rlskey;   // U
    8'h32: kbmat[10] <= ~extkey & ~rlskey;   // B
    8'h34: kbmat[11] <= ~extkey & ~rlskey;   // G
    8'h2C: kbmat[12] <= ~extkey & ~rlskey;   // T
    8'h2E: kbmat[13] <= ~extkey & ~rlskey;   // 5
    8'h75: kbmat[14] <=  extkey & ~rlskey;   // Up
    8'h5D: kbmat[15] <= ~extkey & ~rlskey;   // \
    //  A10 column
    8'h44: kbmat[16] <= ~extkey & ~rlskey;  // O
    8'h3B: kbmat[17] <= ~extkey & ~rlskey;  // J
    8'h2A: kbmat[18] <= ~extkey & ~rlskey;  // V
    8'h2B: kbmat[19] <= ~extkey & ~rlskey;  // F
    8'h2D: kbmat[20] <= ~extkey & ~rlskey;  // R
    8'h25: kbmat[21] <= ~extkey & ~rlskey;  // 4
    8'h72: kbmat[22] <=  extkey & ~rlskey;  // Down
    8'h55: kbmat[23] <= ~extkey & ~rlskey;  // =
    //  A11 column
    8'h46: kbmat[24] <= ~extkey & ~rlskey;  // 9
    8'h42: kbmat[25] <= ~extkey & ~rlskey;  // K
    8'h21: kbmat[26] <= ~extkey & ~rlskey;  // C
    8'h23: kbmat[27] <= ~extkey & ~rlskey;  // D
    8'h24: kbmat[28] <= ~extkey & ~rlskey;  // E
    8'h26: kbmat[29] <= ~extkey & ~rlskey;  // 3
    8'h74: kbmat[30] <=  extkey & ~rlskey;  // Right
    8'h4E: kbmat[31] <= ~extkey & ~rlskey;  // -
    //  A12 column
    8'h4D: kbmat[32] <= ~extkey & ~rlskey;  // P
    8'h3A: kbmat[33] <= ~extkey & ~rlskey;  // M
    8'h22: kbmat[34] <= ~extkey & ~rlskey;  // X
    8'h1B: kbmat[35] <= ~extkey & ~rlskey;  // S
    8'h1D: kbmat[36] <= ~extkey & ~rlskey;  // W
    8'h1E: kbmat[37] <= ~extkey & ~rlskey;  // 2
    8'h6B: kbmat[38] <=  extkey & ~rlskey;  // Left
    8'h5B: kbmat[39] <= ~extkey & ~rlskey;  // ]
    //  A13 column
    8'h45: kbmat[40] <= ~extkey & ~rlskey;  // 0
    8'h4B: kbmat[41] <= ~extkey & ~rlskey;  // L
    8'h1A: kbmat[42] <= ~extkey & ~rlskey;  // Z
    8'h1C: kbmat[43] <= ~extkey & ~rlskey;  // A
    8'h15: kbmat[44] <= ~extkey & ~rlskey;  // Q
    8'h16: kbmat[45] <= ~extkey & ~rlskey;  // 1
    8'h29: kbmat[46] <= ~extkey & ~rlskey;  // Space
    8'h54: kbmat[47] <= ~extkey & ~rlskey;  // [
    //  A14 column
    8'h52: kbmat[48] <= ~extkey & ~rlskey;  // "
    8'h4C: kbmat[49] <= ~extkey & ~rlskey;  // ;
    8'h41: kbmat[50] <= ~extkey & ~rlskey;  // ,
    8'h04: kbmat[51] <= ~extkey & ~rlskey;  // Menu (F3)
    8'h14: kbmat[52] <=           ~rlskey;  // <> (Ctrl)
    8'h0D: kbmat[53] <= ~extkey & ~rlskey;  // Tab
    8'h12: kbmat[54] <= ~extkey & ~rlskey;  // LShift
    8'h05: kbmat[55] <= ~extkey & ~rlskey;  // Help (F1)
    //  A15 column
    8'h0E: kbmat[56] <= ~extkey & ~rlskey;  // £
    8'h4A: kbmat[57] <= ~extkey & ~rlskey;  // /
    8'h49: kbmat[58] <= ~extkey & ~rlskey;  // .
    8'h58: kbmat[59] <= ~extkey & ~rlskey;  // Caps
    8'h06: kbmat[60] <= ~extkey & ~rlskey;  // Index (F2)
    8'h76: kbmat[61] <= ~extkey & ~rlskey;  // Esc
    8'h11: kbmat[62] <=           ~rlskey;  // [] (Alt)
    8'h59: kbmat[63] <= ~extkey & ~rlskey;  // RShift
    default: ;
  endcase
end

endmodule