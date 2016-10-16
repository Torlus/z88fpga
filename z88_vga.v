module z88_vga
(
    // Clock and reset
    input           rst,          // Global reset
    input           clk,          // Master clock (50 MHz)
    input           clk_ena,      // 25 MHz equivalent clock
    
    // LCD control
    input           lcd_on,       // COM register bit #0
    output          new_fr_tgl,   // Fetch a new frame (toggle)
    input           vram_we,      // Write enable
    input     [2:0] vram_data,    // Gray attribute + 2 pixels
    input    [14:0] vram_addr,    // 320 columns x 64 rows
    
    // VGA output
    output          hsync,
    output          vsync,
    output          dena,
    output   [11:0] rgb
);

    // ========================================================================
    // Horizontal and vertical counters
    // ========================================================================
    
    reg       r_fr_tgl;
    reg [9:0] r_hctr_p0;
    reg [9:0] r_vctr_p0;
    reg       r_eol_p0;
    reg       r_eof_p0;
    
    always @(posedge rst or posedge clk) begin : HV_COUNT_P0
        reg v_fr_p0;
    
        if (rst) begin
            r_fr_tgl  <= 1'b0;
            r_hctr_p0 <= 10'd0;
            r_vctr_p0 <= 10'd0;
            r_eol_p0  <= 1'b0;
            r_eof_p0  <= 1'b0;
            v_fr_p0   <= 1'b0;
        end
        else begin
            if (clk_ena) begin
                if (r_eol_p0) begin
                    if (r_eof_p0) begin
                        // Vertical counter
                        r_vctr_p0 <= 10'd0;
                    end
                    else begin
                        r_vctr_p0 <= r_vctr_p0 + 10'd1;
                    end
                    // Frame toggle
                    r_fr_tgl <= r_fr_tgl ^ (v_fr_p0 & lcd_on);
                    // Horizontal counter
                    r_hctr_p0 <= 10'd0;
                end
                else begin
                    r_hctr_p0 <= r_hctr_p0 + 10'd1;
                end
            end
            
            // Comparators
            r_eol_p0 <= (r_hctr_p0 == 10'd799) ? 1'b1 : 1'b0; // 800 - 1 (htotal)
            r_eof_p0 <= (r_vctr_p0 == 10'd524) ? 1'b1 : 1'b0; // 525 - 1 (vtotal)
            v_fr_p0  <= (r_vctr_p0 == 10'd271) ? 1'b1 : 1'b0; // (480 + 64) / 2 - 1
        end
    end
    
    assign new_fr_tgl = r_fr_tgl;

    // ========================================================================
    // Horizontal and vertical blanking
    // ========================================================================
    
    reg       r_hblank_p0;
    reg       r_vblank_p0;
    
    always @(posedge rst or posedge clk) begin : HV_BLANK_P0
        reg v_h_strt; // Horizontal blanking start
        reg v_v_strt; // Vertical blanking start
    
        if (rst) begin
            r_hblank_p0 <= 1'b0;
            r_vblank_p0 <= 1'b0;
            v_h_strt    <= 1'b0;
            v_v_strt    <= 1'b0;
        end
        else begin
            if (clk_ena) begin
                // Horizontal blanking
                if (r_eol_p0) begin
                    r_hblank_p0 <= 1'b0;
                end
                else if (v_h_strt) begin
                    r_hblank_p0 <= 1'b1;
                end
                // Vertical blanking
                if (r_eol_p0 & r_eof_p0) begin
                    r_vblank_p0 <= 1'b0;
                end
                else if (r_eol_p0 & v_v_strt) begin
                    r_vblank_p0 <= 1'b1;
                end
            end
            
            // Comparators
            v_h_strt <= (r_hctr_p0 == 10'd639) ? 1'b1 : 1'b0; // 640 - 1 (hactive)
            v_v_strt <= (r_vctr_p0 == 10'd479) ? 1'b1 : 1'b0; // 480 - 1 (vactive)
        end
    end
    
    // ========================================================================
    // Horizontal and vertical synchros
    // ========================================================================
    
    reg       r_hsync_p0;
    reg       r_vsync_p0;
    
    always @(posedge rst or posedge clk) begin : HV_SYNC_P0
        reg v_h_strt; // Horizontal synchro start
        reg v_h_stop; // Horizontal synchro stop
        reg v_v_strt; // Vertical synchro start
        reg v_v_stop; // Vertical synchro stop
    
        if (rst) begin
            r_hsync_p0 <= 1'b0;
            r_vsync_p0 <= 1'b0;
            v_h_strt  <= 1'b0;
            v_h_stop  <= 1'b0;
            v_v_strt  <= 1'b0;
            v_v_stop  <= 1'b0;
        end
        else begin
            if (clk_ena) begin
                // Horizontal synchro
                if (v_h_strt) begin
                    r_hsync_p0 <= 1'b1;
                end
                else if (v_h_stop) begin
                    r_hsync_p0 <= 1'b0;
                end
                // Vertical synchro
                if (v_h_strt & v_v_strt) begin
                    r_vsync_p0 <= 1'b1;
                end
                else if (v_h_strt & v_v_stop) begin
                    r_vsync_p0 <= 1'b0;
                end
            end
            
            // Comparators
            v_h_strt <= (r_hctr_p0 == 10'd655) ? 1'b1 : 1'b0; // 640 + 16 - 1
            v_h_stop <= (r_hctr_p0 == 10'd751) ? 1'b1 : 1'b0; // 640 + 16 + 96 - 1
            v_v_strt <= (r_vctr_p0 == 10'd489) ? 1'b1 : 1'b0; // 480 + 10 - 1
            v_v_stop <= (r_vctr_p0 == 10'd491) ? 1'b1 : 1'b0; // 480 + 10 + 2 - 1
        end
    end
    
    // ========================================================================
    // VRAM buffer : 640 x 64 pixels + 320 x 8 gray flags
    // ========================================================================
    
    wire  [4:0] w_wren;
    wire [14:0] w_vga_addr_p0;
    wire  [9:0] w_vga_pix_p2;
    wire        w_vga_gry_p2;
    
    assign w_vga_addr_p0 = { r_hctr_p0[9:1], r_vctr_p0[5:0] };
    
    // Slice #0 : pixels   0 - 127
    assign w_wren[0] = (vram_addr[14:12] == 3'd0) ? vram_we : 1'b0;
    
    z88_vga_dpram_4096x2_r U_vram_slice_0
    (
        .wrclock   (clk),
        .wren      (w_wren[0]),
        .wraddress (vram_addr[11:0]),
        .data      (vram_data[1:0]),
        .rdclock   (clk),
        .rdaddress (w_vga_addr_p0[11:0]),
        .q         (w_vga_pix_p2[1:0])
    );
    
    // Slice #1 : pixels 128 - 255
    assign w_wren[1] = (vram_addr[14:12] == 3'd1) ? vram_we : 1'b0;
    
    z88_vga_dpram_4096x2_r U_vram_slice_1
    (
        .wrclock   (clk),
        .wren      (w_wren[1]),
        .wraddress (vram_addr[11:0]),
        .data      (vram_data[1:0]),
        .rdclock   (clk),
        .rdaddress (w_vga_addr_p0[11:0]),
        .q         (w_vga_pix_p2[3:2])
    );
    
    // Slice #2 : pixels 256 - 383
    assign w_wren[2] = (vram_addr[14:12] == 3'd2) ? vram_we : 1'b0;
    
    z88_vga_dpram_4096x2_r U_vram_slice_2
    (
        .wrclock   (clk),
        .wren      (w_wren[2]),
        .wraddress (vram_addr[11:0]),
        .data      (vram_data[1:0]),
        .rdclock   (clk),
        .rdaddress (w_vga_addr_p0[11:0]),
        .q         (w_vga_pix_p2[5:4])
    );
    
    // Slice #3 : pixels 384 - 511
    assign w_wren[3] = (vram_addr[14:12] == 3'd3) ? vram_we : 1'b0;
    
    z88_vga_dpram_4096x2_r U_vram_slice_3
    (
        .wrclock   (clk),
        .wren      (w_wren[3]),
        .wraddress (vram_addr[11:0]),
        .data      (vram_data[1:0]),
        .rdclock   (clk),
        .rdaddress (w_vga_addr_p0[11:0]),
        .q         (w_vga_pix_p2[7:6])
    );
    
    // Slice #4 : pixels 512 - 639
    assign w_wren[4] = (vram_addr[14:12] == 3'd4) ? vram_we : 1'b0;
    
    z88_vga_dpram_4096x2_r U_vram_slice_4
    (
        .wrclock   (clk),
        .wren      (w_wren[4]),
        .wraddress (vram_addr[11:0]),
        .data      (vram_data[1:0]),
        .rdclock   (clk),
        .rdaddress (w_vga_addr_p0[11:0]),
        .q         (w_vga_pix_p2[9:8])
    );
    
    // Gray flag storage
    z88_vga_dpram_4096x1_r U_vram_gray
    (
        .wrclock   (clk),
        .wren      (vram_we),
        .wraddress (vram_addr[14:3]),
        .data      (vram_data[2]),
        .rdclock   (clk),
        .rdaddress (w_vga_addr_p0[14:3]),
        .q         (w_vga_gry_p2)
    );
    
    // ========================================================================
    // VGA output
    // ========================================================================
    
    reg         r_vga_on_p1;
    reg   [3:0] r_vga_addr_p1;
    
    reg         r_vga_on_p2;
    reg   [9:0] r_vga_sel_p2;
    
    always @(posedge clk) begin : PIXEL_SEL_P1_P2
    
        // VGA display is ON
        r_vga_on_p1   <= ((r_vctr_p0[9:4] == 6'h0D) ||
                          (r_vctr_p0[9:4] == 6'h0E) ||
                          (r_vctr_p0[9:4] == 6'h0F) ||
                          (r_vctr_p0[9:4] == 6'h10)) ? lcd_on : 1'b0;
        // Keep the 3 upper address bits + hor. counter lsb
        r_vga_addr_p1 <= { w_vga_addr_p0[14:12], r_hctr_p0[0] };
        
        // Decode them as one hot
        case (r_vga_addr_p1)
            4'd0    : r_vga_sel_p2 <= 10'b00_00_00_00_10;
            4'd1    : r_vga_sel_p2 <= 10'b00_00_00_00_01;
            4'd2    : r_vga_sel_p2 <= 10'b00_00_00_10_00;
            4'd3    : r_vga_sel_p2 <= 10'b00_00_00_01_00;
            4'd4    : r_vga_sel_p2 <= 10'b00_00_10_00_00;
            4'd5    : r_vga_sel_p2 <= 10'b00_00_01_00_00;
            4'd6    : r_vga_sel_p2 <= 10'b00_10_00_00_00;
            4'd7    : r_vga_sel_p2 <= 10'b00_01_00_00_00;
            4'd8    : r_vga_sel_p2 <= 10'b10_00_00_00_00;
            4'd9    : r_vga_sel_p2 <= 10'b01_00_00_00_00;
            default : r_vga_sel_p2 <= 10'b00_00_00_00_00;
        endcase
        r_vga_on_p2   <= r_vga_on_p1;
    end
    
    reg  [11:0] r_vga_rgb_p3;
    
    always @(posedge clk) begin : PIXEL_OUT_P3
        reg [1:0] v_pix_p2;
        
        v_pix_p2[1] = w_vga_gry_p2;
        v_pix_p2[0] = |(r_vga_sel_p2 & w_vga_pix_p2);
        
        if (r_vga_on_p2 & r_hvd_p2[0]) begin
            case (v_pix_p2)
                2'b00 : r_vga_rgb_p3 <= 12'hFFF; // White
                2'b01 : r_vga_rgb_p3 <= 12'h000; // Black
                2'b10 : r_vga_rgb_p3 <= 12'hFFF; // White
                2'b11 : r_vga_rgb_p3 <= 12'h777; // Gray
            endcase
        end
        else begin
            r_vga_rgb_p3 <= 12'h000; // Black
        end
    end
    
    reg [2:0] r_hvd_p1;
    reg [2:0] r_hvd_p2;
    reg [2:0] r_hvd_p3;

    always @(posedge clk) begin : CONTROL_P1_P2_P3
    
        r_hvd_p1[2] <= r_hsync_p0;
        r_hvd_p1[1] <= r_vsync_p0;
        r_hvd_p1[0] <= ~(r_hblank_p0 | r_vblank_p0);
        r_hvd_p2    <= r_hvd_p1;
        r_hvd_p3    <= r_hvd_p2;
    end
    
    assign hsync = r_hvd_p3[2];
    assign vsync = r_hvd_p3[1];
    assign dena  = r_hvd_p3[0];
    assign rgb   = r_vga_rgb_p3;
    
endmodule

module z88_vga_dpram_4096x1_r
(
    // Write port
    input          wrclock,
    input          wren,
    input  [11:0]  wraddress,
    input          data,
    // Read port
    input          rdclock,
    input  [11:0]  rdaddress,
    output         q
);

`ifdef verilator3
    reg r_ram_blk [0:4095];
    
    ////////////////
    // Write port //
    ////////////////
    
    always@(posedge wrclock) begin : WR_PORT
    
        if (wren) begin
            r_ram_blk[wraddress] <= data;
        end
    end
    
    ///////////////
    // Read port //
    ///////////////
    
    reg r_q_p1;
    reg r_q_p2;
    
    always@(posedge rdclock) begin : RD_PORT
    
        r_q_p1 <= r_ram_blk[rdaddress];
        r_q_p2 <= r_q_p1;
    end
    
    assign q = r_q_p2;
`else
    altsyncram U_altsyncram
    (
        .address_a      (wraddress),
        .clock0         (wrclock),
        .data_a         (data),
        .wren_a         (wren),
        .address_b      (rdaddress),
        .clock1         (rdclock),
        .q_b            (q),
        .aclr0          (1'b0),
        .aclr1          (1'b0),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a      (1'b1),
        .byteena_b      (1'b1),
        .clocken0       (1'b1),
        .clocken1       (1'b1),
        .clocken2       (1'b1),
        .clocken3       (1'b1),
        .data_b         (1'b1),
        .eccstatus      (),
        .q_a            (),
        .rden_a         (1'b1),
        .rden_b         (1'b1),
        .wren_b         (1'b0)
    );
    defparam
        U_altsyncram.address_reg_b          = "CLOCK1",
        U_altsyncram.clock_enable_input_a   = "BYPASS",
        U_altsyncram.clock_enable_input_b   = "BYPASS",
        U_altsyncram.clock_enable_output_a  = "BYPASS",
        U_altsyncram.clock_enable_output_b  = "BYPASS",
        U_altsyncram.intended_device_family = "Cyclone II",
        U_altsyncram.lpm_type               = "altsyncram",
        U_altsyncram.numwords_a             = 4096,
        U_altsyncram.numwords_b             = 4096,
        U_altsyncram.operation_mode         = "DUAL_PORT",
        U_altsyncram.outdata_aclr_b         = "NONE",
        U_altsyncram.outdata_reg_b          = "CLOCK1",
        U_altsyncram.power_up_uninitialized = "FALSE",
        U_altsyncram.widthad_a              = 12,
        U_altsyncram.widthad_b              = 12,
        U_altsyncram.width_a                = 1,
        U_altsyncram.width_b                = 1,
        U_altsyncram.width_byteena_a        = 1;
`endif

endmodule

module z88_vga_dpram_4096x2_r
(
    // Write port
    input          wrclock,
    input          wren,
    input  [11:0]  wraddress,
    input   [1:0]  data,
    // Read port
    input          rdclock,
    input  [11:0]  rdaddress,
    output  [1:0]  q
);

`ifdef verilator3
    reg [1:0] r_ram_blk [0:4095];
    
    ////////////////
    // Write port //
    ////////////////
    
    always@(posedge wrclock) begin : WR_PORT
    
        if (wren) begin
            r_ram_blk[wraddress] <= data;
        end
    end
    
    ///////////////
    // Read port //
    ///////////////
    
    reg [1:0] r_q_p1;
    reg [1:0] r_q_p2;
    
    always@(posedge rdclock) begin : RD_PORT
    
        r_q_p1 <= r_ram_blk[rdaddress];
        r_q_p2 <= r_q_p1;
    end
    
    assign q = r_q_p2;
`else
    altsyncram U_altsyncram
    (
        .address_a      (wraddress),
        .clock0         (wrclock),
        .data_a         (data),
        .wren_a         (wren),
        .address_b      (rdaddress),
        .clock1         (rdclock),
        .q_b            (q),
        .aclr0          (1'b0),
        .aclr1          (1'b0),
        .addressstall_a (1'b0),
        .addressstall_b (1'b0),
        .byteena_a      (1'b1),
        .byteena_b      (1'b1),
        .clocken0       (1'b1),
        .clocken1       (1'b1),
        .clocken2       (1'b1),
        .clocken3       (1'b1),
        .data_b         (2'b11),
        .eccstatus      (),
        .q_a            (),
        .rden_a         (1'b1),
        .rden_b         (1'b1),
        .wren_b         (1'b0)
    );
    defparam
        U_altsyncram.address_reg_b          = "CLOCK1",
        U_altsyncram.clock_enable_input_a   = "BYPASS",
        U_altsyncram.clock_enable_input_b   = "BYPASS",
        U_altsyncram.clock_enable_output_a  = "BYPASS",
        U_altsyncram.clock_enable_output_b  = "BYPASS",
        U_altsyncram.intended_device_family = "Cyclone II",
        U_altsyncram.lpm_type               = "altsyncram",
        U_altsyncram.numwords_a             = 4096,
        U_altsyncram.numwords_b             = 4096,
        U_altsyncram.operation_mode         = "DUAL_PORT",
        U_altsyncram.outdata_aclr_b         = "NONE",
        U_altsyncram.outdata_reg_b          = "CLOCK1",
        U_altsyncram.power_up_uninitialized = "FALSE",
        U_altsyncram.widthad_a              = 12,
        U_altsyncram.widthad_b              = 12,
        U_altsyncram.width_a                = 2,
        U_altsyncram.width_b                = 2,
        U_altsyncram.width_byteena_a        = 1;
`endif

endmodule
