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
#define NUM_STEPS    ((vluint64_t)( (491520 * 1) + 10 ))
// Half period (in ps) of a 9.8304 MHz clock
#define STEP_PS      ((vluint64_t)5086)

#define ROM_SIZE      (1<<19)
#define RAM_SIZE      (1<<19)
#define VRAM_SIZE     (1<<14)

#define TIME_SPLIT    ((vluint64_t)1000000000)

// Simulation steps (global)
vluint64_t tb_sstep;
vluint64_t tb_time;
vluint64_t tb_time_split;


Vz88* top;
vluint8_t ROM[ROM_SIZE];
size_t rom_size;
vluint8_t RAM[RAM_SIZE];
vluint8_t VRAM[VRAM_SIZE];

// Disassembly
FILE *logger;
bool disas_rom, disas_ram;
int whichb;
int opcode[4];
int rrPC;

void GrabBytes(int rPC, int Byte0, int Byte1, int Byte2, int Byte3) {
rrPC = rPC;
opcode[0] = Byte0;
opcode[1] = Byte1;
opcode[2] = Byte2;
opcode[3] = Byte3;
}

Z80EX_BYTE disas_readbyte(Z80EX_WORD addr, Z80EX_BYTE bank) {
  whichb = addr - rrPC;
  return opcode[whichb];
}

Z80EX_BYTE disas_readbyte_top(Z80EX_WORD addr, Z80EX_BYTE unused) {
  if (disas_rom)
    return ROM[addr & (rom_size - 1)];
  if (disas_ram)
    return RAM[addr & (RAM_SIZE - 1)];
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

    top->ram_do = 0;
    top->rom_do = 0;

    top->ps2clk = 1;
    top->ps2dat = 1;

    tb_sstep = 0;  // Simulation steps (64 bits)
    tb_time = 0;  // Simulation time in ps (64 bits)
    tb_time_split = 0;

    // Load the ROM file
    //FILE *rom = fopen("Z88UK400.rom","rb");
    FILE *rom = fopen("oz47b.rom","rb");
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
    bool m1_prev = true;
    bool mreq_prev = true;
    bool first = false;
    int opcn = 0;
    int opc [5];
    vluint64_t opctime = 0;
    char disas_out[256];
    int t_states, t_states2;
    int bnk;
    int regA;
    int regF;
    int regB;
    int regC;
    int regD;
    int regE;
    int regH;
    int regL;
    int seg0;
    int seg;
    int com;
    int regPC;
    int regSP;
    int regIX;
    int regIY;

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

        // Simulate ROM behaviour
        if (!top->rom_oe_n && !top->rom_ce_n) {
          disas_rom = true; disas_ram = false;
          top->rom_do = ROM[top->rom_a & (ROM_SIZE-1)];
        } else {
          top->rom_do = 0xFF;
        }

        // Simulate RAM behaviour
        if (!top->ram_oe_n && !top->ram_ce_n) {
          disas_rom = false; disas_ram = true;
          top->ram_do = RAM[top->ram_a & (RAM_SIZE-1)];
        } else {
          top->ram_do = 0xFF;
        }
        if (!top->ram_we_n && !top->ram_ce_n) {
          RAM[top->ram_a & (RAM_SIZE-1)] = top->ram_di;
        }

        // Simulate VRAM behaviour
        if (top->clk) {
          top->vram_rp_do = VRAM[top->vram_rp_a & (VRAM_SIZE-1)] & 0x0f;
          if (top->vram_wp_we) {
            VRAM[top->vram_wp_a & (VRAM_SIZE-1)] = (top->vram_wp_di & 0x0f);
          }
        }


        // Evaluate verilated model
        top->eval();

        // Disassembly
        if (!top->v__DOT__z88_m1_n && !top->v__DOT__z88_mreq_n && top->v__DOT__z88_pm1 && m1_prev) {
          if (first) {
            if (opcn == 1 && (opc[0] == 0xCB || opc[0] == 0xED || opc[0] == 0xDD || opc[0] == 0xFD)){
              first = false;
            }
            else{
              fprintf(logger, "%6lu  ", opctime / 1000000);
              fprintf(logger, "%02X%04X  ", bnk, regPC);
              GrabBytes(regPC, opc[0], opc[1], opc[2], opc[3]);
              z80ex_dasm(disas_out, 256, 0, &t_states, &t_states2, disas_readbyte, regPC, bnk);
              fprintf(logger, "%-16s  ", disas_out);
              //for (int i = 0; i <= opcn; ++i){
              //  fprintf(logger, "%02X ", opc[i]);
              //}
              //fprintf (logger, "\n", NULL);
              fprintf(logger, "%02X  "BYTETOBINARYPATTERN"  %02X%02X %02X%02X %02X%02X  %04X %04X  %04X\n",
               regA, BYTETOBINARY(regF), regB, regC, regD, regE, regH, regL, regIX, regIY, regSP);
              opcn = 0;
              opctime = tb_time;
            }
          }
          first = true;
          opc[opcn] = top->v__DOT__z80_cdi;
          ++opcn;
          regPC = top->v__DOT__z80__DOT__i_tv80_core__DOT__PC;
          regSP = top->v__DOT__z80__DOT__i_tv80_core__DOT__SP;
          regA = top->v__DOT__z80__DOT__i_tv80_core__DOT__ACC;
          regF = top->v__DOT__z80__DOT__i_tv80_core__DOT__F;
          regB = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__B;
          regC = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__C;
          regD = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__D;
          regE = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__E;
          regH = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__H;
          regL = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__L;
          regIX = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__IX;
          regIY = top->v__DOT__z80__DOT__i_tv80_core__DOT__i_reg__DOT__IY;
          seg0 = (regPC>>13 & 0x07);
          seg = (regPC>>14 & 0x03);
          com = top->v__DOT__theblink__DOT__com;
          // vluint8_t bnk;
            if (!seg0) {
              if (com & 0x04) {bnk = 0x20;}
              else {bnk = 0X00;}
            }
            else{
              switch(seg){
                case 0x00:{bnk = top->v__DOT__theblink__DOT__sr0;
                break;}
                case 0x01:{bnk = top->v__DOT__theblink__DOT__sr1;
                break;}
                case 0x02:{bnk = top->v__DOT__theblink__DOT__sr2;
                break;}
                case 0x03:{bnk = top->v__DOT__theblink__DOT__sr3;
                break;}
              }
            }
        }
        m1_prev = !top->v__DOT__z88_m1_n && !top->v__DOT__z88_mreq_n && top->v__DOT__z88_pm1;

        if (top->v__DOT__z88_m1_n && !top->v__DOT__z88_mreq_n && top->v__DOT__z88_pm1 && mreq_prev) {
          opc[opcn] = top->v__DOT__z80_cdi;
          ++opcn;
        }
        mreq_prev = top->v__DOT__z88_m1_n && !top->v__DOT__z88_mreq_n && top->v__DOT__z88_pm1;



#if VM_TRACE
        // Dump signals into VCD file
        if (tfp)
        {
            if ((TIME_SPLIT > 0) && (tb_time - tb_time_split >= TIME_SPLIT))
            {
                tb_time_split = tb_time;
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
