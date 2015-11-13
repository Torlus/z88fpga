#define DPI_DLLISPEC
#define DPI_DLLESPEC

#include "z80ex_dasm.h"

#include "verilated.h"
#include "svdpi.h"

#include "Vz88.h"

#include <ctime>

#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

// Number of simulation steps
#define NUM_STEPS    ((vluint64_t)( (491520 * 2) + 10 ))
// Half period (in ps) of a 9.8304 MHz clock
#define STEP_PS      ((vluint64_t)5086)
// 5ms clock period = 2,500,000,000 ps
// So we will toggle the clock every 2,500,000,000 / 5086 = 491520 ticks
// of the MCLK
// (divided by 10 for debugging = 0.5ms)
//#define CLK5MS_TICKS ((vluint64_t)49152)

#define ROM_SIZE      (1<<22)
#define RAM_SIZE      (1<<19)

// Simulation steps (global)
vluint64_t tb_sstep;
vluint64_t tb_time;
//vluint64_t clk5ms_ticks;

Vz88* top;
vluint8_t ROM[ROM_SIZE];
size_t rom_size;
vluint8_t RAM[RAM_SIZE];

// Disassembly
FILE *logger;
bool disas_rom, disas_ram;

Z80EX_BYTE disas_readbyte(Z80EX_WORD addr, void *user_data) {
  if (disas_rom)
    return ROM[addr & (rom_size-1)];
  if (disas_ram)
    return RAM[addr & (RAM_SIZE-1)];
  fprintf(logger, "PC: Unexpected location %04X\n", addr);
  return 0xFF;
}

int main(int argc, char **argv, char **env)
{
    // Trace index
    int trc_idx = 0;
    // File name generation
    char file_name[256];
    // Simulation duration
    time_t beg, end;
    double secs;

    beg = time(0);

    Verilated::commandArgs(argc, argv);
    // Init top verilog instance
    top = new Vz88;

#if VM_TRACE
    // Init VCD trace dump
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace (tfp, 99);
    tfp->spTrace()->set_time_resolution ("1 ps");
    sprintf(file_name, "z88_%04d.vcd", trc_idx++);
    tfp->open (file_name);
#endif

    // Initialize simulation inputs
    top->reset_n = 0;
    top->clk = 1;
    // top->clk5ms = 1;

    top->ram_do = 0;
    top->rom_do = 0;

    top->ps2clk = 1;
    top->ps2dat = 1;

    tb_sstep = 0;  // Simulation steps (64 bits)
    tb_time = 0;  // Simulation time in ps (64 bits)

    // clk5ms_ticks = 0;

    // Load the ROM file
    FILE *rom = fopen("Z88UK400.rom","rb");
    if (rom == NULL) {
      printf("Cannot open ROM file for reading.\n");
      exit(-1);
    }
    rom_size = fread(ROM, 1, ROM_SIZE, rom);
    fclose(rom);
    printf("Loaded %ld bytes from ROM file.\n", rom_size);
    int rom_shift = 0;
    while( (1 << rom_shift) < rom_size )
      rom_shift++;
    if ( (1 << rom_shift) != rom_size ) {
      rom_size = 1 << rom_shift;
      printf("ROM file packed into a %lu-bytes ROM.\n", rom_size);
    }

    // For disassembly
    logger = fopen("z88_dasm.log", "wb");
    int m1_prev = 1;
    char disas_out[256];
    int t_states, t_states2;

    #define BYTETOBINARYPATTERN "%s%s%s%s%s%s"
    #define BYTETOBINARY(byte)  \
    (byte & 0x80 ? "S" : "."), \
    (byte & 0x40 ? "Z" : "."), \
    (byte & 0x10 ? "H" : "."), \
    (byte & 0x04 ? "P" : "."), \
    (byte & 0x02 ? "N" : "."), \
    (byte & 0x01 ? "C" : ".")

    // Run simulation for NUM_CYCLES clock periods
    while (tb_sstep < NUM_STEPS)
    {
        // Reset ON during 12 cycles
        top->reset_n = (tb_sstep < (vluint64_t)24) ? 0 : 1;
        // Toggle clock
        top->clk = top->clk ^ 1;
        // Generate the 5ms clock
        //if (++clk5ms_ticks == CLK5MS_TICKS) {
        //  top->clk5ms ^= 1;
        //  clk5ms_ticks = 0;
        //}
        // Evaluate verilated model
        top->eval();

        // Disassembly
        if (!top->v__DOT__z88_m1_n && !top->v__DOT__z88_mreq_n && top->v__DOT__z88_pm1 && m1_prev) {
          vluint16_t regPC = top->v__DOT__z80__DOT__i_tv80_core__DOT__PC;
          vluint16_t regSP = top->v__DOT__z80__DOT__i_tv80_core__DOT__SP;
          vluint8_t regA = top->v__DOT__z80__DOT__i_tv80_core__DOT__ACC;
          vluint8_t regI = top->v__DOT__z80__DOT__i_tv80_core__DOT__I;
          vluint8_t regF = top->v__DOT__z80__DOT__i_tv80_core__DOT__F;
          vluint8_t regB = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__B;
          vluint8_t regC = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__C;
          vluint8_t regD = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__D;
          vluint8_t regE = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__E;
          vluint8_t regH = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__H;
          vluint8_t regL = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__L;
          vluint16_t regIX = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__IX;
          vluint16_t regIY = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__IY;
          vluint8_t busD = top->v__DOT__z88_cdo;

          fprintf(logger, "%04X  ", regPC);
          z80ex_dasm(disas_out, 256, 0, &t_states, &t_states2, disas_readbyte,
            /*regPC*/ top->ram_a, NULL);
          fprintf(logger, "%-16s  ", disas_out);
          fprintf(logger, "%02X  "BYTETOBINARYPATTERN"  %02X%02X %02X%02X %02X%02X  %04X %04X  %04X\n",
            regA, BYTETOBINARY(regF), regB, regC, regD, regE, regH, regL, regIX, regIY, regSP);
        }
        m1_prev = !top->v__DOT__z88_m1_n && !top->v__DOT__z88_mreq_n && top->v__DOT__z88_pm1;

        // Simulate ROM behaviour
        if (!top->rom_oe_n && !top->rom_ce_n) {
          disas_rom = true; disas_ram = false;
          top->rom_do = ROM[top->rom_a & (rom_size-1)];
        } else {
          top->rom_do = 0xFF;
        }

        // Simulate RAM behaviour
        if (!top->ram_oe_n && !top->ram_ce_n) {
          disas_rom = false; disas_ram = true;
          top->ram_do = ROM[top->ram_a & (RAM_SIZE-1)];
        } else {
          top->ram_do = 0xFF;
        }
        if (!top->ram_we_n && !top->ram_ce_n) {
          RAM[top->ram_a & (RAM_SIZE-1)] = top->ram_di;
        }


#if VM_TRACE
        // Dump signals into VCD file
        if (tfp)
        {
            if (0)
            {
                // New VCD file
                tfp->close();
                sprintf(file_name, "z88_%04d.vcd", trc_idx++);
                tfp->open(file_name);
            }
            tfp->dump(tb_time);
        }
#endif

        // Next simulation step
        tb_time += STEP_PS;
        tb_sstep++;

        if ((tb_sstep & 4095) == 0)
        {
            printf("\r%lu us", tb_time / 1000000 );
            fflush(stdout);
        }

        if (Verilated::gotFinish()) break;
    }
    top->final();
    fclose(logger);

#if VM_TRACE
    if (tfp) tfp->close();
#endif

    end = time(0);
    secs = difftime(end, beg);
    printf("\n\nSeconds elapsed : %f\n", secs);

    exit(0);
}
