// -----------------------------------------------------------------------------
//  Z88 SCREEN
// -----------------------------------------------------------------------------
module screen(
// Inputs:
mck, rin_n, lcdon,
cdi, mrq_n,
pb0, pb1, pb2, pb3, sbr,

// Outputs:
ma, roe_n, ipce_n, irce_n,
vram_a, vram_do, vram_we
);

// Clocks and control
input           mck;
input           rin_n;
input           lcdon;

// Blink screen registers
input           pb0;
input           pb1;
input           pb2;
input           pb3;
input           sbr;

// Z88 memory
input   [7:0]   cdi;
input           mrq_n;
output  [21:0]  ma;
output          roe_n;
output          ipce_n;
output          irce_n;

// VRAM buffer
output  [13:0]  vram_a;
output  [3:0]   vram_do;
output          vram_we;

// Blink screen registers
wire    [12:0]  pb0;  // Lores0 (ROM, 64 chars map)
wire    [9:0]   pb1;  // Lores1 (RAM, 512-64 char map)
wire    [8:0]   pb2;  // Hires0 (ROM, 256 char map)
wire    [10:0]  pb3;  // Hires1 (RAM, 1024-256 char map)
wire    [10:0]  sbr;  // SBR Screen Base Register

// Screen clock
// Pulse on mck if LCDON and memory not used by Z80 CPU
wire            sclk;
assign          sclk = mck & lcdon & mrq_n;

endmodule
