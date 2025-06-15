#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"  # 清空檔案

declare -A cpu_sum
declare -A count
iterations=10

echo "Monitoring CPU usage for $iterations seconds..."
echo "Each second's snapshot:"

for ((i=1; i<=iterations; i++)); do
    echo "----- Second $i -----"
    ps -eo pid,%cpu,comm --no-headers | while read pid cpu cmd; do
        # 顯示每秒活躍的 process 使用率
        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        # 累積統計
        key="${pid}_${cmd}"
        cpu_sum["$key"]=$(echo "${cpu_sum[$key]:-0} + $cpu" | bc)
        count["$key"]=$(( ${count[$key]:-0} + 1 ))
    done
    sleep 1
done

# 計算平均並輸出到檔案
echo -e "\nSummary (saved to $OUTPUT_FILE):"
echo -e "PID\tCOMMAND\t\tAVG_CPU(%)" > "$OUTPUT_FILE"
for key in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$key]} / ${count[$key]}" | bc)
    pid=${key%%_*}
    cmd=${key#*_}
    printf "%s\t%-16s\t%s\n" "$pid" "$cmd" "$avg"
done | sort -k3 -nr | tee -a "$OUTPUT_FILE"
