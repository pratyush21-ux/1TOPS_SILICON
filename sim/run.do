# Questa run script for the rv32i tests.
#
#   batch:  vsim -c -do sim/run.do
#   GUI  :  cd to the repo root, then in the transcript:  do sim/run.do
#
# Compiles the core + both benches and runs tb_sort (full-core bubble sort)
# followed by tb_fib (iterative Fibonacci).
#
# Run from the REPO ROOT, not from sim/ — the bench loads hex files by a
# path relative to the current directory.

if {![file exists rtl/core/rv32i_core.v]} {
  error "run from the repo root: 'cd <...>/RV32I_rv32i' then 'do sim/run.do'"
}

if {[file exists sim/work]} { vdel -lib sim/work -all }
vlib sim/work

# +acc keeps signals visible so waveforms/hierarchical probes work in the GUI
# +incdir points to the defines header location
vlog -quiet -work sim/work +incdir+rtl/core -f sim/core.f tb/tb_sort.v tb/tb_fib.v

echo "\n######## tb_sort : full-core bubble sort ########"
vsim -quiet -onfinish stop -voptargs=+acc -work sim/work tb_sort
run -all
quit -sim

echo "\n######## tb_fib : iterative Fibonacci ########"
vsim -quiet -onfinish stop -voptargs=+acc -work sim/work tb_fib
run -all
quit -sim

# Only exit the tool in batch mode; in the GUI, stay open so waves are browsable.
if {[batch_mode]} { quit -f }
