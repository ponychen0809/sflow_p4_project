#!/bin/bash

OUTPUT_FILE="cpu_record.txt"
> "$OUTPUT_FILE"

declare -A cpu_sum
declare -A count
declare -A pid_cmd_map
iterations=10
total_cpu_usage_sum=0  # 系統總使用率累加（%）

echo "Monitoring CPU usage for $iterations seconds..."
echo "Each second's snapshot:"

for ((i=1; i<=iterations; i++)); do
    echo "----- Second $i -----"

    # 🔽 使用 /proc/stat 抓系統總 CPU 使用率（真實多核心總和）
    read cpu user nice system idle iowait irq softirq steal guest < /proc/stat
    prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    prev_idle=$((idle + iowait))

    sleep 1

    read cpu user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 guest2 < /proc/stat
    total=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
    idle=$((idle2 + iowait2))

    diff_total=$((total - prev_total))
    diff_idle=$((idle - prev_idle))
    cpu_usage=$(echo "scale=2; (100 * ($diff_total - $diff_idle)) / $diff_total" | bc)
    total_cpu_usage_sum=$(echo "$total_cpu_usage_sum + $cpu_usage" | bc)

    # 🔽 抓每個 process 使用率
    mapfile -t lines < <(ps -eo pid,%cpu,comm --no-headers)

    for line in "${lines[@]}"; do
        pid=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        cmd=$(echo "$line" | awk '{print $3}')

        key="$pid"
        pid_cmd_map["$key"]="$cmd"

        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        cpu_sum["$key"]=$(echo "${cpu_sum[$key]:-0} + $cpu" | bc)
        count["$key"]=$(( ${count[$key]:-0} + 1 ))
    done
done

# 🧮 計算平均總 CPU 使用率
avg_total_cpu=$(echo "scale=2; $total_cpu_usage_sum / $iterations" | bc)

# 🧾 每個 process 的平均 CPU
TMP_RESULT=$(mktemp)
for pid in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$pid]} / ${count[$pid]}" | bc)
    if [[ $(echo "$avg > 0" | bc) -eq 1 ]]; then
        cmd=${pid_cmd_map[$pid]}
        printf "%s\t%s\t%.2f\n" "$pid" "$cmd" "$avg" >> "$TMP_RESULT"
    fi
done

# ✅ 寫入檔案
{
    echo -e "PID\tCOMMAND\t\tAVG_CPU(%)"
    sort -t $'\t' -k3,3nr "$TMP_RESULT"
    echo ""
    echo "System average total CPU usage over $iterations seconds: $avg_total_cpu %"
} > "$OUTPUT_FILE"

echo -e "\nSummary (saved to $OUTPUT_FILE):"
cat "$OUTPUT_FILE"
rm "$TMP_RESULT"
