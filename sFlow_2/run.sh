#!/bin/bash

# 檢查 tmux 是否安裝
if ! command -v tmux &> /dev/null; then
    echo "tmux 未安裝，請先安裝 tmux"
    exit 1
fi

# 開新 tmux session
SESSION_NAME="make_session"
tmux new-session -d -s $SESSION_NAME

# 第 1 個終端機執行 make bfrt
tmux send-keys -t $SESSION_NAME "make bfrt" C-m

# 新開一個 window 執行 make -B test
tmux new-window -t $SESSION_NAME
tmux send-keys -t $SESSION_NAME:1 "make -B test" C-m

# 附加到 session
tmux attach -t $SESSION_NAME
