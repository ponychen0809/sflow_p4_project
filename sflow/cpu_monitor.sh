#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"

declare -A cpu_sum
declare -A count
iterations=10

echo "Monitoring CPU usage for $iterations seconds..."
echo "Each second's snapshot:"

for ((i=1; i<=iterations; i++)); do
    echo "----- Second $i -----"
    mapfile -t lines < <(ps -eo %cpu,comm --no-headers)

    for line in "${lines[@]}"; do
        cpu=$(echo "$line" | awk '{print $1}')
        cmd=$(echo "$line" | cut -d' ' -f2-)

        # 只顯示 CPU > 0 的即時項目
        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "CPU=%.2f\tCMD=%s\n" "$cpu" "$cmd"
        fi

        # 合併統計以 CMD 為 key
        cpu_sum["$cmd"]=$(echo "${cpu_sum[$cmd]:-0} + $cpu" | bc)
        count["$cmd"]=$(( ${count[$cmd]:-0} + 1 ))
    done
    sleep 1
done

# 暫存檔寫入每個 CMD 的平均 CPU
TMP_RESULT=$(mktemp)
for cmd in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$cmd]} / ${count[$cmd]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        printf "%-20s\t%s\n" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

# 輸出表頭與排序後內容
{
    echo -e "COMMAND\t\t\tAVG_CPU(%)"
    sort -k2,2nr "$TMP_RESULT"
} > "$OUTPUT_FILE"

echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"
rm "$TMP_RESULT"
