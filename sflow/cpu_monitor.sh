#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"  # 清空舊內容

declare -A cpu_sum
declare -A count
iterations=10

echo "Monitoring CPU usage for $iterations seconds..."
echo "Each second's snapshot:"

for ((i=1; i<=iterations; i++)); do
    echo "----- Second $i -----"

    mapfile -t lines < <(ps -eo pid,%cpu,comm --no-headers)

    for line in "${lines[@]}"; do
        pid=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | cut -d' ' -f3-)

        # 即時顯示 CPU > 0 的程序
        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        # 累加統計
        key="${pid}_${cmd}"
        cpu_sum["$key"]=$(echo "${cpu_sum[$key]:-0} + $cpu" | bc)
        count["$key"]=$(( ${count[$key]:-0} + 1 ))
    done

    sleep 1
done

# 🔽 將 avg > 0 的條目收集進暫存檔案，並排序後輸出
TMP_RESULT=$(mktemp)

for key in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$key]} / ${count[$key]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        pid=${key%%_*}
        cmd=${key#*_}
        printf "%s\t%-16s\t%s\n" "$pid" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

# 寫入表頭與排序後內容
{
    echo -e "PID\tCOMMAND\t\tAVG_CPU(%)"
    sort -k3 -nr "$TMP_RESULT"
} > "$OUTPUT_FILE"

# 顯示結果
echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"

# 刪除暫存檔
rm "$TMP_RESULT"
