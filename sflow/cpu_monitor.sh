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

        # 即時顯示目前這秒的 process
        if [[ $(echo "$cpu > 0" | bc) -eq 1 ]]; then
            printf "PID=%s\tCPU=%.2f\tCMD=%s\n" "$pid" "$cpu" "$cmd"
        fi

        # 累加即使是 0 也要（以利平均準確），但等等過濾
        key="${pid}_${cmd}"
        cpu_sum["$key"]=$(echo "${cpu_sum[$key]:-0} + $cpu" | bc)
        count["$key"]=$(( ${count[$key]:-0} + 1 ))
    done

    sleep 1
done

# 輸出平均，但只寫入 avg > 0 的
echo -e "\nSummary (saved to $OUTPUT_FILE):"
echo -e "PID\tCOMMAND\t\tAVG_CPU(%)" > "$OUTPUT_FILE"
for key in "${!cpu_sum[@]}"; do
    avg=$(echo "scale=2; ${cpu_sum[$key]} / ${count[$key]}" | bc)
    is_positive=$(echo "$avg > 0" | bc)
    if [ "$is_positive" -eq 1 ]; then
        pid=${key%%_*}
        cmd=${key#*_}
        printf "%s\t%-16s\t%s\n" "$pid" "$cmd" "$avg"
    fi
done | sort -k3 -nr | tee -a "$OUTPUT_FILE"
