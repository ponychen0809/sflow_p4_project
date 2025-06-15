#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"

declare -A cpu_sum
declare -A count
declare -A pid_cmd_map
iterations=10
total_cpu_usage_sum=0  # 將所有 process 的 %CPU 加總

echo "Monitoring CPU usage for $iterations seconds..."
echo "Each second's snapshot:"

for ((i=1; i<=iterations; i++)); do
    echo "----- Second $i -----"

    # 抓所有 process 使用率（含 PID, %CPU, CMD）
    mapfile -t lines < <(ps -eo pid,%cpu,comm --no-headers)

    total_cpu_this_round=0  # 每秒總 %CPU 加總（所有 process）

    for line in "${lines[@]}"; do
        pid=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | awk '{print $3}')

        key="$pid"
        pid_cmd_map["$key"]="$cmd"

        # 顯示當下的活躍 process
        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        cpu_sum["$key"]=$(echo "${cpu_sum[$key]:-0} + $cpu" | bc)
        count["$key"]=$(( ${count[$key]:-0} + 1 ))

        total_cpu_this_round=$(echo "$total_cpu_this_round + $cpu" | bc)
    done

    # 將當秒的所有 process %CPU 加總進 total_cpu_usage_sum
    total_cpu_usage_sum=$(echo "$total_cpu_usage_sum + $total_cpu_this_round" | bc)
done

# 計算平均總 CPU 使用率（取 10 次 process 總使用率的平均）
avg_total_cpu=$(echo "scale=2; $total_cpu_usage_sum / $iterations" | bc)

# 建立每個 process 的平均 %CPU 結果
TMP_RESULT=$(mktemp)
for pid in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$pid]} / ${count[$pid]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        cmd=${pid_cmd_map[$pid]}
        printf "%s\t%s\t%.2f\n" "$pid" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

# 輸出到檔案並排序
{
    echo -e "PID\tCOMMAND\t\tAVG_CPU(%)"
    sort -t $'\t' -k3,3nr "$TMP_RESULT"
    echo ""
    echo "System average total CPU usage over $iterations seconds: $avg_total_cpu %"
} > "$OUTPUT_FILE"

echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"
rm "$TMP_RESULT"
