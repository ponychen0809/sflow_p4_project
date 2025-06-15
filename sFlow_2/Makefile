clear:
	rm -f *log*
	rm -f ptf.pcap
	rm -rf __pycache__

test:
	${SDE}/run_p4_tests.sh -p simple_switch -t ./ -s simple_switch_test.SimpleSwitchTest -f ./ports.json

build:
	~/p4_build.sh simple_switch.p4

bfrt:
	${SDE}/run_switchd.sh -p simple_switch

cpu:
	git reset --hard
	git pull
	sudo chmod +x ./cpu_monitor.sh
	./cpu_monitor.sh