create_clock -name CLOCK_50 -period 20.0 [get_ports CLOCK_50]

derive_pll_clocks

derive_clock_uncertainty

set_clock_groups -asynchronous \
-group { \
	pll|altpll_component|pll|clk[0] \
} \
-group { \
	pll|altpll_component|pll|clk[1] \
}


create_clock -period 100.0 -name sys_clk

set_output_delay -clock sys_clk -max 0.0 [get_ports {SRAM_ADDR[*] SRAM_DQ[*]}]
set_output_delay -clock sys_clk -min 0.0 [get_ports {SRAM_ADDR[*] SRAM_DQ[*]}]

set_input_delay -clock sys_clk -max 0.0 [get_ports {SRAM_DQ[*]}]
set_input_delay -clock sys_clk -min 0.0 [get_ports {SRAM_DQ[*]}]

set_output_delay -clock sys_clk -max 0.0 [get_ports {FL_ADDR[*]}]
set_output_delay -clock sys_clk -min 0.0 [get_ports {FL_ADDR[*]}]

set_input_delay -clock sys_clk -max 0.0 [get_ports {FL_DQ[*]}]
set_input_delay -clock sys_clk -min 0.0 [get_ports {FL_DQ[*]}]
