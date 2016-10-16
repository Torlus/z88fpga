module ps2_keyboard
(
  // Clock and reset
  input        rst,      // Global reset
  input        clk,      // Master clock (28/56/85 MHz)
  input        cdac_r,   // CDAC_n rising edge
  input        cdac_f,   // CDAC_n falling edge
  // Keyboard LEDs
  input        caps_led, // Caps lock LED
  input        num_led,  // Num lock LED
  input        disk_led, // Scroll lock LED
  // PS/2 keyboard port
  inout        ps2_kclk, // PS/2 keyboard clock (O.C.)
  inout        ps2_kdat, // PS/2 keyboard data (O.C.)
  // PS/2 keyboard data
  output       kb_vld,   // Keyboard data valid
  output [7:0] kb_data   // Keyboard data
);

////////////////////////////
// Open collector outputs //
////////////////////////////

wire        w_kdat_out;

assign w_kdat_out = r_tx_buf[0] | r_tx_led1 | r_tx_led2;

assign ps2_kclk = (~r_kclk_out) ? 1'b0 : 1'bZ;
assign ps2_kdat = (~w_kdat_out) ? 1'b0 : 1'bZ;

///////////////////////////
// Clock domain crossing //
///////////////////////////

reg   [1:0] r_kdat_cc;
reg   [2:0] r_kclk_cc;
reg         r_kclk_edge;

always@(posedge clk) begin
  if (cdac_r) begin
    // Inputs synchronization
    r_kclk_cc <= { r_kclk_cc[1:0], ps2_kclk };
    r_kdat_cc <= { r_kdat_cc[0], ps2_kdat };
  end
  if (cdac_f) begin
    // Falling edge detection on KCLK
    r_kclk_edge <= (r_kclk_cc[2:1] == 2'b10) ? 1'b1 : 1'b0;
  end
end


//////////////////////////////////////
// 500 us, 1 ms and 36 ms time-outs //
//////////////////////////////////////

reg  [19:0] r_timer;
wire        w_tout_500us;
wire        w_tout_1ms;
wire        w_tout_36ms;

always@(posedge rst or posedge clk) begin
  if (rst)
    r_timer <= 20'd0;
  else if (cdac_r) begin
    if (r_tmr_clr)
      r_timer <= 20'd0;
    else
      r_timer <= r_timer + 20'd1;
  end
end

assign w_tout_500us = r_timer[13];
assign w_tout_1ms   = r_timer[14];
assign w_tout_36ms  = r_timer[19];

//////////////////////////////
// Keyboard transmit buffer //
//////////////////////////////

reg  [11:0] r_tx_buf;  // Transmit buffer
reg         r_tx_done; // Transmit done
wire  [2:0] w_tx_leds; // Transmitted LEDs states

always@(posedge clk) begin
  if (cdac_r) begin
    if (r_tx_led1 | r_tx_led2)
      r_tx_buf <= (r_tx_led1)
                ? { 3'b111, 8'hED, 1'b0 } // Set/reset LEDs command (0xED)
                : { 2'b11, ~(^w_tx_leds), 5'b00000, w_tx_leds, 1'b0 }; // LEDs states
    else if (r_kclk_edge) begin
      // Falling edge on KCLK : shift one bit out
      if (!r_tx_done)
        r_tx_buf <= { 1'b0, r_tx_buf[11:1] };
    end
  end
  if (cdac_f) begin
    // End of transmit
    r_tx_done <= (r_tx_buf[11:0] == 12'b000000000001) ? 1'b1 : 1'b0;
  end
end

// LEDs states
assign w_tx_leds = { caps_led, num_led, disk_led };

/////////////////////////////
// Keyboard receive buffer //
/////////////////////////////

reg   [7:0] r_rx_buf; // Receive buffer
reg   [3:0] r_rx_ctr; // Bit counter
reg         r_rx_par; // Data odd parity
reg         r_rx_vld; // Data valid
reg   [1:0] r_rx_fsm; // Receive state

localparam [1:0]
    PS2_RX_IDLE = 2'b00,
    PS2_RX_DATA = 2'b01,
    PS2_RX_STOP = 2'b10;

always@(posedge clk) begin
  if (cdac_r) begin
    if (r_rx_init) begin
      r_rx_ctr <= 4'd0;
      r_rx_par <= 1'b0;
      r_rx_vld <= 1'b0;
      //r_rx_buf <= 8'b11111111;
      r_rx_fsm <= PS2_RX_IDLE;
    end else begin
      case (r_rx_fsm)
        // Wait for the start bit
        PS2_RX_IDLE :
        begin
          r_rx_ctr <= 4'd0;
          r_rx_par <= 1'b0;
          r_rx_vld <= 1'b0;
          if (r_kclk_edge & ~r_kdat_cc[1])
            r_rx_fsm <= PS2_RX_DATA;
        end
        // Read data bits and parity bit
        PS2_RX_DATA :
        begin
          if (r_kclk_edge) begin
            r_rx_ctr <= r_rx_ctr + 4'd1;
            r_rx_par <= r_rx_par ^ r_kdat_cc[1];
            r_rx_vld <= 1'b0;
            if (r_rx_ctr[3])
              r_rx_fsm <= PS2_RX_STOP;
            else
              r_rx_buf <= { r_kdat_cc[1], r_rx_buf[7:1] };
          end
        end
        // Get the stop bit, check parity
        PS2_RX_STOP :
        begin
          if (r_kclk_edge) begin
            r_rx_vld <= r_kdat_cc[1] & r_rx_par;
            r_rx_fsm <= PS2_RX_IDLE;
          end
        end
        // We get lost, reset the state machine
        default :
        begin
          r_rx_ctr <= 4'd0;
          r_rx_par <= 1'b0;
          r_rx_vld <= 1'b0;
          r_rx_buf <= 8'b11111111;
          r_rx_fsm <= PS2_RX_IDLE;
        end
      endcase
    end
  end
end

assign kb_data = r_rx_buf;
assign kb_vld  = r_rx_vld & r_kb_fsm[3];


////////////////////////////
// Keyboard state machine //
////////////////////////////

reg         r_kclk_out;
reg         r_rx_init;
reg         r_tx_led1;
reg         r_tx_led2;
reg         r_tmr_clr;
reg   [3:0] r_kb_fsm;

localparam [3:0]
    PS2K_HOLD_CLK1 = 4'b0000,
    PS2K_REQ_SEND1 = 4'b0001,
    PS2K_SEND_LED1 = 4'b0010,
    PS2K_GET_ACK1  = 4'b0011,
    PS2K_HOLD_CLK2 = 4'b0100,
    PS2K_REQ_SEND2 = 4'b0101,
    PS2K_SEND_LED2 = 4'b0110,
    PS2K_GET_ACK2  = 4'b0111,
    PS2K_GET_KEY   = 4'b1000;

always@(posedge rst or posedge clk) begin
  if (rst) begin
    r_kclk_out <= 1'b1;
    r_rx_init  <= 1'b1;
    r_tx_led1  <= 1'b1;
    r_tx_led2  <= 1'b0;
    r_tmr_clr  <= 1'b1;
    r_kb_fsm   <= PS2K_HOLD_CLK1;
  end else if (cdac_r) begin
    // 36 ms time-out
    if (w_tout_36ms & ~r_kb_fsm[3]) begin
      r_kclk_out <= 1'b1;
      r_rx_init  <= 1'b1;
      r_tx_led1  <= 1'b1;
      r_tx_led2  <= 1'b0;
      r_tmr_clr  <= 1'b1;
      r_kb_fsm   <= PS2K_HOLD_CLK1;
    end else begin
      case (r_kb_fsm)
        PS2K_HOLD_CLK1 :
        begin
          r_kclk_out <= 1'b0; // KCLK low
          r_rx_init  <= 1'b1; // Rx disabled
          r_tx_led1  <= 1'b1; // Tx disabled
          r_tx_led2  <= 1'b0;
          r_tmr_clr  <= 1'b0; // Timer ON (500 us delay)
          // 500 us elapsed : send request to send
          if (w_tout_500us) r_kb_fsm <= PS2K_REQ_SEND1;
        end
        PS2K_REQ_SEND1 :
        begin
          r_kclk_out <= 1'b0; // KCLK low
          r_rx_init  <= 1'b1; // Rx disabled
          r_tx_led1  <= 1'b0; // Tx enabled : request to send
          r_tx_led2  <= 1'b0;
          r_tmr_clr  <= 1'b0; // Timer ON (1 ms delay)
          // 1 ms elapsed : send 0xED
          if (w_tout_1ms) r_kb_fsm <= PS2K_SEND_LED1;
        end
        PS2K_SEND_LED1 :
        begin
          r_kclk_out <= 1'b1; // KCLK high
          r_rx_init  <= 1'b1; // Rx disabled
          r_tx_led1  <= 1'b0; // Tx enabled : send 0xED
          r_tx_led2  <= 1'b0;
          r_tmr_clr  <= 1'b0; // Timer ON (32 ms time-out)
          // Transmit done : get acknowledge
          if (r_tx_done) begin
            r_tmr_clr <= 1'b1; // Restart the timer
            r_kb_fsm  <= PS2K_GET_ACK1;
          end
        end
        PS2K_GET_ACK1 :
        begin
          r_kclk_out <= 1'b1; // KCLK high
          r_rx_init  <= 1'b0; // Rx enabled
          r_tx_led1  <= 1'b0; // Re-init Tx
          r_tx_led2  <= 1'b1;
          r_tmr_clr  <= 1'b0; // Timer ON (32 ms time-out)
          // ACK byte received : send start bit
          if (r_rx_vld) begin
            r_tmr_clr <= 1'b1; // Restart the timer
            r_kb_fsm  <= PS2K_HOLD_CLK2;
          end
        end
        PS2K_HOLD_CLK2 :
        begin
          r_kclk_out <= 1'b0; // KCLK low
          r_rx_init  <= 1'b1; // Rx disabled
          r_tx_led1  <= 1'b0; // Tx disabled
          r_tx_led2  <= 1'b1;
          r_tmr_clr  <= 1'b0; // Timer ON (500 us delay)
          // 500 us elapsed : send request to send
          if (w_tout_500us) r_kb_fsm <= PS2K_REQ_SEND2;
        end
        PS2K_REQ_SEND2 :
        begin
          r_kclk_out <= 1'b0; // KCLK low
          r_rx_init  <= 1'b1; // Rx disabled
          r_tx_led1  <= 1'b0; // Tx enabled : request to send
          r_tx_led2  <= 1'b0;
          r_tmr_clr  <= 1'b0; // Timer ON (1 ms delay)
          // 1 ms elapsed : send LEDs states
          if (w_tout_1ms) r_kb_fsm <= PS2K_SEND_LED2;
        end
        PS2K_SEND_LED2 :
        begin
          r_kclk_out <= 1'b1; // KCLK high
          r_rx_init  <= 1'b1; // Rx disabled
          r_tx_led1  <= 1'b0; // Tx enabled : send LEDs states
          r_tx_led2  <= 1'b0;
          r_tmr_clr  <= 1'b0; // Timer ON (32 ms time-out)
          // Transmit done : get acknowledge
          if (r_tx_done) begin
            r_tmr_clr <= 1'b1; // Restart the timer
            r_kb_fsm  <= PS2K_GET_ACK2;
          end
        end
        PS2K_GET_ACK2 :
        begin
          r_kclk_out <= 1'b1; // KCLK high
          r_rx_init  <= 1'b0; // Rx enabled
          r_tx_led1  <= 1'b1; // Re-init Tx
          r_tx_led2  <= 1'b0;
          r_tmr_clr  <= 1'b0; // Timer ON (32 ms time-out)
          // ACK byte received : get key code
          if (r_rx_vld) begin
            r_rx_init <= 1'b1; // Re-init Rx
            r_tmr_clr <= 1'b1; // Restart the timer
            r_kb_fsm  <= PS2K_GET_KEY;
          end
        end
        PS2K_GET_KEY :
        begin
          r_kclk_out <= 1'b1; // KCLK high
          r_tx_led1  <= 1'b1; // Re-init Tx
          r_tx_led2  <= 1'b0;
          if (r_rx_vld) begin
            r_rx_init <= 1'b1; // Re-init Rx
            r_tmr_clr <= 1'b1; // Restart the timer
          end else begin
            r_rx_init <= 1'b0; // Rx enabled
            r_tmr_clr <= 1'b0; // Timer ON (32 ms time-out)
          end
          // 36 ms time-out : send the LEDs states
          if ((w_tout_36ms) && (r_rx_fsm == PS2_RX_IDLE)) begin
            r_tmr_clr <= 1'b1; // Restart the timer
            r_kb_fsm  <= PS2K_HOLD_CLK1;
          end
        end
        // We get lost, reset the state machine
        default :
        begin
          r_kclk_out <= 1'b1;
          r_rx_init  <= 1'b1;
          r_tx_led1  <= 1'b1;
          r_tx_led2  <= 1'b0;
          r_tmr_clr  <= 1'b1;
          r_kb_fsm   <= PS2K_HOLD_CLK1;
        end
      endcase
    end
  end
end

endmodule
