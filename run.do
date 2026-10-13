quit -sim
vlib work
vlog xxxx.v xxxx.v
vsim -voptargs=+acc work.xxxx
add wave -radix unsigned /xxxx/*
run -all
wave zoom full