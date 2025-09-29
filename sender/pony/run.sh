#!/bin/bash

# 建立新的 tmux session
tmux new-session -d -s mysession 'sudo ./udp_sender enp1s0 pony 0 10.10.3.2 11111 32 20; bash'

# 垂直分割視窗，跑第二個程式
tmux split-window -v 'sudo ./udp_sender enp1s0 pony 0 10.10.3.2 22222 32 20; bash'

# 再水平分割下面的區域，跑第三個
tmux split-window -h 'sudo ./udp_sender enp1s0 pony 0 10.10.3.2 33333 32 20; bash'

# 調整畫面配置
tmux select-layout tiled

# 進入 tmux session
tmux attach-session -t mysession
