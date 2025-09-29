#!/bin/bash

# 檢查是否有輸入參數
if [ -z "$1" ]; then
    echo "用法: $0 <頻寬，例如 400M>"
    exit 1
fi
echo "iperf -c 10.10.3.2 -u -b "$1" -l 512 -t 30"
# 執行 iperf
iperf -c 10.10.3.2 -u -b "$1" -l 512 -t 30