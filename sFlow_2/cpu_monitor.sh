#!/bin/bash

echo "Monitoring CPU usage from processes for 10 seconds..."

sum_total=0

for i in {1..10}; do
    # 抓出 top 輸出中非 idle 的 process（%CPU > 0）
    cpu_sum=$(top -b -n 1 | awk '
        BEGIN {sum=0}
        NR>7 && $9 > 0 {sum += $9}
        END {printf "%.1f", sum}')

    echo "Second $i: Total active process CPU usage: $cpu_sum%"
    sum_total=$(echo "$sum_total + $cpu_sum" | bc)
    sleep 1
done

avg=$(echo "scale=2; $sum_total / 10" | bc)
echo "---------------------------------------------"
echo "Average total CPU usage from active processes: $avg%"
