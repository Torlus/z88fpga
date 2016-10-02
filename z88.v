module z88
(
    // Clocks, Reset switch, Flap switch
    input           clk,
    input           reset_n,
    input           flap,  // normally closed =0, open =1
    
    // Debug output
    output          frame,  // BMP generator
    output          t_1s,   // 1 second blinking LED
    output  [7:0]   kbdval,
    output          pm1s,
    output          kbds,
    output          ints,
    output          key,
    
    // LCD on/off
    output          lcdon,
    
    // Keyboard matrix
    input   [63:0]  kbmatrix, // 8*8 keys
    
    // Internal RAM (512KB)
    output  [18:0]  ram_a,
    output  [7:0]   ram_di,
    input   [7:0]   ram_do,
    output          ram_ce_n,
    output          ram_oe_n,
    output          ram_we_n,
    
    // Internal ROM (512KB)
    output  [18:0]  rom_a,
    input   [7:0]   rom_do,
    output          rom_ce_n,
    output          rom_oe_n,
    
    // Dual-port VRAM write port (8KB)
    output          vram_wp_we,
    output  [13:0]  vram_wp_a,
    output  [3:0]   vram_wp_di
);

    assign ints = ~z88_int_n;
    

// Z88 PCB glue
wire            z88_sck;      // standby clock
wire            z88_pm1 /* verilator public */;      // Z80 clock
wire            z88_m1_n /* verilator public */;
wire            z88_mreq_n /* verilator public */;
wire            z88_iorq_n;
wire            z88_rd_n;
wire            z88_halt_n;
wire            z88_flap;
wire            z88_int_n;
wire            z88_nmi_n;
wire            z88_busrq_n;
wire    [21:0]  z88_ma;
wire    [15:0]  z88_ca;
wire    [7:0]   z80_do;
wire    [7:0]   z80_cdi;
wire    [7:0]   vid_cdi;
wire    [7:0]   z88_cdi;
wire            z88_ipce_n;
wire            z88_irce_n;
wire     [3:1]  z88_esel_n;
wire            z88_roe_n;
wire            z88_wrb_n;
wire            z88_rin_n;
wire            z88_rout_n;
wire    [63:0]  z88_kbmat;
`ifdef verilator3
wire            z88_lcdon;
`else
wire            z88_lcdon = 1'b1;
`endif
wire    [12:0]  z88_pb0;
wire    [9:0]   z88_pb1;
wire    [8:0]   z88_pb2;
wire    [10:0]  z88_pb3;
wire    [10:0]  z88_sbr;
wire    [2:0]   z88_clk_ph;
wire    [2:0]   z88_clk_ph_adv;
wire    [21:0]  z88_va;
wire            z88_t1s;
wire            z88_t5ms;

// Clock and Control

reg [4:0] r_clk_ena;

always@(negedge reset_n or posedge clk) begin : CLK_ENA

    if (!reset_n) begin
        r_clk_ena <= 5'b00001;
    end
    else begin
        r_clk_ena <= { r_clk_ena[3:0], r_clk_ena[4] }; 
    end
end

reg [7:0] r_ram_di;
wire [7:0] w_z80_cdi /* verilator public */;
reg  [7:0] r_z80_cdi;
wire [7:0] w_lcd_cdi;
reg  [7:0] r_lcd_cdi;

always@(negedge reset_n or posedge clk) begin : DATA_BUS

    if (!reset_n) begin
        r_ram_di  <= 8'h00;
        r_z80_cdi <= 8'h00;
        r_lcd_cdi <= 8'h00;
    end
    else begin
        // Z80 writes to RAM
        r_ram_di <= z80_do;
        // Z80 reads from RAM/ROM/Blink
        if (r_clk_ena[3] & z88_clk_ph[2]) begin
            if (!z88_irce_n)
                // RAM
                r_z80_cdi <= ram_do;
            else
                // Blink
                r_z80_cdi <= z80_cdi;
        end
        // LCD reads from RAM/ROM
        if (r_clk_ena[3] & ~z88_clk_ph[2]) begin
            if (!z88_irce_n)
                // RAM
                r_lcd_cdi <= ram_do;
            else
                // No read
                r_lcd_cdi <= 8'h00;
        end
    end
end

assign w_z80_cdi = (z88_ipce_n) ? r_z80_cdi : rom_do;
assign w_lcd_cdi = (z88_ipce_n) ? r_lcd_cdi : rom_do;

assign z88_kbmat = kbmatrix;
assign lcdon = z88_lcdon;
assign t_1s = z88_t1s;
assign z88_flap = flap;

// Internal RAM (Slot 0)
assign ram_a = z88_ma[18:0];
assign ram_di = z80_do;
assign ram_we_n = z88_wrb_n;
assign ram_oe_n = z88_roe_n;
assign ram_ce_n = z88_irce_n;

// Internal ROM (Slot 0)
assign rom_a = z88_ma[18:0];
assign rom_oe_n = z88_roe_n;
assign rom_ce_n = z88_ipce_n;

//assign z88_cdi = (!z88_ipce_n && !z88_roe_n) ? rom_do
//                : (!z88_irce_n & !z88_roe_n) ? ram_do
//                : (!z88_iorq_n & z88_rd_n) ? z80_do
//                : (!z88_mreq_n & z88_rd_n) ? z80_do
//                : 8'b11111111;

// Z80 instance
tv80s z80
(
  .m1_n(z88_m1_n),
  .mreq_n(z88_mreq_n),
  .iorq_n(z88_iorq_n),
  .rd_n(z88_rd_n),
  .wr_n(),                  // not wired
  .rfsh_n(),                // not wired
  .halt_n(z88_halt_n),
  .busak_n(),               // not wired
  .A(z88_ca),
  .dout(z80_do),
  .reset_n(reset_n),
  .clk(clk),
  .wait_n(1'b1),            // not wired
  .int_n(z88_int_n),
  .nmi_n(z88_nmi_n),
  .busrq_n(1'b1),           // not wired
  .di(w_z80_cdi),
  .cen(z88_clk_ph[2] & r_clk_ena[4])
);

// Blink instance
blink theblink
(
  .rst(~reset_n),
  .flp(z88_flap),
  .clk(clk),
  .clk_ena(r_clk_ena),
  .clk_ph(z88_clk_ph),
  .clk_ph_adv(z88_clk_ph_adv),
  // Z80 bus
  .z80_hlt_n(z88_halt_n),
  .z80_crd_n(z88_rd_n),
  .z80_cm1_n(z88_m1_n),
  .z80_mrq_n(z88_mreq_n),
  .z80_ior_n(z88_iorq_n),
  .z80_addr(z88_ca),
  .z80_wdata(z80_do),
  .z80_rdata(z80_cdi),
  .z80_nmi_n(z88_nmi_n),
  .z80_int_n(z88_int_n),
  // LCD control
  .lcd_addr(z88_va),
`ifdef verilator3
  .lcd_on(z88_lcdon),
`else
  //.lcd_on(z88_lcdon),
`endif
  .lcd_pb0(z88_pb0),
  .lcd_pb1(z88_pb1),
  .lcd_pb2(z88_pb2),
  .lcd_pb3(z88_pb3),
  .lcd_sbr(z88_sbr),
  // External bus
  .ext_oe_n(z88_roe_n),
  .ext_we_n(z88_wrb_n),
  .ram_cs_n(z88_irce_n),
  .rom_cs_n(z88_ipce_n),
  .ext_cs_n(z88_esel_n),
  .ext_addr(z88_ma),
  
  .kbmat(z88_kbmat),
  .t_1s(z88_t1s),
  .t_5ms(z88_t5ms),
  .kbdval(kbdval),  // Debug
  .pm1s(pm1s),      // Debug
  .kbds(kbds),      // Debug
  .key(key)         // Debug
);

// Screen instance
screen thescreen (
  .clk(clk),
  .clk_ena(r_clk_ena[4]),
  .clk_ph(z88_clk_ph),
  .clk_ph_adv(z88_clk_ph_adv),
  .rin_n(reset_n),
  .lcdon(z88_lcdon),
  .cdi(w_lcd_cdi),
  .pb0(z88_pb0),
  .pb1(z88_pb1),
  .pb2(z88_pb2),
  .pb3(z88_pb3),
  .sbr(z88_sbr),
  .va(z88_va),
  .o_vram_a(vram_wp_a),
  .o_vram_do(vram_wp_di),
  .o_vram_we(vram_wp_we),
  .t_1s(z88_t1s),
  .t_5ms(z88_t5ms),
  .o_frame(frame)
);



endmodule
