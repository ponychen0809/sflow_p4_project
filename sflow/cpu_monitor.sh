#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"  # 清空舊內容

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
        pid=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | cut -d' ' -f3-)

        key="${pid}_${cmd}"  # ✅ 唯一辨識用
        pid_cmd_map["$key"]="$pid $cmd"

        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        cpu_sum["$key"]=$(echo "${cpu_sum[$key]:-0} + $cpu" | bc)
        count["$key"]=$(( ${count[$key]:-0} + 1 ))
    done

    sleep 1
done

# ✅ 建立排序用暫存檔（每行：PID\tCMD\tAVG_CPU）
TMP_RESULT=$(mktemp)
for key in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$key]} / ${count[$key]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        pid=$(echo "${pid_cmd_map[$key]}" | cut -d' ' -f1)
        cmd=$(echo "${pid_cmd_map[$key]}" | cut -d' ' -f2-)
        printf "%s\t%s\t%s\n" "$pid" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

# ✅ 寫入表頭與排序後內容
{
    echo -e "PID\tCOMMAND\t\tAVG_CPU(%)"
    sort -k3,3nr "$TMP_RESULT"
} > "$OUTPUT_FILE"

# ✅ 顯示結果
echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"
rm "$TMP_RESULT"
