#!/bin/bash

echo "Monitoring CPU usage every second, 5 times total..."
echo

total_sum=0

for i in {1..5}; do
    echo "===== Sample $i ====="
    echo "PID     COMMAND              CPU(%)"
    echo "-------------------------------"

    # 取得 top 輸出並篩選有使用 CPU 的 process
    sample_total=$(top -b -n1 | awk '
    NR > 7 && $9 > 0 {
        pid = $1
        cpu = $9
        cmd = $12
        total += cpu
        printf "%-7s %-20s %6.2f\n", pid, cmd, cpu
    }
    END {
        print "-------------------------------"
        printf "Total CPU usage this round: %6.2f%%\n", total
        print total
    }' | tee /tmp/sample_output.txt | tail -n 1)

    # 累加每輪的總 CPU 使用率
    total_sum=$(echo "$total_sum + $sample_total" | bc)

    sleep 1
done

average=$(echo "scale=2; $total_sum / 5" | bc)
echo
echo "========================================"
echo "Average total CPU usage over 5 rounds: $average%"
