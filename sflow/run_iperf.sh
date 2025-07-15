#!/bin/bash

# 設定要執行的 iperf 指令
IPERF_CMD="iperf -c 10.10.3.5 -u -b 2G -l 512 -t 30"

# 開啟 5 個終端機並執行指令
for i in {1..5}
do
    gnome-terminal -- bash -c "$IPERF_CMD; exec bash" &
done
