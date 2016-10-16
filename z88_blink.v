module z88_blink
(
    // Clock and reset
    input           rst,          // Global reset
    input           clk,          // Master clock (50 MHz)
    input           clk_ena,      // 12.5 MHz equivalent clock
    input           bus_ph,       // Bus phase (0 : LCD, 1 : Z80)
    
    // Z80 bus
    input           z80_io_rd,    // Z80 I/O read
    input           z80_io_wr,    // Z80 I/O write
    input    [15:0] z80_addr,     // Z80 address bus
    input     [7:0] z80_wdata,    // Z80 data bus (write)
    output    [7:0] z80_rdata,    // Z80 data bus (read)
    input           z80_hlt_n,    // HALT Coma / Standby command
    output          z80_int_n,    // Maskable interrupt
    output          z80_nmi_n,    // Non maskable interrupt
    
    output   [21:0] cpu_addr,     // 4 MB address space
    
    output          lcd_on,       // LCD is ON
    
    output          stby,         // Standby mode
    
    input    [63:0] kb_matrix,    // 64-key keyboard matrix
    output    [7:0] kbd_val,      // KBD register value (debug)
    
    input           flap_sw       // Flap switch
);

    // ========================================================================
    // MMU Registers Write
    // ========================================================================
    
    // Bank switching (write only)
    reg  [7:0] r_SR0 /* verilator public */;
    reg  [7:0] r_SR1 /* verilator public */;
    reg  [7:0] r_SR2 /* verilator public */;
    reg  [7:0] r_SR3 /* verilator public */;

    // Segment Registers Write
    always @(posedge rst or posedge clk) begin : MMU_REGS_WR
    
        if (rst) begin
            r_SR0 <= 8'h00;
            r_SR1 <= 8'h00;
            r_SR2 <= 8'h00;
            r_SR3 <= 8'h00;
        end
        else begin
            // IO Register Write
            if (z80_io_wr & clk_ena & bus_ph) begin 
                case(z80_addr[7:0])
                    8'hD0 : r_SR0 <= z80_wdata;
                    8'hD1 : r_SR1 <= z80_wdata;
                    8'hD2 : r_SR2 <= z80_wdata;
                    8'hD3 : r_SR3 <= z80_wdata;
                    default : ;
                endcase
            end
        end
    end
    
    // ========================================================================
    // Real time clock
    // ========================================================================
    
    reg [14:0] r_div_5ms; // 6.25 MHz to 200 Hz divider
    reg  [7:0] r_TIM0;    // 5ms tick counter (0-199)
    reg  [5:0] r_TIM1;    // Seconds counter (0-59)
    reg  [7:0] r_TIM2;    // Minutes counter LOW (0-255)
    reg  [7:0] r_TIM3;    // Minutes counter MID (0-255)
    reg  [4:0] r_TIM4;    // Minutes counter HI (0-31)
    reg  [2:0] r_rtc_irq; // Interrupt requests
    
    always @(posedge clk) begin : REAL_TIME_CLK
        reg v_tick_5ms;
        reg v_tick_640ms;
        reg v_tick_1sec;
        reg v_tick_1min;
        reg v_inc_mid;
        reg v_inc_msb;
    
        if ((rst & r_flap_cc[2]) | r_COM[4]) begin
            r_div_5ms    <= 15'd1;
            r_TIM0       <= 8'd0;
            r_TIM1       <= 6'd0;
            r_TIM2       <= 8'd0;
            r_TIM3       <= 8'd0;
            r_TIM4       <= 5'd0;
            r_rtc_irq    <= 3'b000;
            
            v_tick_5ms   <= 1'b0;
            v_tick_640ms <= 1'b0;
            v_tick_1sec  <= 1'b0;
            v_tick_1min  <= 1'b0;
            v_inc_mid    <= 1'b0;
            v_inc_msb    <= 1'b0;
        end
        else begin
            if (clk_ena & bus_ph) begin
                if (v_tick_5ms) begin
                    if (v_tick_640ms) begin
                        if (v_tick_1min) begin
                            if (v_inc_mid) begin
                                if (v_inc_msb) begin
                                    // Minutes HI counter
                                    r_TIM4 <= r_TIM4 + 5'd1;
                                    // Minutes MID counter
                                    r_TIM3 <= 8'd0;
                                end
                                else begin
                                    r_TIM3 <= r_TIM3 + 8'd1;
                                end
                                // Minutes LOW counter
                                r_TIM2 <= 8'd0;
                            end
                            else begin
                                r_TIM2 <= r_TIM2 + 8'd1;
                            end
                            // Seconds counter
                            r_TIM1 <= 6'd0;
                        end
                        else begin
                            r_TIM1 <= r_TIM1 + 6'd1;
                        end
                    end
                    if (v_tick_1sec) begin
                        // 200 Hz counter
                        r_TIM0 <= 8'd0;
                    end
                    else begin
                        r_TIM0 <= r_TIM0 + 8'd1;
                    end
                    // 6.25 MHz counter
                    r_div_5ms <= 15'd1;
                end
                else begin
                    r_div_5ms <= r_div_5ms + 15'd1;
                end
            end
            
            // Interrupt requests
            r_rtc_irq[0] <= v_tick_5ms;
            r_rtc_irq[1] <= v_tick_5ms & v_tick_1sec;
            r_rtc_irq[2] <= v_tick_5ms & v_tick_1sec & v_tick_1min;
            
            // Comparators
            v_tick_5ms   <= (r_div_5ms == 15'd31250) ? 1'b1 : 1'b0;
            v_tick_640ms <= (r_TIM0 == 8'd127) ? 1'b1 : 1'b0;
            v_tick_1sec  <= (r_TIM0 == 8'd199) ? 1'b1 : 1'b0;
            v_tick_1min  <= (r_TIM1 == 6'd59) ? 1'b1 : 1'b0;
            v_inc_mid    <= (r_TIM2 == 8'd255) ? 1'b1 : 1'b0;
            v_inc_msb    <= (r_TIM3 == 8'd255) ? 1'b1 : 1'b0;
        end
    end

    // ========================================================================
    // Blink interrupts
    // ========================================================================
    
    // Common control register (I/O address $B0)
    reg  [7:0] r_COM /* verilator public */;
    // Interrupt masking register (I/O address $B1)
    reg  [7:0] r_INT;
    // Interrupt acknowledge register (I/O address $B6)
    reg  [7:0] r_ACK;
    // Interrupt status register (I/O address $B1)
    reg  [7:0] r_STA;
    // Timer interrupt acknowledge (I/O address $B4)
    reg  [2:0] r_TACK;
    // Timer interrupt mask (I/O address $B5)
    reg  [2:0] r_TMSK;
    // Timer interrupt status (I/O address $B5)
    reg  [2:0] r_TSTA;
    // Z80 interrupt
    reg        r_int_n;
    // Standby mode
    reg        r_stby;
    // Flap switch
    reg  [2:0] r_flap_cc;
    
    always @(posedge rst or posedge clk) begin : BLINK_IRQ
        
        if (rst) begin
            r_COM     <= 8'h00;
            r_INT     <= 8'h00;
            r_ACK     <= 8'h00;
            r_STA     <= 8'h00;
            r_TACK    <= 3'b000;
            r_TMSK    <= 3'b000;
            r_TSTA    <= 3'b000;
            r_int_n   <= 1'b1;
            r_stby    <= 1'b0;
            r_flap_cc <= 3'b000;
        end
        else begin
            // I/O Registers Write
            if (z80_io_wr & clk_ena & bus_ph) begin
                case (z80_addr[7:0])
                    // COM
                    8'hB0 : r_COM  <= z80_wdata[7:0];
                    // INT
                    8'hB1 : r_INT  <= z80_wdata[7:0];
                    // TACK
                    8'hB4 : r_TACK <= z80_wdata[2:0];
                    // TMSK
                    8'hB5 : r_TMSK <= z80_wdata[2:0];
                    // ACK
                    8'hB6 : r_ACK  <= z80_wdata[7:0];
                    default : ;
                endcase
            end
            // Clear acknowledge flags
            else begin
                // KEY
                if (!r_STA[2]) r_ACK[2] <= 1'b0;
                // FLAP
                if (!r_STA[5]) r_ACK[5] <= 1'b0;
                // Tick
                if (!r_TSTA[0]) r_TACK[0] <= 1'b0;
                // Second
                if (!r_TSTA[1]) r_TACK[1] <= 1'b0;
                // Minute
                if (!r_TSTA[2]) r_TACK[2] <= 1'b0;
            end
            
            // Z80 interrupt (FLAP, TIME, KEY, GINT)
            r_int_n <= ~((r_STA[5] | r_STA[2] | r_STA[0]) & r_INT[0]);
            
            // FLAP interrupt
            if (r_flap_cc[2:1] == 2'b01)
                r_STA[5] <= r_INT[5];
            else if (r_ACK[5])
                r_STA[5] <= 1'b0;
            r_STA[7] <= r_flap_cc[2];
            
            // KEY interrupt
            if (r_key_low & r_stby)
                r_STA[2] <= r_INT[2];
            else if (r_ACK[2])
                r_STA[2] <= 1'b0;
                
            // Timer interrupts
            r_STA[0] <= (r_TSTA != 3'b000) ? r_INT[1] : 1'b0;
                
            // Tick interrupt
            if (r_rtc_irq[0])
                r_TSTA[0] <= r_TMSK[0];
            else if (r_TACK[0])
                r_TSTA[0] <= 1'b0;
            
            // Second interrupt
            if (r_rtc_irq[1])
                r_TSTA[1] <= r_TMSK[1];
            else if (r_TACK[1])
                r_TSTA[1] <= 1'b0;
            
            // Minute interrupt
            if (r_rtc_irq[2])
                r_TSTA[2] <= r_TMSK[2];
            else if (r_TACK[2])
                r_TSTA[2] <= 1'b0;
            
            // Clock domain crossing
            r_flap_cc <= { r_flap_cc[1:0], flap_sw };
        end
    end
    
    assign lcd_on = r_COM[0];
    
    assign z80_int_n = r_int_n;
    assign z80_nmi_n = 1'b1;
    
    // ========================================================================
    // Blink registers read
    // ========================================================================
    
    reg [7:0] r_z80_rdata;
    
    always @(posedge rst or posedge clk) begin : BLINK_REGS_RD
    
        if (rst) begin
            r_z80_rdata <= 8'h00;
        end
        else begin
            // I/O Registers Read
            if (clk_ena & bus_ph) begin
                if (z80_io_rd) begin
                    case(z80_addr[7:0])
                        // STA : interrupt status
                        8'hB1 : r_z80_rdata <= r_STA;
                        // KBD : key pressed (TODO: reading KBD when KWAIT set will snooze)
                        8'hB2 : r_z80_rdata <= r_KBD;
                        // TSTA : Timer status
                        8'hB5 : r_z80_rdata <= { 5'b0, r_TSTA };
                        // TIM0 : 5ms tick counter
                        8'hD0 : r_z80_rdata <= r_TIM0;
                        // TIM1 : seconds counter
                        8'hD1 : r_z80_rdata <= { 2'b0, r_TIM1 };
                        // TIM2 : minutes counter
                        8'hD2 : r_z80_rdata <= r_TIM2;
                        // TIM3 : 256 minutes counter
                        8'hD3 : r_z80_rdata <= r_TIM3;
                        // TIM4 : 64K minutes counter
                        8'hD4 : r_z80_rdata <= { 3'b0, r_TIM4 };
                        // UIT : UART interrupt status (required but not implemented)
                        8'hE5 : r_z80_rdata <= 8'h00;
                        // Unknown
                        default: r_z80_rdata <= 8'h00;
                    endcase
                end
                else begin
                    r_z80_rdata <= 8'h00;
                end
            end
        end
    end
    
    assign z80_rdata = r_z80_rdata;

    // ========================================================================
    // CPU address translation
    // ========================================================================
    
    reg [21:0] r_cpu_addr; // 4 MB address space

    /*
    always @(posedge rst or posedge clk) begin : CPU_ADDR_GEN
    
        if (rst) begin
            r_cpu_addr <= 22'd0;
        end
        else begin
            // Address translation
            if (bus_ph) begin
                casez (z80_addr[15:13])
                    // 0000-1FFF : Bank $00 !RAMS, Bank $20 RAMS
                    3'b000 : r_cpu_addr <= { 2'b00, r_COM[2], 6'b0, z80_addr[12:0] };
                    // 2000-3FFF
                    3'b001 : r_cpu_addr <= { r_SR0[7:1], 1'b0, r_SR0[0], z80_addr[12:0] };
                    // 4000-7FFF
                    3'b01? : r_cpu_addr <= { r_SR1[7:0], z80_addr[13:0] };
                    // 8000-BFFF
                    3'b10? : r_cpu_addr <= { r_SR2[7:0], z80_addr[13:0] };
                    // C000-FFFF
                    3'b11? : r_cpu_addr <= { r_SR3[7:0], z80_addr[13:0] };
                endcase
            end
            else begin
                r_cpu_addr <= 22'd0;
            end
        end
    end
    */
    
    always @(*) begin : CPU_ADDR_GEN
    
        // Address translation
        if (bus_ph) begin
            casez (z80_addr[15:13])
                // 0000-1FFF : Bank $00 !RAMS, Bank $20 RAMS
                3'b000 : r_cpu_addr = { 2'b00, r_COM[2], 6'b0, z80_addr[12:0] };
                // 2000-3FFF
                3'b001 : r_cpu_addr = { r_SR0[7:1], 1'b0, r_SR0[0], z80_addr[12:0] };
                // 4000-7FFF
                3'b01? : r_cpu_addr = { r_SR1[7:0], z80_addr[13:0] };
                // 8000-BFFF
                3'b10? : r_cpu_addr = { r_SR2[7:0], z80_addr[13:0] };
                // C000-FFFF
                3'b11? : r_cpu_addr = { r_SR3[7:0], z80_addr[13:0] };
            endcase
        end
        else begin
            r_cpu_addr = 22'd0;
        end
    end
    
    assign cpu_addr = r_cpu_addr;
    
    // ========================================================================
    // Keyboard scanning
    // ========================================================================
    
    reg [7:0] r_kbd_val;
    reg [7:0] r_KBD;
    reg       r_key_low;
    
    always @(posedge clk) begin : KB_SCAN
        reg [7:0] v_kb_col [0:7];
    
        r_KBD <= v_kb_col[0] & v_kb_col[1] & v_kb_col[2] & v_kb_col[3]
               & v_kb_col[4] & v_kb_col[5] & v_kb_col[6] & v_kb_col[7];
    
        if (clk_ena) begin
            v_kb_col[0] <= (!z80_addr[ 8]) ? ~kb_matrix[ 7: 0] : 8'b11111111;
            v_kb_col[1] <= (!z80_addr[ 9]) ? ~kb_matrix[15: 8] : 8'b11111111;
            v_kb_col[2] <= (!z80_addr[10]) ? ~kb_matrix[23:16] : 8'b11111111;
            v_kb_col[3] <= (!z80_addr[11]) ? ~kb_matrix[31:24] : 8'b11111111;
            v_kb_col[4] <= (!z80_addr[12]) ? ~kb_matrix[39:32] : 8'b11111111;
            v_kb_col[5] <= (!z80_addr[13]) ? ~kb_matrix[47:40] : 8'b11111111;
            v_kb_col[6] <= (!z80_addr[14]) ? ~kb_matrix[55:48] : 8'b11111111;
            v_kb_col[7] <= (!z80_addr[15]) ? ~kb_matrix[63:56] : 8'b11111111;
            r_key_low   <= (kb_matrix != 64'b0) ? 1'b1 : 1'b0;
        end
        
        // Debug
        if (z80_io_rd & clk_ena & bus_ph) begin
            if (z80_addr[7:0] == 8'hB2) begin
                r_kbd_val <= r_KBD;
            end
        end
    end
    
    assign kbd_val = r_kbd_val;
    
endmodule