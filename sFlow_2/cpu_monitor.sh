#!/bin/bash

total_sum=0

for i in {1..10}; do
    echo "======== Sampling #$i ========"

    sum=0
    # 印出有使用CPU的process，並加總
    top -b -n 1 | awk '
        BEGIN { printf "%-8s %-25s %s\n", "PID", "COMMAND", "CPU(%)"; s = 0; }
        /^[ 0-9]+ / {
            pid = $1
            cpu = $9
            cmd = $12
            if (cpu + 0 > 0) {
                printf "%-8s %-25s %s\n", pid, cmd, cpu
                s += cpu
            }
        }
        END {
            printf "\n[Total CPU Usage This Round]: %.2f%%\n", s
            print s > "/tmp/top_sum_tmp"
        }
    '

    # 讀取這一輪的總 CPU 使用率
    round_sum=$(cat /tmp/top_sum_tmp)
    total_sum=$(echo "$total_sum + $round_sum" | bc)
    sleep 1
done

avg=$(echo "scale=2; $total_sum / 10" | bc)
echo "========================================="
echo "Average total CPU usage over 10 rounds: $avg%"
