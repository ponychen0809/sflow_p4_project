#!/bin/bash

total=0

for i in {1..10}; do
    cpu=$(top -bn1 | awk 'NR > 7 && $9 ~ /^[0-9.]+$/ { sum += $9 } END { print sum }')
    echo "Sample $i: $cpu%"
    total=$(echo "$total + $cpu" | bc)
    sleep 1
done

average=$(echo "scale=2; $total / 10" | bc)
echo "============================="
echo "Average total CPU usage: $average%"
