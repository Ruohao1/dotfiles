#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <session-name> <root-directory>"
    exit 1
fi
SESSION="$1"
ROOT="$2"

tmux has-session -t "$SESSION" 2>/dev/null && tmux switch-client -t "$SESSION:main" && exit 0

tmux new-session -d -s "$SESSION" -c "$ROOT"

# Window 1: editor
tmux rename-window -t "$SESSION:1" "main"
tmux send-keys -t "$SESSION:main" "nvim" Enter

# Window 2: shell
tmux new-window -t "$SESSION" -n "shell" -c "$ROOT"

# Window 3: codex
tmux new-window -t "$SESSION" -n "codex" -c "$ROOT"
tmux send-keys -t "$SESSION:codex" "codex" Enter

# Attach to session
tmux switch-client -t "$SESSION:main"
