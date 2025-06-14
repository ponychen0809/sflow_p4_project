#!/bin/bash

# The file containing total_packets and uptime
FILE="statistics.txt"

if [ ! -f "$FILE" ]; then
    echo "File $FILE does not exist."
    exit 1
fi

PREV_REAL_TOTAL_PACKETS=0
PREV_ESTIMATED_TOTAL_PACKETS=0
PREV_UPTIME=0
while [ -z "$PREV_REAL_TOTAL_PACKETS" ] || \
    [ -z "$PREV_ESTIMATED_TOTAL_PACKETS" ] || \
    [ -z "$PREV_UPTIME" ] || \
    ! echo "$PREV_REAL_TOTAL_PACKETS" | grep -qE '^[0-9]+$' || \
    ! echo "$PREV_ESTIMATED_TOTAL_PACKETS" | grep -qE '^[0-9]+$' || \
    ! echo "$PREV_UPTIME" | grep -qE '^[0-9]+$'; do
    readarray -t LINES < "$FILE"
    PREV_REAL_TOTAL_PACKETS="${LINES[0]}"
    PREV_ESTIMATED_TOTAL_PACKETS="${LINES[1]}"
    PREV_UPTIME="${LINES[2]}"
done

TOTAL_SY_CPU=0
TOTAL_BF_SWITCH_CPU=0
TOTAL_PYTHON3_CPU=0
TOTAL_REAL_PACKET_ARRIVAL_RATE=0
TOTAL_ESTIMATED_PACKET_ARRIVAL_RATE=0
i=1
while [ $i -le 10 ]; do
    readarray -t LINES < "$FILE"
    CURRENT_REAL_TOTAL_PACKETS="${LINES[0]}"
    CURRENT_ESTIMATED_TOTAL_PACKETS="${LINES[1]}"
    CURRENT_UPTIME="${LINES[2]}"

    if [ -z "$CURRENT_REAL_TOTAL_PACKETS" ] || \
        [ -z "$CURRENT_ESTIMATED_TOTAL_PACKETS" ] || \
        [ -z "$CURRENT_UPTIME" ] || \
        ! echo "$CURRENT_REAL_TOTAL_PACKETS" | grep -qE '^[0-9]+$' || \
        ! echo "$CURRENT_ESTIMATED_TOTAL_PACKETS" | grep -qE '^[0-9]+$' || \
        ! echo "$CURRENT_UPTIME" | grep -qE '^[0-9]+$'; then
        sleep 1
        continue
    fi

    # Packet arrival rate
    REAL_PACKETS_DIFF=$((CURRENT_REAL_TOTAL_PACKETS - PREV_REAL_TOTAL_PACKETS))
    ESTIMATED_PACKETS_DIFF=$((CURRENT_ESTIMATED_TOTAL_PACKETS - PREV_ESTIMATED_TOTAL_PACKETS))
    TIME_DIFF=$((CURRENT_UPTIME - PREV_UPTIME))

    if [ "$TIME_DIFF" -gt 0 ]; then
        REAL_PACKET_ARRIVAL_RATE=$(echo "scale=2; $REAL_PACKETS_DIFF / ($TIME_DIFF / 1000)" | bc)
        ESTIMATED_PACKET_ARRIVAL_RATE=$(echo "scale=2; $ESTIMATED_PACKETS_DIFF / ($TIME_DIFF / 1000)" | bc)
        TOTAL_REAL_PACKET_ARRIVAL_RATE=$(echo "$TOTAL_REAL_PACKET_ARRIVAL_RATE + $REAL_PACKET_ARRIVAL_RATE" | bc)
        TOTAL_ESTIMATED_PACKET_ARRIVAL_RATE=$(echo "$TOTAL_ESTIMATED_PACKET_ARRIVAL_RATE + $ESTIMATED_PACKET_ARRIVAL_RATE" | bc)
    else
        ARRIVAL_RATE=0
    fi

    PREV_REAL_TOTAL_PACKETS=$CURRENT_REAL_TOTAL_PACKETS
    PREV_ESTIMATED_TOTAL_PACKETS=$CURRENT_ESTIMATED_TOTAL_PACKETS
    PREV_UPTIME=$CURRENT_UPTIME

    # CPU Usage
    TOP_OUTPUT=$(top -bn 1)
    
    SY_CPU_USAGE=$(echo "$TOP_OUTPUT" | awk '/%Cpu\(s\):/ {print $4}' | sed 's/[^0-9.]//g')
    BF_SWITCH_CPU_USAGE=$(echo "$TOP_OUTPUT" | awk '$12 == "bf_switchd" {print $9}')
    PYTHON3_CPU_USAGE=$(echo "$TOP_OUTPUT" | awk '$12 == "python3" {print $9}' | head -n 1)
    CPU_USAGE=$(echo "$SY_CPU_USAGE + $BF_SWITCH_CPU_USAGE + $PYTHON3_CPU_USAGE" | bc)
    
    TOTAL_SY_CPU=$(echo "$TOTAL_SY_CPU + $SY_CPU_USAGE" | bc)
    TOTAL_BF_SWITCH_CPU=$(echo "$TOTAL_BF_SWITCH_CPU + $BF_SWITCH_CPU_USAGE" | bc)
    TOTAL_PYTHON3_CPU=$(echo "$TOTAL_PYTHON3_CPU + $PYTHON3_CPU_USAGE" | bc)
    
    i=$(($i+1))
    sleep 1
done

AVG_CPU_USAGE_SYS=$(echo "scale=2; $TOTAL_SY_CPU / 10" | bc)
AVG_CPU_USAGE_BFSWITCH=$(echo "scale=2; $TOTAL_BF_SWITCH_CPU / 10" | bc)
AVG_CPU_USAGE_PYTHON3=$(echo "scale=2; $TOTAL_PYTHON3_CPU / 10" | bc)
AVG_CPU_USAGE=$(echo "scale=2; $AVG_CPU_USAGE_SYS + $AVG_CPU_USAGE_BFSWITCH + $AVG_CPU_USAGE_PYTHON3" | bc)
AVG_REAL_PACKET_ARRIVAL_RATE=$(echo "scale=2; $TOTAL_REAL_PACKET_ARRIVAL_RATE / 10" | bc)
AVG_ESTIMATED_PACKET_ARRIVAL_RATE=$(echo "scale=2; $TOTAL_ESTIMATED_PACKET_ARRIVAL_RATE / 10" | bc)

echo "Average system CPU usage: $AVG_CPU_USAGE_SYS%"
echo "Average switch CPU usage: $AVG_CPU_USAGE_BFSWITCH%"
echo "Average controller CPU usage: $AVG_CPU_USAGE_PYTHON3%"
echo "Average total CPU usage: $AVG_CPU_USAGE%"
echo "Average real packet arrival rate: $AVG_REAL_PACKET_ARRIVAL_RATE packets/sec"
echo "Average estimated packet arrival rate: $AVG_ESTIMATED_PACKET_ARRIVAL_RATE packets/sec"
echo "$AVG_REAL_PACKET_ARRIVAL_RATE $AVG_ESTIMATED_PACKET_ARRIVAL_RATE $AVG_CPU_USAGE_SYS $AVG_CPU_USAGE_BFSWITCH $AVG_CPU_USAGE_PYTHON3 $AVG_CPU_USAGE" >> results.txt
