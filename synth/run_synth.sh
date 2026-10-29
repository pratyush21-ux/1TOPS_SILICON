#!/usr/bin/env bash
# Run inside WSL from this folder:  bash run_synth.sh
set -e
cd "$(dirname "$0")"
mkdir -p reports netlist
if [ ! -f sky130_hd_tt.lib ]; then
  LIB="$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
  if [ -n "$PDK_ROOT" ] && [ -f "$LIB" ]; then
    cp "$LIB" sky130_hd_tt.lib
  else
    curl -L -o sky130_hd_tt.lib https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
  fi
fi
yosys -l reports/yosys.log rv32i_core_sky130.ys
grep -E "Chip area|sequential" reports/area_flat.rpt
