#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"  # 清空舊檔案

declare -A cpu_sum         # PID => CPU 累加值
declare -A count           # PID => 出現次數
declare -A pid_cmd_map     # PID => CMD 名稱
iterations=10

echo "Monitoring CPU usage for $iterations seconds..."
echo "Each second's snapshot:"

for ((i=1; i<=iterations; i++)); do
    echo "----- Second $i -----"
    mapfile -t lines < <(ps -eo pid,%cpu,comm --no-headers)

    for line in "${lines[@]}"; do
        pid=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | awk '{print $3}')

        # 記錄 PID 與對應 command name
        pid_cmd_map["$pid"]="$cmd"

        # 即時顯示 CPU > 0 的項目
        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        # 累加每個 PID 的 CPU 使用量與出現次數
        cpu_sum["$pid"]=$(echo "${cpu_sum[$pid]:-0} + $cpu" | bc)
        count["$pid"]=$(( ${count[$pid]:-0} + 1 ))
    done

    sleep 1
done

# 準備輸出：每個 PID 的平均 CPU 使用率
TMP_RESULT=$(mktemp)
for pid in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$pid]} / ${count[$pid]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        cmd=${pid_cmd_map[$pid]}
        printf "%s\t%s\t%.2f\n" "$pid" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

# 輸出並依 AVG_CPU 排序
{
    echo -e "PID\tCOMMAND\t\tAVG_CPU(%)"
    sort -t $'\t' -k3,3nr "$TMP_RESULT"
} > "$OUTPUT_FILE"

echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"
rm "$TMP_RESULT"
