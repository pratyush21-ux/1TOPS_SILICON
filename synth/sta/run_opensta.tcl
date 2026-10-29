# OpenSTA run for the Yosys gate-level netlist.
#   sta -exit run_opensta.tcl        (from synth/sta/)
# Change LIB and NETLIST for GF 28 nm.
set LIB     ../sky130_hd_tt.lib
set NETLIST ../netlist/rv32i_core_sky130.v

read_liberty $LIB
read_verilog $NETLIST
link_design rv32i_core
read_sdc core_500MHz.sdc

report_checks -path_delay max -group_path_count 5 -fields {slew cap input_pins fanout} -digits 3 > reports/opensta_setup.rpt
report_checks -path_delay min -group_path_count 5 -digits 3 > reports/opensta_hold.rpt
report_tns > reports/opensta_summary.rpt
report_wns >> reports/opensta_summary.rpt
report_worst_slack -max >> reports/opensta_summary.rpt
report_worst_slack -min >> reports/opensta_summary.rpt
report_check_types -max_slew -max_capacitance -violators >> reports/opensta_summary.rpt
