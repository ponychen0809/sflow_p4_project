#!/bin/bash

total=0

for i in {1..10}; do
    echo "===== Sample $i ====="
    echo "PID     COMMAND              CPU(%)"
    echo "-------------------------------"

    round_total=$(ps -eo pid,comm,pcpu --sort=-pcpu | awk '
    NR > 1 && $3 + 0 > 0 {
        printf "%-7s %-20s %6.2f\n", $1, $2, $3
        sum += $3
    }
    END {
        print "-------------------------------"
        printf "Total CPU this round:     %6.2f%%\n", sum
        print sum
    }' | tee /tmp/sample.txt | tail -n 1)

    total=$(echo "$total + $round_total" | bc)
    sleep 1
done

average=$(echo "scale=2; $total / 10" | bc)
echo
echo "======================================"
echo "Average total CPU usage: $average%"
