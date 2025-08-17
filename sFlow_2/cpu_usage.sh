#!/bin/bash
# 每 0.5 秒取樣一次，共 50 次；每次即時印出各核心使用率，最後印平均（整數 %）
# 若要浮點小數我也可以再改成小數點兩位

LC_ALL=C

declare -A prev_idle prev_total
declare -A sum count

print_and_accumulate() {
  # 逐行讀 /proc/stat，遇到 cpu/cpu0/cpu1... 就當場算、印、累加
  while read -r tag user nice system idle iowait irq softirq steal rest; do
    [[ "$tag" =~ ^cpu ]] || break
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))

    # 前一刻
    pi=${prev_idle[$tag]:-}
    pt=${prev_total[$tag]:-}

    if [[ -n "$pt" ]]; then
      di=$(( idle  - pi ))
      dt=$(( total - pt ))
      if (( dt > 0 )); then
        # 使用率 = 100 * (1 - di/dt) ；四捨五入成整數 %
        usage=$(( (100 * (dt - di) + dt/2) / dt ))
        printf "%-5s 使用率: %3d%%\n" "$tag" "$usage"
        sum[$tag]=$(( ${sum[$tag]:-0} + usage ))
        count[$tag]=$(( ${count[$tag]:-0} + 1 ))
      fi
    fi

    # 更新前一刻
    prev_idle[$tag]=$idle
    prev_total[$tag]=$total
  done < /proc/stat
}

echo "開始紀錄 CPU 使用率 (每 0.5 秒一次，共 50 次)..."
echo

# 先讀一次作為基準
print_and_accumulate >/dev/null

for i in $(seq 1 50); do
  sleep 0.5
  echo "---- 第 $i 次 ----"
  print_and_accumulate
done

echo
echo "=========================="
echo " 每個核心平均 CPU 使用率 "
echo "=========================="
# 依名稱排序，先 cpu（總和），再 cpu0、cpu1...
for k in $(printf "%s\n" "${!sum[@]}" | sort -V); do
  avg=$(( sum[$k] / count[$k] ))
  printf "%-5s 平均使用率: %3d%%\n" "$k" "$avg"
done
