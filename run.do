#compiles everything and runs the testbench with waveforms
#run from the project folder in modelsim with: do run.do

quit -sim
vlib work
vlog rtl/cache.v rtl/lru.v rtl/plru.v tb/mem_model.v tb/tb_cache.v
vsim -voptargs=+acc work.tb_cache
add wave -radix unsigned -r /*
run -all
wave zoom full
