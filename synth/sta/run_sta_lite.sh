#!/usr/bin/env bash
# Python NLDM static timing (no OpenSTA needed). Run from synth/sta/ after synth/run_synth.sh.
# Synthesizes a flattened netlist with a 2 ns (500 MHz) ABC target, then times it.
set -e
cd "$(dirname "$0")"
mkdir -p reports work
LIB=../sky130_hd_tt.lib
cat > work/abc_timing.script <<'EOS'
strash
&get -n
&fraig -x
&put
scorr
dc2
dretime
strash
&get -n
&dch -f
&nf -D 2000
&put
buffer -p
upsize -D 2000
dnsize -D 2000
stime -p
EOS
C=../../rtl/core
DU='-dont_use *lpflow* -dont_use *probe* -dont_use *clkdly* -dont_use *dlygate* -dont_use *dlymetal* -dont_use *_0'
yosys -q -l work/yosys_flat.log -p "read_verilog -I$C $C/rv32i_*.v ../../rtl/soc/cluster_clock_gating.v; hierarchy -check -top rv32i_core; synth -flatten -top rv32i_core; dfflibmap -liberty $LIB $DU; abc -liberty $LIB $DU -D 2000 -script work/abc_timing.script; opt_clean -purge; hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO; setundef -zero; tee -o reports/area_flat_500MHz_target.rpt stat -liberty $LIB; write_json work/core_flat_500.json"
yosys -q -p "read_liberty -lib $LIB" >/dev/null
awk '/"type":/ {gsub(/[",]/,"",$2); print $2}' work/core_flat_500.json | sort -u > work/cells.txt
python3 libparse.py $LIB work/cells.txt work/lib.pkl
python3 sta.py work/core_flat_500.json work/lib.pkl --lib $LIB --period 2.0 --top 5 --max-cap 0.03 --exclude-start '^dbg_|debug_unit' > reports/sta_500MHz_tt.rpt
head -4 reports/sta_500MHz_tt.rpt
