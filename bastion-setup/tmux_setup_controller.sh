#!/bin/sh
#
# Reference: https://gist.github.com/todgru/6224848
session="work2"

# set up tmux
tmux start-server

# create a new tmux session, 
tmux new-session -d -s $session -n test2

# Select pane 1, set dir to api, run vim
tmux selectp -t 1 
tmux send-keys "ssh -i ssh_keys/kube-controller-0 kube-controller-0@10.240.0.10" C-m 

# Split pane 1 vertically by 25%
tmux splitw -v -p 75
tmux send-keys "ssh -i ssh_keys/kube-controller-1 kube-controller-1@10.240.0.11" C-m 

# Select pane 2 
tmux selectp -t 2
# Split pane 2 vertically by 25%
tmux splitw -v -p 75

# select pane 3, set to api root
tmux selectp -t 3
tmux send-keys "ssh -i ssh_keys/kube-controller-2 kube-controller-2@10.240.0.12" C-m 

# Select pane 1
tmux selectp -t 1

# create a new window called scratch
tmux new-window -t $session:1 -n scratch

# return to main vim window
tmux select-window -t $session:0

# Finished setup, attach to the tmux session!
tmux attach-session -t $session