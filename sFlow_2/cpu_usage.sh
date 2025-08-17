#!/bin/bash

declare -A sum count prev_idle prev_total

echo "開始紀錄 CPU 使用率 (每 0.5 秒一次，共 50 次)..."
echo

# 取 CPU 狀態
get_cpu_usage() {
    while read -r line; do
        [[ "$line" =~ ^cpu ]] || break
        cpu=($line)
        core=${cpu[0]}         # CPU 名稱 (cpu, cpu0, cpu1...)
        user=${cpu[1]}
        nice=${cpu[2]}
        system=${cpu[3]}
        idle=${cpu[4]}
        iowait=${cpu[5]}
        irq=${cpu[6]}
        softirq=${cpu[7]}
        steal=${cpu[8]}
        total=$((user+nice+system+idle+iowait+irq+softirq+steal))

        prev_i=${prev_idle[$core]:-0}
        prev_t=${prev_total[$core]:-0}

        diff_idle=$((idle - prev_i))
        diff_total=$((total - prev_t))
        usage=$((100 * (diff_total - diff_idle) / diff_total))

        if [ $prev_t -ne 0 ]; then
            echo "$core $usage"
        fi

        prev_idle[$core]=$idle
        prev_total[$core]=$total
    done < /proc/stat
}

# 50 次，每次間隔 0.5 秒
for i in $(seq 1 50); do
    echo "---- 第 $i 次 ----"
    get_cpu_usage | while read core usage; do
        sum[$core]=$((${sum[$core]:-0} + usage))
        count[$core]=$((${count[$core]:-0} + 1))
        printf "%-5s 使用率: %3d%%\n" "$core" "$usage"
    done
    sleep 0.5
done

echo
echo "=========================="
echo " 每個核心平均 CPU 使用率 "
echo "=========================="

for core in "${!sum[@]}"; do
    avg=$((sum[$core] / count[$core]))
    printf "%-5s 平均使用率: %3d%%\n" "$core" "$avg"
done | sort
