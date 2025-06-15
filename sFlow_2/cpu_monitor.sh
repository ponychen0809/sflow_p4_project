#!/bin/bash

echo "Monitoring CPU usage every second, 5 times total..."
echo

total_sum=0

for i in {1..5}; do
    echo "===== Sample $i ====="
    echo "PID     COMMAND              CPU(%)"
    echo "-------------------------------"

    # 使用 ps 並避免欄位名稱混淆
    sample_total=$(ps -eo pid=,comm=,pcpu= --sort=-pcpu | awk '
    $3 > 0.0 {
        printf "%-7s %-20s %6.2f\n", $1, $2, $3
        total += $3
    }
    END {
        print "-------------------------------"
        printf "Total CPU usage this round: %6.2f%%\n", total
        print total
    }' | tee /tmp/sample_output.txt | tail -n 1)

    total_sum=$(echo "$total_sum + $sample_total" | bc)

    sleep 1
done

average=$(echo "scale=2; $total_sum / 5" | bc)
echo
echo "========================================"
echo "Average total CPU usage over 5 rounds: $average%"
