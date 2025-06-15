#!/bin/bash

total=0

for i in {1..10}; do
    echo "===== Sample $i ====="
    echo "PID     COMMAND              CPU(%)"
    echo "-------------------------------"

    # 使用 ps 抓出有佔用 CPU 的 process
    round_total=$(ps -eo pid=,comm=,pcpu= --sort=-pcpu | awk '
    $3 > 0.0 {
        printf "%-7s %-20s %6.2f\n", $1, $2, $3
        total += $3
    }
    END {
        print "-------------------------------"
        printf "Total CPU this round:     %6.2f%%\n", total
        print total
    }' | tee /tmp/round.txt | tail -n 1)

    total=$(echo "$total + $round_total" | bc)
    sleep 1
done

average=$(echo "scale=2; $total / 10" | bc)
echo
echo "======================================"
echo "Average total CPU usage: $average%"
