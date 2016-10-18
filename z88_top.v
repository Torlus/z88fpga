module z88_top
(
    // Clocks, Reset switch, Flap switch
    input          rst,
    input          clk,
    output         clk_ena,
    output         bus_ph,
    input          flap_sw,  // normally closed =0, open =1

    // Keyboard matrix
    input   [63:0] kb_matrix, // 8 x 8 keys
    output   [7:0] kbd_val,

    // Internal RAM (512 KB)
    output         ram_ce_n,
    output         ram_oe_n,
    output         ram_we_n,
    output   [1:0] ram_be_n,
    output  [18:0] ram_addr,
    output  [15:0] ram_wdata,
    input   [15:0] ram_rdata,

    // Internal ROM (512 KB)
    output         rom_ce_n,
    output         rom_oe_n,
    output   [1:0] rom_be_n,
    output  [18:0] rom_addr,
    input   [15:0] rom_rdata,

    // VGA output
    output         vga_fr_tgl, // For debug
    output         vga_hs,
    output         vga_vs,
    output         vga_de,
    output  [11:0] vga_rgb
);
    parameter RAM_ADDR_MASK  = 32'h0007FFFF; // 512 KB
    //parameter RAM_ADDR_MASK  = 32'h00007FFF; //  32 KB
    parameter RAM_DATA_WIDTH = 16;
    parameter ROM_DATA_WIDTH = 8;

    // ========================================================================
    // Clock and Control
    // ========================================================================

    reg       r_vga_ena;
    reg [3:0] r_clk_ena;
    reg       r_bus_ph;

    always@(posedge rst or posedge clk) begin : CLK_CTRL

        if (rst) begin
            r_vga_ena <= 1'b0;
            r_clk_ena <= 4'b0001;
            r_bus_ph  <= 1'b0;
        end
        else begin
            r_vga_ena <= ~r_vga_ena;
            r_clk_ena <= { r_clk_ena[2:0], r_clk_ena[3] };
            if (r_clk_ena[3]) begin
                r_bus_ph <= ~r_bus_ph;
            end
        end
    end

    assign clk_ena = r_clk_ena[3];
    assign bus_ph  = r_bus_ph;

    // ========================================================================
    // Z80 CPU
    // ========================================================================

    wire        w_z80_m1_n   /* verilator public */;
    wire        w_z80_mreq_n /* verilator public */;
    wire        w_z80_iorq_n;
    wire        w_z80_rd_n;
    wire        w_z80_wr_n;
    wire        w_z80_halt_n /* verilator public */;

    wire        w_z80_int_n;
    wire        w_z80_nmi_n;

    wire [15:0] w_z80_addr;
    wire  [7:0] w_z80_wdata;

    wire        w_z80_clk_ena /* verilator public */;
    wire        w_z80_mem_rd;
    wire        w_z80_mem_wr;
    wire        w_z80_io_rd;
    wire        w_z80_io_wr;

    assign w_z80_clk_ena = r_clk_ena[3] & ~r_bus_ph;
    assign w_z80_mem_rd  = ~w_z80_mreq_n & ~w_z80_rd_n;
    assign w_z80_mem_wr  = ~w_z80_mreq_n & ~w_z80_wr_n;
    assign w_z80_io_rd   = ~w_z80_iorq_n & ~w_z80_rd_n;
    assign w_z80_io_wr   = ~w_z80_iorq_n & ~w_z80_wr_n;

    tv80s the_z80
    (
        .reset_n    (~rst),
        .clk        (clk),
        .cen        (w_z80_clk_ena),

        .m1_n       (w_z80_m1_n),
        .mreq_n     (w_z80_mreq_n),
        .iorq_n     (w_z80_iorq_n),
        .rd_n       (w_z80_rd_n),
        .wr_n       (w_z80_wr_n),
        .rfsh_n     (/* open */),
        .halt_n     (w_z80_halt_n),
        .busak_n    (/* open */),
        .wait_n     (1'b1),
        .busrq_n    (1'b1),

        .A          (w_z80_addr),
        .dout       (w_z80_wdata),
        .di         (r_z80_rdata),

        .int_n      (w_z80_int_n),
        .nmi_n      (w_z80_nmi_n)
    );

    // ========================================================================
    // I/O registers debug
    // ========================================================================

/*
`ifdef verilator3
    integer _fh_io_log;

    initial begin
        _fh_io_log = $fopen("mem_io.log", "w");
    end

    always@(posedge rst or posedge clk) begin : MEM_IO_DBG
        reg _z80_mem_rd_d;
        reg _z80_mem_wr_d;
        reg _z80_io_rd_d;
        reg _z80_io_wr_d;

        if (rst) begin
            _z80_mem_rd_d <= 1'b0;
            _z80_mem_wr_d <= 1'b0;
            _z80_io_rd_d  <= 1'b0;
            _z80_io_wr_d  <= 1'b0;
        end
        else begin
            // Memory read
            if (~w_z80_mem_rd & _z80_mem_rd_d & w_z80_halt_n) begin
                $fwrite(_fh_io_log, "Mem RD %x @ %x\n", r_z80_rdata, w_z80_addr);
                $fflush(_fh_io_log);
            end
            // Memory write
            if (w_z80_mem_wr & ~_z80_mem_wr_d) begin
                $fwrite(_fh_io_log, "Mem WR %x @ %x\n", w_z80_wdata, w_z80_addr);
                $fflush(_fh_io_log);
            end
            // I/O read
            if (~w_z80_io_rd & _z80_io_rd_d) begin
                $fwrite(_fh_io_log, "I/O RD %x @ %x\n", r_z80_rdata, w_z80_addr);
                $fflush(_fh_io_log);
            end
            // I/O write
            if (w_z80_io_wr & ~_z80_io_wr_d) begin
                $fwrite(_fh_io_log, "I/O WR %x @ %x\n", w_z80_wdata, w_z80_addr);
                $fflush(_fh_io_log);
            end
            // Delayed controls
            _z80_mem_rd_d <= w_z80_mem_rd;
            _z80_mem_wr_d <= w_z80_mem_wr;
            _z80_io_rd_d  <= w_z80_io_rd;
            _z80_io_wr_d  <= w_z80_io_wr;
        end
    end
`endif
*/

    // ========================================================================
    // Blink gate array
    // ========================================================================

    wire  [7:0] w_blk_rdata;
    wire        w_blk_lcd_on;
    wire        w_blk_stby;

    wire [21:0] w_cpu_phy_addr;

    z88_blink the_blink
    (
        .rst        (rst),
        .clk        (clk),
        .clk_ena    (r_clk_ena[3]),
        .bus_ph     (r_bus_ph),

        .z80_io_rd  (w_z80_io_rd),
        .z80_io_wr  (w_z80_io_wr),
        .z80_addr   (w_z80_addr),
        .z80_wdata  (w_z80_wdata),
        .z80_rdata  (w_blk_rdata),
        .z80_hlt_n  (w_z80_halt_n),
        .z80_int_n  (w_z80_int_n),
        .z80_nmi_n  (w_z80_nmi_n),

        .cpu_addr   (w_cpu_phy_addr),
        .lcd_on     (w_blk_lcd_on),
        .stby       (w_blk_stby),

        .kb_matrix  (kb_matrix),
        .kbd_val    (kbd_val),
        .flap_sw    (flap_sw)
    );

    // ========================================================================
    // 640 x 64 LCD screen
    // ========================================================================

    wire        w_lcd_rden;
    wire [21:0] w_lcd_phy_addr;

    wire        w_lcd_vram_we /* verilator public */;
    wire  [2:0] w_lcd_vram_data /* verilator public */;
    wire [14:0] w_lcd_vram_addr /* verilator public */;

    z88_screen the_screen
    (
        .rst        (rst),
        .clk        (clk),
        .clk_ena    (r_clk_ena[3]),
        .bus_ph     (r_bus_ph),

        .z80_io_wr  (w_z80_io_wr),
        .z80_addr   (w_z80_addr),
        .z80_wdata  (w_z80_wdata),

        .new_fr_tgl (w_vga_fr_tgl),
        .lcd_rden   (w_lcd_rden),
        .lcd_addr   (w_lcd_phy_addr),
        .lcd_vld    (r_lcd_vld),
        .lcd_rdata  (r_lcd_rdata),

        .vram_we    (w_lcd_vram_we),
        .vram_data  (w_lcd_vram_data),
        .vram_addr  (w_lcd_vram_addr)
    );

    // ========================================================================
    // 640 x 480 VGA output
    // ========================================================================

    wire        w_vga_fr_tgl /* verilator public */;

    z88_vga the_vga
    (
        .rst        (rst),
        .clk        (clk),
        .clk_ena    (r_vga_ena),

        .lcd_on     (w_blk_lcd_on),
        .new_fr_tgl (w_vga_fr_tgl),
        .vram_we    (w_lcd_vram_we),
        .vram_data  (w_lcd_vram_data),
        .vram_addr  (w_lcd_vram_addr),

        .hsync      (vga_hs),
        .vsync      (vga_vs),
        .dena       (vga_de),
        .rgb        (vga_rgb)
    );

    assign vga_fr_tgl = w_vga_fr_tgl;

    // ========================================================================
    // External memory bus
    // ========================================================================

    // Controls
    reg  [3:1] r_ext_cs_n;
    reg        r_ext_oe_n;
    reg        r_ext_we_n;
    reg        r_rom_cs_n;
    reg  [1:0] r_rom_be_n;
    reg        r_ram_cs_n;
    reg  [1:0] r_ram_be_n;
    // Addresses
    reg [21:0] r_ext_addr;
    reg [18:0] r_ram_addr;
    reg [18:0] r_rom_addr;
    // Data
    reg [15:0] r_ram_rdata;
    reg [15:0] r_ram_wdata;
    reg [15:0] r_rom_rdata;
    reg  [7:0] r_z80_rdata /* verilator public */;
    reg  [7:0] r_lcd_rdata;
    reg        r_lcd_vld;

    always @(posedge rst or posedge clk) begin : EXT_MEM_BUS
        reg v_cpu_ram_rd; // Z80 RAM read
        reg v_cpu_rom_rd; // Z80 ROM read
        reg v_cpu_byte;   // Z80 reads LSB(0) / MSB(1)
        reg v_lcd_ram_rd; // LCD RAM read
        reg v_lcd_rom_rd; // LCD ROM read
        reg v_lcd_byte;   // LCD reads LSB(0) / MSB(1)

        if (rst) begin
            r_ext_cs_n   <= 3'b111;
            r_ext_oe_n   <= 1'b1;
            r_ext_we_n   <= 1'b1;
            r_rom_cs_n   <= 1'b1;
            r_rom_be_n   <= 2'b11;
            r_ram_cs_n   <= 1'b1;
            r_ram_be_n   <= 2'b11;

            r_ext_addr   <= 22'd0;
            r_ram_addr   <= 19'd0;
            r_rom_addr   <= 19'd0;

            r_ram_rdata  <= 16'h0000;
            r_ram_wdata  <= 16'h0000;
            r_rom_rdata  <= 16'h0000;
            r_z80_rdata  <= 8'h00;
            r_lcd_rdata  <= 8'h00;
            r_lcd_vld    <= 1'b0;

            v_cpu_ram_rd <= 1'b0;
            v_cpu_rom_rd <= 1'b0;
            v_cpu_byte   <= 1'b0;
            v_lcd_ram_rd <= 1'b0;
            v_lcd_rom_rd <= 1'b0;;
            v_lcd_byte   <= 1'b0;
        end
        else begin
            if (r_clk_ena[1]) begin
                if (r_bus_ph) begin
                    // Z80 access
                    r_ext_oe_n    <= ~w_z80_mem_rd;
                    r_ext_we_n    <= ~w_z80_mem_wr;
                    r_rom_cs_n    <= (w_cpu_phy_addr[21:19] == 3'b000) ? w_z80_mreq_n : 1'b1;
                    r_ram_cs_n    <= (w_cpu_phy_addr[21:19] == 3'b001) ? w_z80_mreq_n : 1'b1;
                    r_ext_cs_n[1] <= (w_cpu_phy_addr[21:20] == 2'b01 ) ? w_z80_mreq_n : 1'b1;
                    r_ext_cs_n[2] <= (w_cpu_phy_addr[21:20] == 2'b10 ) ? w_z80_mreq_n : 1'b1;
                    r_ext_cs_n[3] <= (w_cpu_phy_addr[21:20] == 2'b11 ) ? w_z80_mreq_n : 1'b1;
                end
                else begin
                    // LCD access
                    r_ext_oe_n    <= ~w_lcd_rden;
                    r_ext_we_n    <= 1'b1;
                    r_rom_cs_n    <= (w_lcd_phy_addr[21:19] == 3'b000) ? ~w_lcd_rden : 1'b1;
                    r_ram_cs_n    <= (w_lcd_phy_addr[21:19] == 3'b001) ? ~w_lcd_rden : 1'b1;
                    r_ext_cs_n[1] <= (w_lcd_phy_addr[21:20] == 2'b01 ) ? ~w_lcd_rden : 1'b1;
                    r_ext_cs_n[2] <= (w_lcd_phy_addr[21:20] == 2'b10 ) ? ~w_lcd_rden : 1'b1;
                    r_ext_cs_n[3] <= (w_lcd_phy_addr[21:20] == 2'b11 ) ? ~w_lcd_rden : 1'b1;
                end
            end
            else if (r_clk_ena[3]) begin
                // Keep track of previous bus phase access
                if (r_bus_ph) begin
                    v_cpu_ram_rd <= ~r_ram_cs_n;
                    v_cpu_rom_rd <= ~r_rom_cs_n;
                    v_cpu_byte   <= (r_ram_cs_n) ? r_rom_be_n[0] : r_ram_be_n[0];
                    v_lcd_ram_rd <= 1'b0;
                    v_lcd_rom_rd <= 1'b0;
                    v_lcd_byte   <= 1'b0;
                end
                else begin
                    v_cpu_ram_rd <= 1'b0;
                    v_cpu_rom_rd <= 1'b0;
                    v_cpu_byte   <= 1'b0;
                    v_lcd_ram_rd <= ~r_ram_cs_n;
                    v_lcd_rom_rd <= ~r_rom_cs_n;
                    v_lcd_byte   <= (r_ram_cs_n) ? r_rom_be_n[0] : r_ram_be_n[0];
                end
                // De-select SRAM chip
                r_ram_cs_n <= 1'b1;
            end

            // External memory
            r_ext_addr <= w_lcd_phy_addr | w_cpu_phy_addr;
            // Internal RAM (Slot 0)
            if (RAM_DATA_WIDTH == 8) begin
                r_ram_be_n  <= 2'b10;
                r_ram_addr  <= (w_lcd_phy_addr[18:0] | w_cpu_phy_addr[18:0]) & RAM_ADDR_MASK[18:0];
                r_ram_rdata <= { 8'h00, ram_rdata[7:0] };
                r_ram_wdata <= { 8'h00, w_z80_wdata };
            end
            else begin
                r_ram_be_n  <= (w_lcd_phy_addr[0] | w_cpu_phy_addr[0]) ? 2'b01 : 2'b10;
                r_ram_addr  <= { 1'b0, (w_lcd_phy_addr[18:1] | w_cpu_phy_addr[18:1]) & RAM_ADDR_MASK[18:1] };
                r_ram_rdata <= ram_rdata[15:0];
                r_ram_wdata <= { w_z80_wdata, w_z80_wdata };
            end
            // Internal ROM (Slot 0)
            if (ROM_DATA_WIDTH == 8) begin
                r_rom_be_n  <= 2'b10;
                r_rom_addr  <= w_lcd_phy_addr[18:0] | w_cpu_phy_addr[18:0];
                r_rom_rdata <= { 8'h00, rom_rdata[7:0] };
            end
            else begin
                r_rom_be_n  <= (w_lcd_phy_addr[0] | w_cpu_phy_addr[0]) ? 2'b01 : 2'b10;
                r_rom_addr  <= { 1'b0, w_lcd_phy_addr[18:1] | w_cpu_phy_addr[18:1] };
                r_rom_rdata <= rom_rdata[15:0];
            end

            // Z80 data read
            casez ({ v_cpu_ram_rd, v_cpu_rom_rd, v_cpu_byte })
                3'b00? : if (w_z80_io_rd)
                             r_z80_rdata <= w_blk_rdata[ 7:0];
                         else if (r_ext_cs_n != 3'b111)
                             r_z80_rdata <= 8'h00;
                3'b010 : if (r_clk_ena[2]) r_z80_rdata <= r_rom_rdata[ 7:0];
                3'b011 : if (r_clk_ena[2]) r_z80_rdata <= r_rom_rdata[15:8];
                3'b1?0 : if (r_clk_ena[0]) r_z80_rdata <= r_ram_rdata[ 7:0];
                3'b1?1 : if (r_clk_ena[0]) r_z80_rdata <= r_ram_rdata[15:8];
            endcase
            // LCD data read
            casez ({ v_lcd_ram_rd, v_lcd_rom_rd, v_lcd_byte })
                3'b00? :                   r_lcd_rdata <= 8'h00;
                3'b010 : if (r_clk_ena[2]) r_lcd_rdata <= r_rom_rdata[ 7:0];
                3'b011 : if (r_clk_ena[2]) r_lcd_rdata <= r_rom_rdata[15:8];
                3'b1?0 : if (r_clk_ena[0]) r_lcd_rdata <= r_ram_rdata[ 7:0];
                3'b1?1 : if (r_clk_ena[0]) r_lcd_rdata <= r_ram_rdata[15:8];
            endcase
            r_lcd_vld <= r_clk_ena[2] & v_lcd_rom_rd | r_clk_ena[0] & v_lcd_ram_rd;
        end
    end

    // Internal RAM (Slot 0)
    assign ram_ce_n  = r_ram_cs_n;
    assign ram_we_n  = r_ext_we_n;
    assign ram_oe_n  = r_ext_oe_n;
    assign ram_be_n  = r_ram_be_n;
    assign ram_addr  = r_ram_addr[18:0];
    assign ram_wdata = r_ram_wdata;

    // Internal ROM (Slot 0)
    assign rom_ce_n  = r_rom_cs_n;
    assign rom_oe_n  = r_ext_oe_n;
    assign rom_be_n  = r_rom_be_n;
    assign rom_addr  = r_rom_addr[18:0];

endmodule
