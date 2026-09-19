#!/bin/bash
# read-timer.sh — Print the persisted timer as "<action>:<deadline>".
#
#   action   1=shutdown 2=restart 3=sleep 4=logoff, 0 = nothing armed
#   deadline epoch seconds at which the action fires
#
# Prints "0:0" when no timer is armed. Reads only this plugin's own state file,
# so it can never damage shell.json.

set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gerygerger.power-actions"
STATE_FILE="$STATE_DIR/timer"

if [[ -r "$STATE_FILE" ]]; then
  IFS=: read -r action deadline < "$STATE_FILE" || true
  if [[ "${action:-0}" =~ ^[1-4]$ && "${deadline:-0}" =~ ^[0-9]+$ ]]; then
    printf '%s:%s\n' "$action" "$deadline"
    exit 0
  fi
fi

printf '0:0\n'
