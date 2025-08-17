#!/bin/bash

declare -A sum count

echo "開始紀錄 CPU 使用率 (每 0.5 秒一次，共 50 次)..."

for i in $(seq 1 50)
do
    # 取得 mpstat 輸出，顯示所有核心
    mpstat -P ALL 1 1 | awk '/^[0-9]+/ {print $3, 100 - $13}' | while read core usage
    do
        sum[$core]=$(echo "${sum[$core]:-0} + $usage" | bc)
        count[$core]=$((${count[$core]:-0} + 1))
    done
    sleep 0.5
done

echo
echo "=========================="
echo " 每個核心平均 CPU 使用率 "
echo "=========================="

for core in "${!sum[@]}"
do
    avg=$(echo "scale=2; ${sum[$core]} / ${count[$core]}" | bc)
    printf "CPU%-3s 平均使用率: %.2f%%\n" "$core" "$avg"
done | sort
