# SDC for rv32i_core, 500 MHz target
# Library-specific names (driving cell) must be changed for GF 28 nm.
set CLK_PERIOD 2.0
create_clock -name core_clk -period $CLK_PERIOD [get_ports clk_i]
set_clock_uncertainty 0.10 [get_clocks core_clk]
set_clock_transition 0.10 [get_clocks core_clk]

set non_clk_inputs [lsearch -inline -all -not -exact [all_inputs] [get_ports clk_i]]
set_input_delay  [expr 0.2 * $CLK_PERIOD] -clock core_clk $non_clk_inputs
set_output_delay [expr 0.2 * $CLK_PERIOD] -clock core_clk [all_outputs]

set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 $non_clk_inputs
set_load 0.005 [all_outputs]

# reset is asynchronous
set_false_path -from [get_ports rst_ni]
