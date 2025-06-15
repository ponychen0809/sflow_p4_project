#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"  # 清空檔案

declare -A cpu_sum
declare -A count
iterations=10

echo "Monitoring CPU usage for $iterations seconds..."

for ((i=1; i<=iterations; i++)); do
    # 抓取目前每個 process 的 PID、%CPU、COMMAND
    ps -eo pid,%cpu,comm --no-headers | awk '$2 > 0 {print}' | while read pid cpu cmd; do
        key="${pid}_${cmd}"
        cpu_sum["$key"]=$(echo "${cpu_sum[$key]:-0} + $cpu" | bc)
        count["$key"]=$(( ${count[$key]:-0} + 1 ))
    done
    sleep 1
done

# 印出結果
echo -e "PID\tCOMMAND\t\tAVG_CPU(%)" > "$OUTPUT_FILE"
for key in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$key]} / ${count[$key]}" | bc)
    pid=${key%%_*}
    cmd=${key#*_}
    printf "%s\t%-16s\t%s\n" "$pid" "$cmd" "$avg"
done | sort -k3 -nr >> "$OUTPUT_FILE"

cat "$OUTPUT_FILE"
