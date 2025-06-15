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

    mapfile -t lines < <(ps -eo pid,%cpu,comm --no-headers)

    for line in "${lines[@]}"; do
        pid=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | cut -d' ' -f3-)

        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        # ✅ 用 CMD 作為 key，把相同名稱的程式合併統計
        key="$cmd"
        cpu_sum["$key"]=$(echo "${cpu_sum[$key]:-0} + $cpu" | bc)
        count["$key"]=$(( ${count[$key]:-0} + 1 ))
    done

    sleep 1
done

# 🔽 輸出時正確排序並過濾 avg = 0
TMP_RESULT=$(mktemp)

for cmd in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$cmd]} / ${count[$cmd]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        printf "%-20s\t%s\n" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

# 輸出表頭與排序內容
{
    echo -e "COMMAND\t\t\tAVG_CPU(%)"
    sort -t $'\t' -k2,2nr "$TMP_RESULT"
} > "$OUTPUT_FILE"

echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"
rm "$TMP_RESULT"
