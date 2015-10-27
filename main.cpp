#define DPI_DLLISPEC
#define DPI_DLLESPEC

#include "verilated.h"
#include "svdpi.h"

#include "Vz88.h"

#include <ctime>

#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

// Number of simulation steps
#define NUM_STEPS    ((vluint64_t)205000)
// Half period (in ps) of a 33.333 MHz clock
#define STEP_PS      ((vluint64_t)15000)

#define ROM_SIZE      (1<<22)

// Simulation steps (global)
vluint64_t tb_sstep;
vluint64_t tb_time;

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
    Vz88* top = new Vz88;

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

    // Load the ROM file
    vluint8_t ROM[ROM_SIZE];
    FILE *rom = fopen("Z88UK400.rom","rb");
    if (rom == NULL) {
      printf("Cannot open ROM file for reading.\n");
      exit(-1);
    }
    size_t rom_size = fread(ROM, 1, ROM_SIZE, rom);
    fclose(rom);
    printf("Loaded %ld bytes from ROM file.\n", rom_size);
    int rom_shift = 0;
    while( (1 << rom_shift) < rom_size )
      rom_shift++;
    if ( (1 << rom_shift) != rom_size ) {
      rom_size = 1 << rom_shift;
      printf("ROM file packed into a %lu-bytes ROM.\n", rom_size);
    }

    // Run simulation for NUM_CYCLES clock periods
    while (tb_sstep < NUM_STEPS)
    {
        // Reset ON during 12 cycles
        top->reset_n = (tb_sstep < (vluint64_t)24) ? 0 : 1;
        // Toggle clock
        top->clk = top->clk ^ 1;
        // Evaluate verilated model
        top->eval();

        // Simulate ROM behaviour
        if (!top->rom_oe_n && !top->rom_ce_n) {
          top->rom_do = ROM[top->rom_a & (rom_size-1)];
        } else {
          top->rom_do = 0xFF;
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

#if VM_TRACE
    if (tfp) tfp->close();
#endif

    end = time(0);
    secs = difftime(end, beg);
    printf("\n\nSeconds elapsed : %f\n", secs);

    exit(0);
}
