#!/bin/bash
# 0.5 秒取樣一次，共 50 次；每次即時印出各核心使用率，最後印平均

declare -A prev_idle prev_total
declare -A sum count

read_stat() {
  # 讀取 /proc/stat 中所有 cpu/cpu0/cpu1... 的 idle 和 total
  while read -r tag user nice system idle iowait irq softirq steal rest; do
    [[ "$tag" =~ ^cpu ]] || break
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    CUR_IDLE[$tag]=$idle
    CUR_TOTAL[$tag]=$total
  done < /proc/stat
}

echo "開始紀錄 CPU 使用率 (每 0.5 秒一次，共 50 次)..."
echo

# 先讀一次做為前一刻
read_stat
for core in "${!CUR_IDLE[@]}"; do
  prev_idle[$core]=${CUR_IDLE[$core]}
  prev_total[$core]=${CUR_TOTAL[$core]}
done

# 取樣 50 次
for i in $(seq 1 50); do
  sleep 0.5

  # 讀現在的數值
  read_stat

  echo "---- 第 $i 次 ----"
  for core in "${!CUR_IDLE[@]}"; do
    di=$(( CUR_IDLE[$core]  - prev_idle[$core]  ))
    dt=$(( CUR_TOTAL[$core] - prev_total[$core] ))
    if (( dt > 0 )); then
      # 使用率(%) = 100 * (1 - di/dt)
      # 為了整數運算，四捨五入到整數百分比
      usage=$(( (100 * (dt - di) + dt/2) / dt ))
      printf "%-5s 使用率: %3d%%\n" "$core" "$usage"

      sum[$core]=$(( ${sum[$core]:-0} + usage ))
      count[$core]=$(( ${count[$core]:-0} + 1 ))
    fi
    # 更新前一刻
    prev_idle[$core]=${CUR_IDLE[$core]}
    prev_total[$core]=${CUR_TOTAL[$core]}
  done
done

echo
echo "=========================="
echo " 每個核心平均 CPU 使用率 "
echo "=========================="
for core in "${!sum[@]}"; do
  avg=$(( sum[$core] / count[$core] ))
  printf "%-5s 平均使用率: %3d%%\n" "$core" "$avg"
done | sort
