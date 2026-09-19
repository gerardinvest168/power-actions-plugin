#!/bin/bash
# write-timer.sh — Persist an armed timer as "<action>:<deadline>".
#
# Usage: write-timer.sh <action 1-4> <deadline epoch seconds>
#
# Stores an absolute deadline rather than a countdown, so a shell restart reads
# back the real time left instead of restarting the original duration.
#
# Writes only this plugin's own state file (atomic temp + rename). The previous
# version rewrote ~/.config/omarchy/shell.json and fell back to writing "{}" when
# that file failed to parse, which destroyed the whole bar layout.

set -eu

action="${1:-0}"
deadline="${2:-0}"

if [[ ! "$action" =~ ^[1-4]$ ]]; then
  echo "write-timer.sh: action must be 1-4, got '$action'" >&2
  exit 2
fi

if [[ ! "$deadline" =~ ^[0-9]+$ ]]; then
  echo "write-timer.sh: deadline must be epoch seconds, got '$deadline'" >&2
  exit 2
fi

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/gerygerger.power-actions"
mkdir -p "$state_dir"

tmp="$(mktemp "$state_dir/.timer.XXXXXX")"
printf '%s:%s\n' "$action" "$deadline" > "$tmp"
mv -f "$tmp" "$state_dir/timer"
