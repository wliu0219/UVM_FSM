TESTNAME ?= test_1011

all: work tb sim dump wave

work:
	vlib work

tb:
	vlog -f filelist.f

sim:
	vsim tb +UVM_TESTNAME=$(TESTNAME) -do "run -all;exit" -c -l $(TESTNAME).log -voptargs=+acc

dump:
	vcd2wlf dump.vcd dump.wlf

wave:
	vsim -view dump.wlf

clean:
	rm -r work
	rm *.log transcript vsim.* *.ucdb

