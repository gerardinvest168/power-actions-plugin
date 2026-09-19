#!/bin/bash
# power-action.sh — Run a power action and report failure.
#
# Usage: power-action.sh <shutdown|restart|sleep|logoff>
#
# `omarchy system` only has lock, logout, reboot, shutdown, stats and wake —
# there is no suspend and no power-off verb — and systemctl's verb is `poweroff`,
# not `power-off`. Each action therefore tries its own commands in order.
#
# Exits 0 as soon as one succeeds. Otherwise it writes what went wrong to stderr
# and exits 1, so the panel can show the reason instead of hiding it behind
# 2>/dev/null and closing as if the action had worked.

action="${1:-}"
last=""

try() {
  local output
  if output=$("$@" 2>&1); then
    exit 0
  fi
  last="${output:-$*: command failed}"
}

case "$action" in
  shutdown)
    try omarchy system shutdown
    try systemctl poweroff
    ;;
  restart)
    try omarchy system reboot
    try systemctl reboot
    ;;
  sleep)
    try systemctl suspend
    ;;
  logoff)
    try omarchy system logout
    if [[ -n "${XDG_SESSION_ID:-}" ]]; then
      try loginctl terminate-session "$XDG_SESSION_ID"
    fi
    try loginctl terminate-user "$USER"
    ;;
  *)
    echo "power-action.sh: unknown action '${action}'" >&2
    exit 2
    ;;
esac

echo "${last}" >&2
exit 1
