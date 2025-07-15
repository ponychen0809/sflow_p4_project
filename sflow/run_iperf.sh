#!/bin/bash

IPERF_CMD="iperf -c 10.10.3.5 -u -b 2G -l 512 -t 30"

for i in {1..5}
do
    xterm -hold -e "$IPERF_CMD" &
done
