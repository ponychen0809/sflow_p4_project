#!/bin/bash

IFACE="enp1s0"        # 請改成你要監控的網卡，例如 eth0, ens33, etc.
DURATION=16         # 監控秒數，可自行調整

# 檢查網卡是否存在
if [ ! -f "/sys/class/net/$IFACE/statistics/tx_packets" ]; then
    echo "找不到網卡 $IFACE"
    exit 1
fi

echo "開始監控 $IFACE，持續 $DURATION 秒..."
START=$(cat /sys/class/net/$IFACE/statistics/tx_packets)
PREV=$START

# 每秒監控一次
for ((i=1; i<=DURATION; i++)); do
    sleep 1
    CUR=$(cat /sys/class/net/$IFACE/statistics/tx_packets)
    DELTA=$((CUR - PREV))
    echo "第 $i 秒：這秒送出 $DELTA 個封包（累積 $((CUR - START))）"
    PREV=$CUR
done

END=$(cat /sys/class/net/$IFACE/statistics/tx_packets)
TOTAL=$((END - START))

echo "=========="
echo "總共送出 $TOTAL 個封包"
echo "=========="
