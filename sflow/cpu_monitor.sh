#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"  # 清空輸出檔

declare -A cpu_sum
declare -A count
declare -A pid_cmd_map
iterations=10

echo "Monitoring CPU usage for $iterations seconds..."
echo "Each second's snapshot:"

for ((i=1; i<=iterations; i++)); do
    echo "----- Second $i -----"
    mapfile -t lines < <(ps -eo pid,%cpu,comm --no-headers)

    for line in "${lines[@]}"; do
        # 處理一行：PID、%CPU、CMD
        pid=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | cut -d' ' -f3-)

        key="${pid}"  # ✅ 以 PID 為唯一 key，完全去重
        pid_cmd_map["$key"]="$cmd"

        # 只顯示當前 CPU > 0 的 process
        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        cpu_sum["$key"]=$(echo "${cpu_sum[$key]:-0} + $cpu" | bc)
        count["$key"]=$(( ${count[$key]:-0} + 1 ))
    done
    sleep 1
done

# 統整輸出
TMP_RESULT=$(mktemp)
for pid in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$pid]} / ${count[$pid]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        cmd=${pid_cmd_map[$pid]}
        printf "%s\t%-20s\t%.2f\n" "$pid" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

# 寫入檔案並排序（依照第 3 欄）
{
    echo -e "PID\tCOMMAND\t\t\tAVG_CPU(%)"
    sort -k3,3nr "$TMP_RESULT"
} > "$OUTPUT_FILE"

echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"
rm "$TMP_RESULT"
