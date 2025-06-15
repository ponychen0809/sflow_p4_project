#!/bin/bash

total=0

for i in {1..10}; do
    echo "===== Sample $i ====="
    echo "PID     COMMAND              CPU(%)"
    echo "-------------------------------"

    # 同時列出 process 與加總 CPU 使用率
    round_total=$(top -bn1 | awk '
    NR > 7 && $9 ~ /^[0-9.]+$/ && $9 > 0 {
        pid = $1
        cpu = $9
        cmd = $12
        printf "%-7s %-20s %6.2f\n", pid, cmd, cpu
        sum += cpu
    }
    END {
        print "-------------------------------"
        printf "Total CPU this round:     %6.2f%%\n", sum
        print sum
    }' | tee /tmp/sample_output.txt | tail -n 1)

    total=$(echo "$total + $round_total" | bc)
    sleep 1
done

average=$(echo "scale=2; $total / 10" | bc)
echo
echo "======================================"
echo "Average total CPU usage: $average%"
