#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"  # 清空舊檔案

declare -A cpu_sum
declare -A count
declare -A cmd_pid  # 儲存第一次看到的 PID
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

        # 合併統計同名 command
        cpu_sum["$cmd"]=$(echo "${cpu_sum[$cmd]:-0} + $cpu" | bc)
        count["$cmd"]=$(( ${count[$cmd]:-0} + 1 ))

        # 儲存第一次看到的 pid（代表性）
        if [[ -z "${cmd_pid[$cmd]}" ]]; then
            cmd_pid["$cmd"]="$pid"
        fi
    done
    sleep 1
done

# 寫入平均結果（合併同名 command），含 PID，正確排序
TMP_RESULT=$(mktemp)
for cmd in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$cmd]} / ${count[$cmd]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        printf "%s\t%-20s\t%s\n" "${cmd_pid[$cmd]}" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

{
    echo -e "PID\tCOMMAND\t\t\tAVG_CPU(%)"
    sort -k3,3nr "$TMP_RESULT"
} > "$OUTPUT_FILE"

echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"
rm "$TMP_RESULT"
