#!/bin/bash
# remove-timer.sh — Clear the persisted timer.
#
# Deletes this plugin's own state file only; nothing else is touched.

set -eu

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gerygerger.power-actions"

rm -f "$STATE_DIR/timer"
