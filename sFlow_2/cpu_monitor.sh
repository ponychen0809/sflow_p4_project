#!/bin/bash

echo "Monitoring CPU usage for 10 seconds..."

total=0

for i in {1..10}; do
    # 抓取第一行 "cpu " 的欄位，計算 user, nice, system, idle, iowait, irq, softirq, steal...
    cpu_line=($(grep '^cpu ' /proc/stat))
    unset cpu_line[0]  # 移除 "cpu" 這個字
    prev_idle=${cpu_line[3]}
    prev_total=0
    for value in "${cpu_line[@]}"; do
        ((prev_total+=value))
    done

    sleep 1

    cpu_line=($(grep '^cpu ' /proc/stat))
    unset cpu_line[0]
    idle=${cpu_line[3]}
    total_now=0
    for value in "${cpu_line[@]}"; do
        ((total_now+=value))
    done

    # 計算 delta
    diff_idle=$((idle - prev_idle))
    diff_total=$((total_now - prev_total))
    diff_usage=$((100 * (diff_total - diff_idle) / diff_total))

    echo "CPU Usage at second $i: $diff_usage%"
    total=$((total + diff_usage))
done

avg=$((total / 10))
echo "--------------------------------"
echo "Average CPU Usage over 10s: $avg%"
