#!/bin/bash
# write-timer.sh — Persist timer state to shell.json
# Args: action (1-4) seconds

ACTION="${1:-0}"
SECONDS="${2:-0}"

SHELL_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"

python3 -c "
import sys, json, os
path = '$SHELL_JSON'
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        pass

data.setdefault('powerActions', {})
data['powerActions']['timerAction'] = int('$ACTION') if '$ACTION' and '$ACTION' != '0' else 0
data['powerActions']['timerSeconds'] = int('$SECONDS') if '$SECONDS' and '$SECONDS' != '0' else 0

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
