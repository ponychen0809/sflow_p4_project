#!/bin/bash
# 每 0.5 秒取樣一次，共 50 次；即時印出各核心使用率，最後印每核心平均與總平均

LC_ALL=C

declare -A prev_idle prev_total
declare -A sum count

print_and_accumulate() {
  while read -r tag user nice system idle iowait irq softirq steal rest; do
    [[ "$tag" =~ ^cpu ]] || break
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))

    pi=${prev_idle[$tag]:-}
    pt=${prev_total[$tag]:-}

    if [[ -n "$pt" ]]; then
      di=$(( idle  - pi ))
      dt=$(( total - pt ))
      if (( dt > 0 )); then
        usage=$(( (100 * (dt - di) + dt/2) / dt ))
        printf "%-5s 使用率: %3d%%\n" "$tag" "$usage"
        sum[$tag]=$(( ${sum[$tag]:-0} + usage ))
        count[$tag]=$(( ${count[$tag]:-0} + 1 ))
      fi
    fi

    prev_idle[$tag]=$idle
    prev_total[$tag]=$total
  done < /proc/stat
}

echo "開始紀錄 CPU 使用率 (每 0.5 秒一次，共 50 次)..."
echo

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

overall_sum=0
core_count=0

for k in $(printf "%s\n" "${!sum[@]}" | sort -V); do
  avg=$(( sum[$k] / count[$k] ))
  printf "%-5s 平均使用率: %3d%%\n" "$k" "$avg"
  # 只算 cpu0、cpu1…，不包含總 cpu
  if [[ "$k" =~ ^cpu[0-9]+$ ]]; then
    overall_sum=$(( overall_sum + avg ))
    core_count=$(( core_count + 1 ))
  fi
done

if (( core_count > 0 )); then
  overall_avg=$(( overall_sum / core_count ))
  echo "--------------------------"
  printf "所有核心總平均使用率: %3d%%\n" "$overall_avg"
fi
