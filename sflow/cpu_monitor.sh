#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"

declare -A cpu_sum
declare -A count
declare -A pid_cmd_map
iterations=10
total_cpu=0  # 累加系統總 CPU 使用率

echo "Monitoring CPU usage for $iterations seconds..."
echo "Each second's snapshot:"

for ((i=1; i<=iterations; i++)); do
    echo "----- Second $i -----"
    
    # ⏺ 抓系統總 CPU 使用率（user + system）
    cpu_line=$(top -bn1 | grep "%Cpu(s)")
    us=$(echo "$cpu_line" | awk '{print $2}')
    sy=$(echo "$cpu_line" | awk '{print $4}')
    cpu_total_sec=$(echo "$us + $sy" | bc)
    total_cpu=$(echo "$total_cpu + $cpu_total_sec" | bc)

    # 抓每個 process 使用率
    mapfile -t lines < <(ps -eo pid,%cpu,comm --no-headers)

    for line in "${lines[@]}"; do
        pid=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | awk '{print $3}')

        key="${pid}"
        pid_cmd_map["$key"]="$cmd"

        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        cpu_sum["$pid"]=$(echo "${cpu_sum[$pid]:-0} + $cpu" | bc)
        count["$pid"]=$(( ${count[$pid]:-0} + 1 ))
    done

    sleep 1
done

# 🧮 系統總 CPU 平均
avg_total_cpu=$(echo "scale=2; $total_cpu / $iterations" | bc)

# 🧾 準備寫入每個 PID 的平均 CPU
TMP_RESULT=$(mktemp)
for pid in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$pid]} / ${count[$pid]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        cmd=${pid_cmd_map[$pid]}
        printf "%s\t%s\t%.2f\n" "$pid" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

# 🖨️ 寫入並排序，附加總 CPU 使用率
{
    echo -e "PID\tCOMMAND\t\tAVG_CPU(%)"
    sort -t $'\t' -k3,3nr "$TMP_RESULT"
    echo ""
    echo "System average total CPU usage over $iterations seconds: $avg_total_cpu %"
} > "$OUTPUT_FILE"

echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"
rm "$TMP_RESULT"
