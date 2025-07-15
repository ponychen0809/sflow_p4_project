#!/bin/bash

SESSION="iperf_test"
IPERF_CMD="iperf -c 10.10.3.3 -u -b 2G -l 512 -t 30"

# 建立 tmux session（不附帶 shell）
tmux new-session -d -s $SESSION

# 執行第一個 iperf 指令在主 pane
tmux send-keys -t $SESSION "$IPERF_CMD" C-m

# 接著建立剩下四個 pane 並執行指令
for i in {1..4}
do
    tmux split-window -t $SESSION
    tmux select-layout -t $SESSION tiled
    tmux send-keys -t $SESSION "$IPERF_CMD" C-m
done

# 最後附著到這個 tmux session
tmux attach-session -t $SESSION
