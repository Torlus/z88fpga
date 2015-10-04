Z88 in a FPGA
---

# Requirements

- A working C++ compiler.
- Verilator
- Gtkwave
- A binary image of a ROM.

# Instructions

```
./compile
./obj_dir/Vz88
gtkwave z88_0000.vcd
```

From gtkwave, File -> Read Save File, and select "view.gtkw".
