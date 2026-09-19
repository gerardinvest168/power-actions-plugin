#!/bin/bash
# remove-timer.sh — Clear timer state from shell.json

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

if 'powerActions' in data:
    data['powerActions']['timerAction'] = 0
    data['powerActions']['timerSeconds'] = 0

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null
