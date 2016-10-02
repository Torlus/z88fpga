#define DPI_DLLISPEC
#define DPI_DLLESPEC

#include "EasyBMP.h"
#include "z80ex_dasm.h"

#include "verilated.h"
#include "svdpi.h"

#include "Vz88_de1.h"
#include "Vz88_de1_z88_de1.h"
#include "Vz88_de1_z88.h"
#include "Vz88_de1_blink.h"
#include "Vz88_de1_tv80s.h"
#include "Vz88_de1_tv80_reg.h"
#include "Vz88_de1_tv80_core__M0.h"

#include <ctime>

#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

// Number of simulation steps
#define NUM_STEPS    ((vluint64_t)100000000)
// Half period (in ps) of a 50 MHz clock
#define STEP_PS      ((vluint64_t)10000)

#define ROM_SIZE      (1<<19)
#define RAM_SIZE      (1<<18)
#define VRAM_SIZE     (1<<14)

#define TIME_SPLIT    ((vluint64_t)1000000000)

// Simulation steps (global)
vluint64_t tb_sstep;
vluint64_t tb_time;
vluint64_t tb_time_split;


Vz88_de1* top;
vluint8_t ROM[ROM_SIZE];
size_t rom_size;
vluint8_t RAM_U[RAM_SIZE];
vluint8_t RAM_L[RAM_SIZE];
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
  {
      if (addr & 1)
          return RAM_U[(addr >> 1) & (RAM_SIZE - 1)];
      else
          return RAM_L[(addr >> 1) & (RAM_SIZE - 1)];
  }
  fprintf(logger, "PC: Unexpected location %04X\n", addr);
  return 0xFF;
}

int main(int argc, char **argv, char **env)
{
    vluint16_t ram_dly;
    vluint8_t  rom_dly[7];
    // Trace index
    int trc_idx = 0;
    // File name generation
    char file_name[256];
    // Simulation duration
    time_t beg, end;
    double secs;
    // BMP
    BMP *bmp = new BMP;
    int bmp_idx = 0;
    bmp->SetBitDepth(24);
    bmp->SetSize(640, 64);

    beg = time(0);

    Verilated::commandArgs(argc, argv);
    // Init top verilog instance
    top = new Vz88_de1;

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
    top->SW = 3;
    top->CLOCK_50 = 1;

    top->SRAM_D  = 0;
    top->FL_D    = 0;

    top->PS2_CLK = 0;
    top->PS2_DAT = 0;

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
        // Reset ON during 15 cycles
        top->SW = (tb_sstep < (vluint64_t)30) ? 3 : 0;
        // Toggle clock
        top->CLOCK_50 = top->CLOCK_50 ^ 1;

        // Simulate ROM behaviour
        top->FL_D = rom_dly[6]; // 70ns latency
        rom_dly[6] = rom_dly[5];
        rom_dly[5] = rom_dly[4];
        rom_dly[4] = rom_dly[3];
        rom_dly[3] = rom_dly[2];
        rom_dly[2] = rom_dly[1];
        rom_dly[1] = rom_dly[0];
        if (!top->FL_OE_N && !top->FL_CE_N) {
          disas_rom = true; disas_ram = false;
          rom_dly[0] = ROM[top->FL_ADDR & (ROM_SIZE-1)];
        } else {
          rom_dly[0] = 0xFF;
        }

        // Simulate RAM behaviour
        top->SRAM_D = ram_dly; // 10ns latency
        if (!top->SRAM_OE_N && !top->SRAM_CE_N) {
          disas_rom = false; disas_ram = true;
          ram_dly =  (vluint16_t)RAM_L[top->SRAM_ADDR & (RAM_SIZE-1)]
                      | ((vluint16_t)RAM_U[top->SRAM_ADDR & (RAM_SIZE-1)] << 8);
        } else {
          ram_dly = 0xFFFF;
        }
        if (!top->SRAM_WE_N && !top->SRAM_CE_N) {
          if (!top->SRAM_LB_N) RAM_L[top->SRAM_ADDR & (RAM_SIZE-1)] = (vluint8_t)top->SRAM_Q;
          if (!top->SRAM_UB_N) RAM_U[top->SRAM_ADDR & (RAM_SIZE-1)] = (vluint8_t)(top->SRAM_Q >> 8);
        }

        // Simulate VRAM behaviour
        if (top->CLOCK_50) {
          //top->vram_rp_do = VRAM[top->vram_rp_a & (VRAM_SIZE-1)] & 0x0f;
          if (top->v->vram_wp_we) {
            VRAM[top->v->vram_wp_a & (VRAM_SIZE-1)] = (top->v->vram_wp_di & 0x0f);
          }
        }

        // Evaluate verilated model
        top->eval();

        // Disassembly
        if (!top->v->z88de1->z88_m1_n &&
            !top->v->z88de1->z88_mreq_n &&
             top->v->z88de1->z88_pm1 && m1_prev) {
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
          opc[opcn] = top->v->z88de1->w_z80_cdi;
          ++opcn;
          regPC = top->v->z88de1->z80->i_tv80_core->PC;
          regSP = top->v->z88de1->z80->i_tv80_core->SP;
          regA = top->v->z88de1->z80->i_tv80_core->ACC;
          regF = top->v->z88de1->z80->i_tv80_core->F;
          regB = top->v->z88de1->z80->i_tv80_core->i_reg->B;
          regC = top->v->z88de1->z80->i_tv80_core->i_reg->C;
          regD = top->v->z88de1->z80->i_tv80_core->i_reg->D;
          regE = top->v->z88de1->z80->i_tv80_core->i_reg->E;
          regH = top->v->z88de1->z80->i_tv80_core->i_reg->H;
          regL = top->v->z88de1->z80->i_tv80_core->i_reg->L;
          regIX = top->v->z88de1->z80->i_tv80_core->i_reg->IX;
          regIY = top->v->z88de1->z80->i_tv80_core->i_reg->IY;
          seg0 = (regPC>>13 & 0x07);
          seg = (regPC>>14 & 0x03);
          com = top->v->z88de1->theblink->com;
          // vluint8_t bnk;
            if (!seg0) {
              if (com & 0x04) {bnk = 0x20;}
              else {bnk = 0X00;}
            }
            else{
              switch(seg){
                case 0x00:{bnk = top->v->z88de1->theblink->sr0;
                break;}
                case 0x01:{bnk = top->v->z88de1->theblink->sr1;
                break;}
                case 0x02:{bnk = top->v->z88de1->theblink->sr2;
                break;}
                case 0x03:{bnk = top->v->z88de1->theblink->sr3;
                break;}
              }
            }
        }
        m1_prev = !top->v->z88de1->z88_m1_n &&
                  !top->v->z88de1->z88_mreq_n &&
                   top->v->z88de1->z88_pm1;

        if (top->v->z88de1->z88_m1_n &&
           !top->v->z88de1->z88_mreq_n &&
            top->v->z88de1->z88_pm1 && mreq_prev) {
          opc[opcn] = top->v->z88de1->w_z80_cdi;
          ++opcn;
        }
        mreq_prev = top->v->z88de1->z88_m1_n &&
                   !top->v->z88de1->z88_mreq_n &&
                    top->v->z88de1->z88_pm1;



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

        if (top->CLOCK_50 && top->v->frame) {
          int addr = 0;
          for(int y = 0; y < 64; y++) {
            addr = y * (1024 >> 2);
            for(int x = 0; x < 640; x++) {
              uint8_t dot = VRAM[addr] & (1 << (3 - (x & 3)));
              // uint8_t dot = VRAM[addr] & (1 << (x & 3));
              RGBApixel pixel;
              pixel.Red   = (dot) ? 0 : 255;
              pixel.Green = (dot) ? 0 : 255;
              pixel.Blue  = (dot) ? 0 : 255;
              bmp->SetPixel(x, y, pixel);
              if ((x & 3) == 3) addr++;
            }
          }
          sprintf(file_name, "vid_%04d.bmp", bmp_idx);
          bmp->WriteToFile(file_name);
          bmp_idx++;
        }

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
