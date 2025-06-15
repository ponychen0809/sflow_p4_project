#!/bin/bash

echo "Monitoring CPU usage every second, 5 times total..."
echo

total_sum=0

for i in {1..5}; do
    echo "----- Sample $i -----"
    echo "PID   COMMAND              CPU(%)"
    echo "-------------------------------"

    # 執行 top 並處理有佔用 CPU 的 processes
    sample_total=$(top -b -n1 | awk '
    NR > 7 && $9 > 0 {
        pid=$1
        cpu=$9
        command=$12
        total += cpu
        printf "%-5s %-20s %6.2f\n", pid, command, cpu
    }
    END {
        print "-------------------------------"
        printf "Total CPU usage this round: %6.2f%%\n", total
        print total
    }' | tee /tmp/sample_cpu.txt | tail -n 1)

    total_sum=$(echo "$total_sum + $sample_total" | bc)
    sleep 1
done

average=$(echo "scale=2; $total_sum / 5" | bc)
echo
echo "======================================="
echo "Average total CPU usage over 5 rounds: $average%"
