module z88_de1_top
(
    input   [1:0] CLOCK_27,
    input   [1:0] CLOCK_24,
    input         CLOCK_50,
    input         EXT_CLOCK,
    
    input   [9:0] SW,
    
    output  [6:0] HEX0,
    output  [6:0] HEX1,
    output  [6:0] HEX2,
    output  [6:0] HEX3,
    
    input   [3:0] KEY,
    
    output  [9:0] LEDR,
    output  [7:0] LEDG,
    
    
    inout         PS2_CLK,
    inout         PS2_DAT,
    
    output  [3:0] VGA_R,
    output  [3:0] VGA_G,
    output  [3:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    
    output [21:0] FL_ADDR,
    `ifdef verilator3
    input   [7:0] FL_D,
    output  [7:0] FL_Q,
    `else
    inout   [7:0] FL_DQ,
    `endif
    output        FL_OE_N,
    output        FL_RST_N,
    output        FL_WE_N,
    output        FL_CE_N,
    
    output [17:0] SRAM_ADDR,
    output        SRAM_CE_N,
    `ifdef verilator3
    input  [15:0] SRAM_D,
    output [15:0] SRAM_Q,
    `else
    inout  [15:0] SRAM_DQ,
    `endif
    output        SRAM_LB_N,
    output        SRAM_OE_N,
    output        SRAM_UB_N,
    output        SRAM_WE_N
);

    // ========================================================================
    // Reset de-bouncing
    // ========================================================================
    
    reg  [6:0] r_rst_n;
    reg  [6:0] r_flap_n;
    reg        r_rst;
    reg        r_flap;
    wire       w_clk_ena;
    wire       w_bus_ph;

    always@(posedge CLOCK_50) begin : RESET_FLAP_CC
        r_rst_n  <= { r_rst_n[5:0],  KEY[0] };
        r_flap_n <= { r_flap_n[5:0], KEY[1] };
        r_rst    <= (r_rst_n[6:2]  == 5'b00000) ? 1'b1 : 1'b0;
        r_flap   <= (r_flap_n[6:2] == 5'b00000) ? 1'b1 : 1'b0;
    end

    // ========================================================================
    // Z88 instance
    // ========================================================================
    
    wire  [7:0] w_kbd_val;
    
    wire        w_ram_ce_n;
    wire        w_ram_oe_n;
    wire        w_ram_we_n;
    wire  [1:0] w_ram_be_n;
    wire [18:0] w_ram_addr;
    wire [15:0] w_ram_wdata;
    wire [15:0] w_ram_rdata;
    
    wire        w_rom_ce_n;
    wire        w_rom_oe_n;
    wire  [1:0] w_rom_be_n;
    wire [18:0] w_rom_addr;
    wire [15:0] w_rom_rdata;
    
    wire        w_vga_fr_tgl;
    wire        w_vga_hs;
    wire        w_vga_vs;
    wire        w_vga_de;
    wire [11:0] w_vga_rgb;
    
    z88_top
    #(
        .RAM_DATA_WIDTH (16),
        .ROM_DATA_WIDTH (8),
        `ifdef verilator3
        .RAM_ADDR_MASK  (32'h00007FFF) // 32 KB
        `else
        .RAM_ADDR_MASK  (32'h0007FFFF) // 512 KB
        `endif
    )
    the_z88
    (
        .rst        (r_rst),
        .clk        (CLOCK_50),
        .clk_ena    (w_clk_ena),
        .bus_ph     (w_bus_ph),
        .flap_sw    (r_flap),
        
        .kb_matrix  (r_kb_matrix_p2),
        .kbd_val    (w_kbd_val),
        
        .ram_ce_n   (w_ram_ce_n),
        .ram_oe_n   (w_ram_oe_n),
        .ram_we_n   (w_ram_we_n),
        .ram_be_n   (w_ram_be_n),
        .ram_addr   (w_ram_addr),
        .ram_wdata  (w_ram_wdata),
        .ram_rdata  (w_ram_rdata),
        
        .rom_ce_n   (w_rom_ce_n),
        .rom_oe_n   (w_rom_oe_n),
        .rom_be_n   (w_rom_be_n),
        .rom_addr   (w_rom_addr),
        .rom_rdata  (w_rom_rdata),
        
        .vga_fr_tgl (w_vga_fr_tgl),
        .vga_hs     (w_vga_hs),
        .vga_vs     (w_vga_vs),
        .vga_de     (w_vga_de),
        .vga_rgb    (w_vga_rgb)
    );
    
    // 512 KB SRAM :
    // -------------
    assign SRAM_CE_N         = w_ram_ce_n;
    assign SRAM_OE_N         = w_ram_oe_n;
    assign SRAM_WE_N         = w_ram_we_n;
    assign SRAM_UB_N         = w_ram_be_n[1];
    assign SRAM_LB_N         = w_ram_be_n[0];
    assign SRAM_ADDR[17:0]   = w_ram_addr[17:0];
`ifdef verilator3
    assign SRAM_Q[15:0]      = w_ram_wdata[15:0];
    assign w_ram_rdata[15:0] = SRAM_D[15:0];
`else
    assign SRAM_DQ[15:0]     = (!w_ram_we_n) ? w_ram_wdata[15:0] : 16'hZZ_ZZ;
    assign w_ram_rdata[15:0] = SRAM_DQ[15:0];
`endif

    // 512 KB Flash :
    // --------------
    assign FL_RST_N          = 1'b1;
    assign FL_CE_N           = w_rom_ce_n;
    assign FL_OE_N           = w_rom_oe_n;
    assign FL_WE_N           = 1'b1;
    assign FL_ADDR[21:0]     = { 3'b0, w_rom_addr[18:0] };
`ifdef verilator3
    assign FL_Q[7:0]         = 8'h00;
    assign w_rom_rdata[15:0] = { 8'h00, FL_D[7:0] };
`else
    assign FL_DQ[7:0]        = 8'hZZ;
    assign w_rom_rdata[15:0] = { 8'h00, FL_DQ[7:0] };
`endif

    // VGA output :
    // ------------
    assign VGA_HS = w_vga_hs;
    assign VGA_VS = w_vga_vs;
    assign VGA_R  = w_vga_rgb[3:0];
    assign VGA_G  = w_vga_rgb[7:4];
    assign VGA_B  = w_vga_rgb[11:8];

    // ========================================================================
    // PS2 controller
    // ========================================================================

    wire        w_kb_vld_p0;
    wire  [7:0] w_kb_data_p0;
    
    ps2_keyboard the_keyboard
    (
        .rst       (r_rst),
        .clk       (CLOCK_50),
        .cdac_r    (w_clk_ena & ~w_bus_ph),
        .cdac_f    (w_clk_ena &  w_bus_ph),
        .caps_led  (1'b0),
        .num_led   (1'b0), 
        .disk_led  (1'b0),
        .ps2_kclk  (PS2_CLK),
        .ps2_kdat  (PS2_DAT),
        .kb_vld    (w_kb_vld_p0),
        .kb_data   (w_kb_data_p0)
    );
    
    reg       r_kb_ext_p1;
    reg       r_kb_brk_p1;
    reg [8:0] r_kb_data_p1;
    reg       r_kb_vld_p1;
    
    always@(posedge r_rst or posedge CLOCK_50) begin : KB_PRE_DECODE_P1
    
        if (r_rst) begin
            r_kb_ext_p1  <= 1'b0;
            r_kb_brk_p1  <= 1'b0;
            r_kb_data_p1 <= { 1'b0, 8'h00 };
            r_kb_vld_p1  <= 1'b0;
        end
        else begin
            if (w_clk_ena & w_bus_ph & w_kb_vld_p0) begin
                case (w_kb_data_p0[7:4])
                    4'hE : // Extended key
                    begin
                        r_kb_ext_p1 <= 1'b1;
                        r_kb_vld_p1 <= 1'b0;
                    end
                    4'hF : // Key upstroke
                    begin
                        r_kb_brk_p1 <= 1'b1;
                        r_kb_vld_p1 <= 1'b0;
                    end
                    default : // Normal keycode
                    begin
                        // Store key code
                        r_kb_data_p1 <= { r_kb_brk_p1, r_kb_ext_p1 | w_kb_data_p0[7], w_kb_data_p0[6:0] };
                        r_kb_vld_p1  <= 1'b1;
                        // Clear special flags
                        r_kb_brk_p1  <= 1'b0;
                        r_kb_ext_p1  <= 1'b0;
                    end
                endcase
            end
            else begin
                r_kb_vld_p1 <= 1'b0;
            end
        end
    end
    
    reg  [63:0] r_kb_matrix_p2;
    
    always@(posedge r_rst or posedge CLOCK_50) begin : KB_MATRIX_P2
        `ifdef verilator3
        integer v_fr_num;
        reg     v_fr_tgl;
        `endif
    
        if (r_rst) begin
            `ifdef verilator3
            v_fr_num  = 0;
            v_fr_tgl <= 1'b0;
            `endif
            r_kb_matrix_p2 <= 64'b0;
        end
        else begin
            `ifdef verilator3
            if (v_fr_tgl != w_vga_fr_tgl) begin
                if (v_fr_num == 32'd150) r_kb_matrix_p2[22] <= 1'b1; // Down
                if (v_fr_num == 32'd151) r_kb_matrix_p2[22] <= 1'b0;
                if (v_fr_num == 32'd155) r_kb_matrix_p2[22] <= 1'b1; // Down
                if (v_fr_num == 32'd156) r_kb_matrix_p2[22] <= 1'b0;
                if (v_fr_num == 32'd160) r_kb_matrix_p2[ 6] <= 1'b1; // Enter
                if (v_fr_num == 32'd161) r_kb_matrix_p2[ 6] <= 1'b0;
                if (v_fr_num == 32'd192) r_kb_matrix_p2[45] <= 1'b1; // 1
                if (v_fr_num == 32'd193) r_kb_matrix_p2[45] <= 1'b0;
                if (v_fr_num == 32'd196) r_kb_matrix_p2[40] <= 1'b1; // 0
                if (v_fr_num == 32'd197) r_kb_matrix_p2[40] <= 1'b0;
                if (v_fr_num == 32'd200) r_kb_matrix_p2[46] <= 1'b1; // Space
                if (v_fr_num == 32'd201) r_kb_matrix_p2[46] <= 1'b0;
                if (v_fr_num == 32'd204) r_kb_matrix_p2[32] <= 1'b1; // P
                if (v_fr_num == 32'd205) r_kb_matrix_p2[32] <= 1'b0;
                if (v_fr_num == 32'd208) r_kb_matrix_p2[20] <= 1'b1; // R
                if (v_fr_num == 32'd209) r_kb_matrix_p2[20] <= 1'b0;
                if (v_fr_num == 32'd212) r_kb_matrix_p2[ 8] <= 1'b1; // I
                if (v_fr_num == 32'd213) r_kb_matrix_p2[ 8] <= 1'b0;
                if (v_fr_num == 32'd216) r_kb_matrix_p2[ 2] <= 1'b1; // N
                if (v_fr_num == 32'd217) r_kb_matrix_p2[ 2] <= 1'b0;
                if (v_fr_num == 32'd220) r_kb_matrix_p2[12] <= 1'b1; // T
                if (v_fr_num == 32'd221) r_kb_matrix_p2[12] <= 1'b0;
                if (v_fr_num == 32'd224) r_kb_matrix_p2[46] <= 1'b1; // Space
                if (v_fr_num == 32'd225) r_kb_matrix_p2[46] <= 1'b0;
                if (v_fr_num == 32'd228) r_kb_matrix_p2[54] <= 1'b1; // Shift
                if (v_fr_num == 32'd228) r_kb_matrix_p2[48] <= 1'b1; // "
                if (v_fr_num == 32'd229) r_kb_matrix_p2[54] <= 1'b0;
                if (v_fr_num == 32'd229) r_kb_matrix_p2[48] <= 1'b0;
                if (v_fr_num == 32'd232) r_kb_matrix_p2[12] <= 1'b1; // T
                if (v_fr_num == 32'd233) r_kb_matrix_p2[12] <= 1'b0;
                if (v_fr_num == 32'd236) r_kb_matrix_p2[28] <= 1'b1; // E
                if (v_fr_num == 32'd237) r_kb_matrix_p2[28] <= 1'b0;
                if (v_fr_num == 32'd240) r_kb_matrix_p2[35] <= 1'b1; // S
                if (v_fr_num == 32'd241) r_kb_matrix_p2[35] <= 1'b0;
                if (v_fr_num == 32'd244) r_kb_matrix_p2[12] <= 1'b1; // T
                if (v_fr_num == 32'd245) r_kb_matrix_p2[12] <= 1'b0;
                if (v_fr_num == 32'd248) r_kb_matrix_p2[54] <= 1'b1; // Shift
                if (v_fr_num == 32'd248) r_kb_matrix_p2[48] <= 1'b1; // "
                if (v_fr_num == 32'd249) r_kb_matrix_p2[54] <= 1'b0;
                if (v_fr_num == 32'd249) r_kb_matrix_p2[48] <= 1'b0;
                if (v_fr_num == 32'd252) r_kb_matrix_p2[ 6] <= 1'b1; // Enter
                if (v_fr_num == 32'd253) r_kb_matrix_p2[ 6] <= 1'b0;
                if (v_fr_num == 32'd256) r_kb_matrix_p2[37] <= 1'b1; // 2
                if (v_fr_num == 32'd257) r_kb_matrix_p2[37] <= 1'b0;
                if (v_fr_num == 32'd260) r_kb_matrix_p2[40] <= 1'b1; // 0
                if (v_fr_num == 32'd261) r_kb_matrix_p2[40] <= 1'b0;
                if (v_fr_num == 32'd264) r_kb_matrix_p2[46] <= 1'b1; // Space
                if (v_fr_num == 32'd265) r_kb_matrix_p2[46] <= 1'b0;
                if (v_fr_num == 32'd268) r_kb_matrix_p2[11] <= 1'b1; // G
                if (v_fr_num == 32'd269) r_kb_matrix_p2[11] <= 1'b0;
                if (v_fr_num == 32'd272) r_kb_matrix_p2[16] <= 1'b1; // O
                if (v_fr_num == 32'd273) r_kb_matrix_p2[16] <= 1'b0;
                if (v_fr_num == 32'd276) r_kb_matrix_p2[12] <= 1'b1; // T
                if (v_fr_num == 32'd277) r_kb_matrix_p2[12] <= 1'b0;
                if (v_fr_num == 32'd280) r_kb_matrix_p2[16] <= 1'b1; // O
                if (v_fr_num == 32'd281) r_kb_matrix_p2[16] <= 1'b0;
                if (v_fr_num == 32'd284) r_kb_matrix_p2[46] <= 1'b1; // Space
                if (v_fr_num == 32'd285) r_kb_matrix_p2[46] <= 1'b0;
                if (v_fr_num == 32'd288) r_kb_matrix_p2[45] <= 1'b1; // 1
                if (v_fr_num == 32'd289) r_kb_matrix_p2[45] <= 1'b0;
                if (v_fr_num == 32'd292) r_kb_matrix_p2[40] <= 1'b1; // 0
                if (v_fr_num == 32'd293) r_kb_matrix_p2[40] <= 1'b0;
                if (v_fr_num == 32'd296) r_kb_matrix_p2[ 6] <= 1'b1; // Enter
                if (v_fr_num == 32'd297) r_kb_matrix_p2[ 6] <= 1'b0;
                if (v_fr_num == 32'd300) r_kb_matrix_p2[20] <= 1'b1; // R
                if (v_fr_num == 32'd301) r_kb_matrix_p2[20] <= 1'b0;
                if (v_fr_num == 32'd304) r_kb_matrix_p2[ 9] <= 1'b1; // U
                if (v_fr_num == 32'd305) r_kb_matrix_p2[ 9] <= 1'b0;
                if (v_fr_num == 32'd308) r_kb_matrix_p2[ 2] <= 1'b1; // N
                if (v_fr_num == 32'd309) r_kb_matrix_p2[ 2] <= 1'b0;
                if (v_fr_num == 32'd312) r_kb_matrix_p2[ 6] <= 1'b1; // Enter
                if (v_fr_num == 32'd313) r_kb_matrix_p2[ 6] <= 1'b0;
                v_fr_num = v_fr_num + 1;
            end
            v_fr_tgl <= w_vga_fr_tgl;
            `else
            if (r_kb_vld_p1) begin
                case (r_kb_data_p1[7:0])
                    //  A8 column
                    8'h3E: r_kb_matrix_p2[ 0] <= ~r_kb_data_p1[8];  // 8
                    8'h3D: r_kb_matrix_p2[ 1] <= ~r_kb_data_p1[8];  // 7
                    8'h31: r_kb_matrix_p2[ 2] <= ~r_kb_data_p1[8];  // N
                    8'h33: r_kb_matrix_p2[ 3] <= ~r_kb_data_p1[8];  // H
                    8'h35: r_kb_matrix_p2[ 4] <= ~r_kb_data_p1[8];  // Y
                    8'h36: r_kb_matrix_p2[ 5] <= ~r_kb_data_p1[8];  // 6
                    8'h5A: r_kb_matrix_p2[ 6] <= ~r_kb_data_p1[8];  // Enter
                    8'h66: r_kb_matrix_p2[ 7] <= ~r_kb_data_p1[8];  // Del
                    //  A9 column
                    8'h43: r_kb_matrix_p2[ 8] <= ~r_kb_data_p1[8];  // I
                    8'h3C: r_kb_matrix_p2[ 9] <= ~r_kb_data_p1[8];  // U
                    8'h32: r_kb_matrix_p2[10] <= ~r_kb_data_p1[8];  // B
                    8'h34: r_kb_matrix_p2[11] <= ~r_kb_data_p1[8];  // G
                    8'h2C: r_kb_matrix_p2[12] <= ~r_kb_data_p1[8];  // T
                    8'h2E: r_kb_matrix_p2[13] <= ~r_kb_data_p1[8];  // 5
                    8'hF5: r_kb_matrix_p2[14] <= ~r_kb_data_p1[8];  // Up
                    8'h5D: r_kb_matrix_p2[15] <= ~r_kb_data_p1[8];  // \
                    //  A10 column
                    8'h44: r_kb_matrix_p2[16] <= ~r_kb_data_p1[8];  // O
                    8'h3B: r_kb_matrix_p2[17] <= ~r_kb_data_p1[8];  // J
                    8'h2A: r_kb_matrix_p2[18] <= ~r_kb_data_p1[8];  // V
                    8'h2B: r_kb_matrix_p2[19] <= ~r_kb_data_p1[8];  // F
                    8'h2D: r_kb_matrix_p2[20] <= ~r_kb_data_p1[8];  // R
                    8'h25: r_kb_matrix_p2[21] <= ~r_kb_data_p1[8];  // 4
                    8'hF2: r_kb_matrix_p2[22] <= ~r_kb_data_p1[8];  // Down
                    8'h55: r_kb_matrix_p2[23] <= ~r_kb_data_p1[8];  // =
                    //  A11 column
                    8'h46: r_kb_matrix_p2[24] <= ~r_kb_data_p1[8];  // 9
                    8'h42: r_kb_matrix_p2[25] <= ~r_kb_data_p1[8];  // K
                    8'h21: r_kb_matrix_p2[26] <= ~r_kb_data_p1[8];  // C
                    8'h23: r_kb_matrix_p2[27] <= ~r_kb_data_p1[8];  // D
                    8'h24: r_kb_matrix_p2[28] <= ~r_kb_data_p1[8];  // E
                    8'h26: r_kb_matrix_p2[29] <= ~r_kb_data_p1[8];  // 3
                    8'hF4: r_kb_matrix_p2[30] <= ~r_kb_data_p1[8];  // Right
                    8'h4E: r_kb_matrix_p2[31] <= ~r_kb_data_p1[8];  // -
                    //  A12 column
                    8'h4D: r_kb_matrix_p2[32] <= ~r_kb_data_p1[8];  // P
                    8'h3A: r_kb_matrix_p2[33] <= ~r_kb_data_p1[8];  // M
                    8'h22: r_kb_matrix_p2[34] <= ~r_kb_data_p1[8];  // X
                    8'h1B: r_kb_matrix_p2[35] <= ~r_kb_data_p1[8];  // S
                    8'h1D: r_kb_matrix_p2[36] <= ~r_kb_data_p1[8];  // W
                    8'h1E: r_kb_matrix_p2[37] <= ~r_kb_data_p1[8];  // 2
                    8'hEB: r_kb_matrix_p2[38] <= ~r_kb_data_p1[8];  // Left
                    8'h5B: r_kb_matrix_p2[39] <= ~r_kb_data_p1[8];  // ]
                    //  A13 column
                    8'h45: r_kb_matrix_p2[40] <= ~r_kb_data_p1[8];  // 0
                    8'h4B: r_kb_matrix_p2[41] <= ~r_kb_data_p1[8];  // L
                    8'h1A: r_kb_matrix_p2[42] <= ~r_kb_data_p1[8];  // Z
                    8'h1C: r_kb_matrix_p2[43] <= ~r_kb_data_p1[8];  // A
                    8'h15: r_kb_matrix_p2[44] <= ~r_kb_data_p1[8];  // Q
                    8'h16: r_kb_matrix_p2[45] <= ~r_kb_data_p1[8];  // 1
                    8'h29: r_kb_matrix_p2[46] <= ~r_kb_data_p1[8];  // Space
                    8'h54: r_kb_matrix_p2[47] <= ~r_kb_data_p1[8];  // [
                    //  A14 column
                    8'h52: r_kb_matrix_p2[48] <= ~r_kb_data_p1[8];  // "
                    8'h4C: r_kb_matrix_p2[49] <= ~r_kb_data_p1[8];  // ;
                    8'h41: r_kb_matrix_p2[50] <= ~r_kb_data_p1[8];  // ,
                    8'h04: r_kb_matrix_p2[51] <= ~r_kb_data_p1[8];  // Menu (F3)
                    8'h14: r_kb_matrix_p2[52] <= ~r_kb_data_p1[8];  // <> (Ctrl)
                    8'h94: r_kb_matrix_p2[52] <= ~r_kb_data_p1[8];  // <> (Ctrl)
                    8'h0D: r_kb_matrix_p2[53] <= ~r_kb_data_p1[8];  // Tab
                    8'h12: r_kb_matrix_p2[54] <= ~r_kb_data_p1[8];  // LShift
                    8'h05: r_kb_matrix_p2[55] <= ~r_kb_data_p1[8];  // Help (F1)
                    //  A15 column
                    8'h0E: r_kb_matrix_p2[56] <= ~r_kb_data_p1[8];  // £
                    8'h4A: r_kb_matrix_p2[57] <= ~r_kb_data_p1[8];  // /
                    8'h49: r_kb_matrix_p2[58] <= ~r_kb_data_p1[8];  // .
                    8'h58: r_kb_matrix_p2[59] <= ~r_kb_data_p1[8];  // Caps
                    8'h06: r_kb_matrix_p2[60] <= ~r_kb_data_p1[8];  // Index (F2)
                    8'h76: r_kb_matrix_p2[61] <= ~r_kb_data_p1[8];  // Esc
                    8'h11: r_kb_matrix_p2[62] <= ~r_kb_data_p1[8];  // [] (Alt)
                    8'h91: r_kb_matrix_p2[62] <= ~r_kb_data_p1[8];  // [] (Alt)
                    8'h59: r_kb_matrix_p2[63] <= ~r_kb_data_p1[8];  // RShift
                    default: ;                    
                endcase
            end
            `endif
        end
    end
    
    // ========================================================================
    // Debug
    // ========================================================================
    
    reg [6:0] r_hex0_disp;
    reg [6:0] r_hex1_disp;
    reg [6:0] r_hex2_disp;
    reg [6:0] r_hex3_disp;
    
    always@(posedge CLOCK_50) begin : HEX0_DISP
    
        case (w_kbd_val[3:0])
            4'h0 : r_hex0_disp <= 7'b1000000;
            4'h1 : r_hex0_disp <= 7'b1111001;
            4'h2 : r_hex0_disp <= 7'b0100100;
            4'h3 : r_hex0_disp <= 7'b0110000;
            4'h4 : r_hex0_disp <= 7'b0011001;
            4'h5 : r_hex0_disp <= 7'b0010010;
            4'h6 : r_hex0_disp <= 7'b0000010;
            4'h7 : r_hex0_disp <= 7'b1111000;
            4'h8 : r_hex0_disp <= 7'b0000000;
            4'h9 : r_hex0_disp <= 7'b0010000;
            4'hA : r_hex0_disp <= 7'b0001000;
            4'hB : r_hex0_disp <= 7'b0000011;
            4'hC : r_hex0_disp <= 7'b1000110;
            4'hD : r_hex0_disp <= 7'b0100001;
            4'hE : r_hex0_disp <= 7'b0000110;
            4'hF : r_hex0_disp <= 7'b0001110;
        endcase
    end
    
    always@(posedge CLOCK_50) begin : HEX1_DISP
    
        case (w_kbd_val[7:4])
            4'h0 : r_hex1_disp <= 7'b1000000;
            4'h1 : r_hex1_disp <= 7'b1111001;
            4'h2 : r_hex1_disp <= 7'b0100100;
            4'h3 : r_hex1_disp <= 7'b0110000;
            4'h4 : r_hex1_disp <= 7'b0011001;
            4'h5 : r_hex1_disp <= 7'b0010010;
            4'h6 : r_hex1_disp <= 7'b0000010;
            4'h7 : r_hex1_disp <= 7'b1111000;
            4'h8 : r_hex1_disp <= 7'b0000000;
            4'h9 : r_hex1_disp <= 7'b0010000;
            4'hA : r_hex1_disp <= 7'b0001000;
            4'hB : r_hex1_disp <= 7'b0000011;
            4'hC : r_hex1_disp <= 7'b1000110;
            4'hD : r_hex1_disp <= 7'b0100001;
            4'hE : r_hex1_disp <= 7'b0000110;
            4'hF : r_hex1_disp <= 7'b0001110;
        endcase
    end

    always@(posedge CLOCK_50) begin : HEX2_DISP
    
        case (r_kb_data_p1[3:0])
            4'h0 : r_hex2_disp <= 7'b1000000;
            4'h1 : r_hex2_disp <= 7'b1111001;
            4'h2 : r_hex2_disp <= 7'b0100100;
            4'h3 : r_hex2_disp <= 7'b0110000;
            4'h4 : r_hex2_disp <= 7'b0011001;
            4'h5 : r_hex2_disp <= 7'b0010010;
            4'h6 : r_hex2_disp <= 7'b0000010;
            4'h7 : r_hex2_disp <= 7'b1111000;
            4'h8 : r_hex2_disp <= 7'b0000000;
            4'h9 : r_hex2_disp <= 7'b0010000;
            4'hA : r_hex2_disp <= 7'b0001000;
            4'hB : r_hex2_disp <= 7'b0000011;
            4'hC : r_hex2_disp <= 7'b1000110;
            4'hD : r_hex2_disp <= 7'b0100001;
            4'hE : r_hex2_disp <= 7'b0000110;
            4'hF : r_hex2_disp <= 7'b0001110;
        endcase
    end
    
    always@(posedge CLOCK_50) begin : HEX3_DISP
    
        case (r_kb_data_p1[7:4])
            4'h0 : r_hex3_disp <= 7'b1000000;
            4'h1 : r_hex3_disp <= 7'b1111001;
            4'h2 : r_hex3_disp <= 7'b0100100;
            4'h3 : r_hex3_disp <= 7'b0110000;
            4'h4 : r_hex3_disp <= 7'b0011001;
            4'h5 : r_hex3_disp <= 7'b0010010;
            4'h6 : r_hex3_disp <= 7'b0000010;
            4'h7 : r_hex3_disp <= 7'b1111000;
            4'h8 : r_hex3_disp <= 7'b0000000;
            4'h9 : r_hex3_disp <= 7'b0010000;
            4'hA : r_hex3_disp <= 7'b0001000;
            4'hB : r_hex3_disp <= 7'b0000011;
            4'hC : r_hex3_disp <= 7'b1000110;
            4'hD : r_hex3_disp <= 7'b0100001;
            4'hE : r_hex3_disp <= 7'b0000110;
            4'hF : r_hex3_disp <= 7'b0001110;
        endcase
    end
    
    assign HEX0 = r_hex0_disp;
    assign HEX1 = r_hex1_disp;
    assign HEX2 = r_hex2_disp;
    assign HEX3 = r_hex3_disp;
    
    reg [9:0] r_sw_cc [0:6];
    reg [9:0] r_sw_val;
    
    always@(posedge r_rst or posedge CLOCK_50) begin : SWITCH_CC
        integer i;
        reg [4:0] v_tmp;
        
        if (r_rst) begin
            r_sw_cc[0] <= 10'b0000000000;
            r_sw_cc[1] <= 10'b0000000000;
            r_sw_cc[2] <= 10'b0000000000;
            r_sw_cc[3] <= 10'b0000000000;
            r_sw_cc[4] <= 10'b0000000000;
            r_sw_cc[5] <= 10'b0000000000;
            r_sw_cc[6] <= 10'b0000000000;
            r_sw_val   <= 10'b0000000000;
        end
        else begin
            for (i = 0; i < 10; i = i + 1) begin
                 v_tmp = { r_sw_cc[6][i],
                           r_sw_cc[5][i],
                           r_sw_cc[4][i],
                           r_sw_cc[3][i], 
                           r_sw_cc[2][i] };
                 if (v_tmp == 5'b00000)
                     r_sw_val[i] <= 1'b0;
                 else if (v_tmp == 5'b11111)
                     r_sw_val[i] <= 1'b1;
            end
            r_sw_cc[6] <= r_sw_cc[5];
            r_sw_cc[5] <= r_sw_cc[4];
            r_sw_cc[4] <= r_sw_cc[3];
            r_sw_cc[3] <= r_sw_cc[2];
            r_sw_cc[2] <= r_sw_cc[1];
            r_sw_cc[1] <= r_sw_cc[0];
            r_sw_cc[0] <= SW[9:0];
        end
    end
    
    assign LEDR = { r_rst, r_flap, r_sw_val[7:0] };
    assign LEDG = r_kb_matrix_p2[ 7: 0] & {8{r_sw_val[0]}}
                | r_kb_matrix_p2[15: 8] & {8{r_sw_val[1]}}
                | r_kb_matrix_p2[23:16] & {8{r_sw_val[2]}}
                | r_kb_matrix_p2[31:24] & {8{r_sw_val[3]}}
                | r_kb_matrix_p2[39:32] & {8{r_sw_val[4]}}
                | r_kb_matrix_p2[47:40] & {8{r_sw_val[5]}}
                | r_kb_matrix_p2[55:48] & {8{r_sw_val[6]}}
                | r_kb_matrix_p2[63:56] & {8{r_sw_val[7]}};

endmodule
