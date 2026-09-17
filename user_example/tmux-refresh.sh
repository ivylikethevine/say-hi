#!/bin/bash

tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' | xargs -I {} tmux send-keys -t {} 'source ~/.bashrc' Enter
