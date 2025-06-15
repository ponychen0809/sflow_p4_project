#!/bin/bash

total=0

for i in {1..10}; do
    echo "===== Sample $i ====="
    usage=$(top -bn1 | awk 'NR > 7 && $9 ~ /^[0-9.]+$/ { sum += $9; printf "%-6s %-20s %5s%%\n", $1, $12, $9 } END { print "------------------------"; printf "Total: %.2f\n", sum }' | tee /tmp/out.txt | tail -n 1 | cut -d':' -f2)
    total=$(echo "$total + $usage" | bc)
    sleep 1
done

average=$(echo "scale=2; $total / 10" | bc)
echo
echo "============================"
echo "Average total CPU usage: $average%"
