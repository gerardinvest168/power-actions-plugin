#!/bin/bash
# read-timer.sh — Read persistent timer state from shell.json
# Output format: "action:seconds" or "0:0" if no timer

SHELL_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"

if [[ ! -f "$SHELL_JSON" ]]; then
  echo "0:0"
  exit 0
fi

# Extract timer action and seconds using python (lightweight JSON parse)
python3 -c "
import sys, json
try:
    with open('$SHELL_JSON') as f:
        d = json.load(f)
    ta = d.get('powerActions', {}).get('timerAction', 0)
    ts = d.get('powerActions', {}).get('timerSeconds', 0)
    print(f'{ta}:{ts}')
except Exception:
    print('0:0')
" 2>/dev/null
