module z88_screen
(
    // Clock and reset
    input           rst,          // Global reset
    input           clk,          // Master clock (50 MHz)
    input           clk_ena,      // 12.5 MHz equivalent clock
    input           bus_ph,       // Bus phase (0 : LCD, 1 : Z80)

    // Z80 bus
    input           z80_io_wr,    // Z80 I/O write
    input    [15:0] z80_addr,     // Z80 address bus
    input     [7:0] z80_wdata,    // Z80 data bus (write)

    // LCD control
    input           new_fr_tgl,   // Fetch a new frame (toggle)
    output          lcd_rden,     // Reading LCD data
    output   [21:0] lcd_addr,     // 4 MB address space
    input           lcd_vld,      // 8-bit data is ready
    input     [7:0] lcd_rdata,    // 8-bit data from RAM/ROM

    // LCD VRAM
    output          vram_we,      // Write enable
    output    [2:0] vram_data,    // Gray attribute + 2 pixels
    output   [14:0] vram_addr     // 320 columns x 64 rows
);
    // Blinking effect half period
    parameter BLINK_PERIOD = 30;

    // ========================================================================
    // LCD Registers Write
    // ========================================================================

    // LCD screen registers
    reg [12:0] r_PB0;  // Lores0 (RAM, 64 char, 512B)
    reg  [9:0] r_PB1;  // Lores1 (ROM, 448 char, 3.5K)
    reg  [8:0] r_PB2;  // Hires0 (RAM, 768 char, 6K)
    reg [10:0] r_PB3;  // Hires1 (ROM, 256 char, 2K)
    reg [10:0] r_SBR;  // Screen Base File (RAM, 128 attr*8, 2K)

    always @(posedge rst or posedge clk) begin : LCD_REGS_WR

        if (rst) begin
            r_PB0 <= 13'd0;
            r_PB1 <= 10'd0;
            r_PB2 <= 9'd0;
            r_PB3 <= 11'd0;
            r_SBR <= 11'd0;
        end
        else begin
            // I/O Register Write
            if (z80_io_wr & clk_ena & bus_ph) begin
                case (z80_addr[7:0])
                    8'h70: r_PB0 <= { z80_addr[12:8], z80_wdata };
                    8'h71: r_PB1 <= { z80_addr[ 9:8], z80_wdata };
                    8'h72: r_PB2 <= { z80_addr[   8], z80_wdata };
                    8'h73: r_PB3 <= { z80_addr[10:8], z80_wdata };
                    8'h74: r_SBR <= { z80_addr[10:8], z80_wdata };
                    default: ;
                endcase
            end
        end
    end

    // ========================================================================
    // LCD matrix counters
    // ========================================================================

    reg       r_lcd_run;   // LCD matrix scanning is running
    reg [2:0] r_lcd_cyc;   // LCD cycle (0 : SBA LSB, 1 : SBA MSB, 2 : )
    reg [6:0] r_col_ctr;   // 108 columns
    reg [5:0] r_row_ctr;   // 64 rows
    reg       r_lcd_eol;   // End of LCD line
    reg       r_lcd_eof;   // End of LCD frame
    reg       r_blink;     // Blinking effect flag

    always @(posedge rst or posedge clk) begin : LCD_MATRIX_CTR
        reg [5:0] v_fr_ctr;    // Frame counter (for blinking effect)
        reg [2:0] v_new_fr_cc; // New frame (from VGA controller)

        if (rst) begin
            r_lcd_run   <= 1'b0;
            r_lcd_cyc   <= 3'b000;
            r_col_ctr   <= 7'd0;
            r_row_ctr   <= 6'd0;
            r_lcd_eol   <= 1'b0;
            r_lcd_eof   <= 1'b0;
            r_blink     <= 1'b0;
            v_fr_ctr    <= BLINK_PERIOD[5:0];
            v_new_fr_cc <= 3'b000;
        end
        else begin
            if (clk_ena & bus_ph) begin
                // Row and column counters
                if (r_lcd_run & r_lcd_cyc[2]) begin
                    if (r_lcd_eol) begin
                        r_row_ctr <= r_row_ctr + 6'd1;
                        r_col_ctr <= 7'd0;
                    end
                    else begin
                        r_col_ctr <= r_col_ctr + 7'd1;
                    end
                end

                if (^v_new_fr_cc[2:1]) begin
                    // Start LCD scanning
                    r_lcd_run <= 1'b1;
                    r_lcd_cyc <= 3'b001;
                    // Frame counter
                    if (v_fr_ctr == 6'd0) begin
                        r_blink  <= ~r_blink;
                        v_fr_ctr <= BLINK_PERIOD[5:0];
                    end
                    else begin
                        v_fr_ctr <= v_fr_ctr + 6'd1;
                    end
                end
                else if (r_lcd_eol & r_lcd_eof & r_lcd_cyc[2]) begin
                    // Stop LCD scanning
                    r_lcd_run <= 1'b0;
                    r_lcd_cyc <= 3'b000;
                end
                else begin
                    // LCD scanning is running
                    r_lcd_cyc <= { r_lcd_cyc[1:0], r_lcd_cyc[2] };
                end
            end

            // End of line flag
            r_lcd_eol <= (r_col_ctr == 7'd107) ? 1'b1 : 1'b0;
            // End of frame flag
            r_lcd_eof <= (r_row_ctr == 6'd63) ? 1'b1 : 1'b0;

            // Edge detect
            if (clk_ena & bus_ph) begin
                v_new_fr_cc[2] <= v_new_fr_cc[1];
            end
            // Clock domain crossing
            v_new_fr_cc[1] <= v_new_fr_cc[0];
            v_new_fr_cc[0] <= new_fr_tgl;
        end
    end

    // ========================================================================
    // LCD address generator
    // ========================================================================

    reg [21:0] r_lcd_addr; // 4 MB address space
    reg [21:9] r_pix_page; // Character pixel page


    always @(posedge rst or posedge clk) begin : PIX_PAGE_GEN

        if (rst) begin
            r_pix_page <= 13'd0;
        end
        else begin
            // Address translation
            casez ({ w_hires & ~w_cursor, r_SBA[9:6] })
                // Lo-res RAM (7 x 64 chars)
                5'b0?0?? : r_pix_page <= { r_PB1[9:0], r_SBA[8:6] };
                5'b0?10? : r_pix_page <= { r_PB1[9:0], r_SBA[8:6] };
                5'b0?110 : r_pix_page <= { r_PB1[9:0], r_SBA[8:6] };
                // Lo-res ROM (1 x 64 chars)
                5'b0?111 : r_pix_page <= { r_PB0[12:0]        };
                // Hi-res ROM (3 x 256 chars)
                5'b100?? : r_pix_page <= { r_PB2[8:0], r_SBA[9:6] };
                5'b101?? : r_pix_page <= { r_PB2[8:0], r_SBA[9:6] };
                5'b110?? : r_pix_page <= { r_PB2[8:0], r_SBA[9:6] };
                // Hi-res RAM (1 x 256 chars)
                5'b111?? : r_pix_page <= { r_PB3[10:0], r_SBA[7:6] };
            endcase
        end
    end

    always @(*) begin : LCD_ADDR_GEN

        // Address generation
        if (~bus_ph & r_lcd_run) begin
            r_lcd_addr =
                // Read SBA LSB
                {22{r_lcd_cyc[0]}} & { r_SBR[10:0], r_row_ctr[5:3], r_col_ctr[6:0], 1'b0 } |
                // Read SBA MSB
                {22{r_lcd_cyc[1]}} & { r_SBR[10:0], r_row_ctr[5:3], r_col_ctr[6:0], 1'b1 } |
                // Read Pixels
                {22{r_lcd_cyc[2]}} & { r_pix_page[21:9], r_SBA[5:0], r_row_ctr[2:0] };
        end
        else begin
            r_lcd_addr = 22'd0;
        end
    end

    assign lcd_rden = r_lcd_run;
    assign lcd_addr = r_lcd_addr;

    // ========================================================================
    // LCD data
    // ========================================================================

    reg [13:0] r_SBA;       // Attributes
    reg  [7:0] r_gfx_p0;    // Pixels data
    reg        r_gfx_en_p0; // Pixels data are valid

    wire w_hires  =  r_SBA[13];            // High resolution
    wire w_invert =  r_SBA[12];            // Inverted
    wire w_blink  =  r_SBA[11];            // 1Hz Blinking
    wire w_gray   =  r_SBA[10];            // Gray colour
    wire w_under  = ~r_SBA[13] & r_SBA[9]; // Underlined
    wire w_cursor = &r_SBA[13:11];         // Cursor
    wire w_null   = (r_SBA[13:10] == 4'b1101)
                  ? 1'b1 : 1'b0;           // Null character

    always @(posedge rst or posedge clk) begin : LCD_DATA_READ

        if (rst) begin
            r_SBA       <= 14'b0;
            r_gfx_p0    <= 8'h00;
            r_gfx_en_p0 <= 1'b0;
        end
        else begin
            // Read SBA LSB
            if (lcd_vld & r_lcd_cyc[0]) begin
                r_SBA[7:0] <= lcd_rdata[7:0];
            end
            // Read SBA MSB
            if (lcd_vld & r_lcd_cyc[1]) begin
                r_SBA[13:8] <= lcd_rdata[5:0];
            end
            // Read Pixels
            if (lcd_vld & r_lcd_cyc[2]) begin
                r_gfx_p0[7:0] <= lcd_rdata[7:0];
            end
            r_gfx_en_p0 <= lcd_vld & r_lcd_cyc[2];
        end
    end

    // ========================================================================
    // LCD pixel pipeline
    // ========================================================================

    reg  [8:0] r_gfx_dat_p1; // Pixels data
    reg        r_gfx_en_p1;  // Pixels data are valid
    reg  [5:0] r_gfx_row_p1; // Row number
    reg        r_gfx_eol_p1; // End of line flag

    always @(posedge rst or posedge clk) begin : LCD_PIXEL_P1
        reg [7:0] v_gfx_p0;

        if (rst) begin
            r_gfx_dat_p1 <= { 1'b0, 8'h00 };
            r_gfx_en_p1  <= 1'b0;
            r_gfx_row_p1 <= 6'd0;
            r_gfx_eol_p1 <= 1'b0;
        end
        else begin
            if (r_gfx_en_p0) begin
                // Underline effect : low-res and line #7
                v_gfx_p0 = (&{ w_under, r_row_ctr[2:0] }) ? 8'hFF : r_gfx_p0;
                // Reverse and/or 1 second flashing effect
                case ({ w_invert, w_blink })
                    2'b00 : r_gfx_dat_p1[7:0] <=              v_gfx_p0;
                    2'b01 : r_gfx_dat_p1[7:0] <= (r_blink) ?  v_gfx_p0 : 8'h00;
                    2'b10 : r_gfx_dat_p1[7:0] <=             ~v_gfx_p0;
                    2'b11 : r_gfx_dat_p1[7:0] <= (r_blink) ? ~v_gfx_p0 : v_gfx_p0;
                endcase
                // Gray effect
                r_gfx_dat_p1[8] <= w_gray;
                // Row number
                r_gfx_row_p1 <= r_row_ctr;
                // End of line
                r_gfx_eol_p1 <= r_lcd_eol;
            end
            // Data enable
            r_gfx_en_p1 <= r_gfx_en_p0;
        end
    end

    reg  [8:0] r_gfx_dat_p2; // Pixels data shift register
    reg  [3:0] r_gfx_en_p2;  // Pixels data are valid
    reg  [5:0] r_gfx_row_p2; // Row number
    reg        r_gfx_eol_p2; // End of line flag
    reg  [8:0] r_gfx_ctr_p2; // Pixel counter

    always @(posedge rst or posedge clk) begin : LCD_PIXEL_P2

        if (rst) begin
            r_gfx_dat_p2 <= { 1'b0, 8'b00_00_00_00 };
            r_gfx_en_p2  <= 4'b0000;
            r_gfx_row_p2 <= 6'd0;
            r_gfx_eol_p2 <= 1'b0;
            r_gfx_ctr_p2 <= 9'd0;
        end
        else begin
            if (r_gfx_en_p1) begin
                if (w_null) begin
                    // No pixel output
                    r_gfx_dat_p2 <= r_gfx_dat_p1[8:0];
                    r_gfx_en_p2  <= 4'b0000;
                end
                else if (w_cursor | ~w_hires) begin
                    // Low-res : 6-pixel output
                    r_gfx_dat_p2 <= { r_gfx_dat_p1[8], r_gfx_dat_p1[5:0], 2'b00 };
                    r_gfx_en_p2  <= 4'b1110;
                end
                else begin
                    // High-res : 8-pixel output
                    r_gfx_dat_p2 <= r_gfx_dat_p1[8:0];
                    r_gfx_en_p2  <= 4'b1111;
                end
                // Row number
                r_gfx_row_p2 <= r_gfx_row_p1 + 6'd16; // Trick : to match VGA lines numbers
                // End of line flag
                r_gfx_eol_p2 <= r_gfx_eol_p1;
            end
            else begin
                // Shift 2 pixels out
                r_gfx_dat_p2[7:0] <= { r_gfx_dat_p2[5:0], 2'b00 };
                r_gfx_en_p2       <= { r_gfx_en_p2[2:0], 1'b0 };
                // Increment address
                if (r_gfx_en_p2[3]) begin
                    r_gfx_ctr_p2 <= r_gfx_ctr_p2 + 9'd1;
                end
                // Reset address at the end of the line
                else if (r_gfx_eol_p2) begin
                    r_gfx_ctr_p2 <= 9'd0;
                end
            end
        end
    end

    assign vram_we   = r_gfx_en_p2[3];
    assign vram_data = r_gfx_dat_p2[8:6];
    assign vram_addr = { r_gfx_ctr_p2, r_gfx_row_p2 };

endmodule
