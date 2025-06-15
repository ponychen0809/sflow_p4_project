#!/bin/bash

total=0

for i in {1..10}; do
    echo "Sampling #$i..."
    sum=$(top -b -n 1 | awk '
        BEGIN { s = 0; }
        /^ *[0-9]+ / {
            cpu = $9;
            if (cpu + 0 > 0) s += cpu;
        }
        END { print s; }
    ')
    echo "  Total CPU usage (active processes): $sum%"
    total=$(echo "$total + $sum" | bc)
    sleep 1
done

avg=$(echo "scale=2; $total / 10" | bc)
echo "========================================="
echo "Average total CPU usage over 10 seconds: $avg%"
