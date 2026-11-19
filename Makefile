RTL   := rtl/nco.sv rtl/cic_decimator.sv rtl/ddc.sv
BUILD := build

.PHONY: test lint synth clean

test:
	@mkdir -p $(BUILD)
	python3 -c "import sys; sys.path.insert(0, 'scripts'); import run_checks; run_checks.gen_lut('$(BUILD)/sine_quarter.hex')"
	iverilog -g2012 -o $(BUILD)/tb.vvp $(RTL) tb/tb_ddc.sv
	python3 scripts/run_checks.py $(BUILD) $(BUILD)/tb.vvp

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --top-module ddc $(RTL)

synth:
	@mkdir -p $(BUILD)
	yosys -q -p "read_verilog -sv rtl/cic_decimator.sv; synth -top cic_decimator; tee -o $(BUILD)/synth_cic.txt stat"

clean:
	rm -rf $(BUILD)
