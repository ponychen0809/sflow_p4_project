#!/bin/bash

output_file="cpu_record.txt"
> "$output_file"  # 清空舊檔

echo "Collecting CPU usage every 0.5s, total 20 times..."

for i in {1..20}; do
    timestamp=$(date +"%H:%M:%S")
    usage=$(top -bn1 | awk 'NR > 7 && $9 ~ /^[0-9.]+$/ { sum += $9 } END { print sum }')
    echo "$timestamp $usage" >> "$output_file"
    echo "[$i] $timestamp → CPU: $usage%"
    sleep 0.5
done

# 計算平均
average=$(awk '{sum += $2} END {if (NR>0) printf "Average CPU usage: %.2f%%\n", sum / NR}' "$output_file")
echo "==============================="
echo "$average"
