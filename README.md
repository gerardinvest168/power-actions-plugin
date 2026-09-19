# Power Actions — Quick Start

## What it does

A bar widget (󰖲 power icon) that gives you quick access to four power actions — **Shutdown**, **Restart**, **Sleep**, and **Log off** — each with optional countdown timers. Timers survive shell restarts.

## Install

### Automated (one command)

```bash
omarchy plugin add https://github.com/gerardinvest168/power-actions-plugin --enable
```

Replace the URL with your actual repo once published. Until then, use the manual route.

### Manual

```bash
# 1. Clone or copy the plugin into Omarchy's plugin dir
cp -r /home/gerygerger/Projects/power-actions ~/.config/omarchy/plugins/gerygerger.power-actions

# 2. Make the shell helper scripts executable
chmod +x ~/.config/omarchy/plugins/gerygerger.power-actions/*.sh

# 3. Rescan so Omarchy picks it up
omarchy-shell shell rescanPlugins

# 4. Enable it
omarchy plugin enable gerygerger.power-actions

# 5. Add it to the bar (append to your bar.right layout in ~/.config/omarchy/shell.json)
#    { "id": "gerygerger.power-actions" }
```

After editing `shell.json`, restart the shell:

```bash
omarchy restart shell
```

## Using it

### Bar icon

- **Left-click** the 󰖲 icon → opens the Power Actions panel.
- **Right-click** the icon → cancels any active timer.

### Panel

The panel shows four action rows — Shutdown, Restart, Sleep, Log off — each with:

- A **label** and **icon**.
- **Timer preset chips** — 1m, 15m, 30m, 1h. Click a chip to schedule that action with that countdown.
- A **"+"** button — opens a custom timer picker for that action: set any countdown from **1 to 120 minutes**, then press **Enter** or **Start**. The chip shows the running custom value (e.g. "12m") until the timer ends or is cancelled.

When a timer is running you'll see:

- A **countdown box** at the top of the panel showing the action name and remaining time in red.
- A **Cancel timer** button in the countdown box (right-clicking the bar icon also cancels).

### Immediate actions

Click the action label/icon row itself (not a timer chip) to execute that action immediately — a Yes/No confirmation dialog appears first.

### Timer persistence

Timers are stored in `~/.config/omarchy/shell.json` under `powerActions.timerAction` and `powerActions.timerSeconds`. If the shell restarts while a timer is running, it picks up where it left off.

## Timer presets

| Chip | Countdown |
|------|-----------|
| 1m   | 60 seconds |
| 15m  | 900 seconds |
| 30m  | 1800 seconds |
| 1h   | 3600 seconds |
| +    | custom — 1 to 120 minutes (inline picker) |

## How it works

- **Power actions** are executed via `omarchy system <action>` (shutdown→power-off, restart→reboot, sleep→suspend, logoff→logout), falling back to `systemctl <action>` if the omarchy command isn't available.
- **Timers** use a 1-second `Timer` element in QML counting down `timerSeconds`. When it hits zero the scheduled action fires immediately (no confirmation for timed actions).
- **State persistence** is handled by three shell scripts — `read-timer.sh`, `write-timer.sh`, `remove-timer.sh` — that read/write the `powerActions` key in `shell.json`.
- **IPC** exposes `shutdown()`, `restart()`, `sleep()`, `logoff()`, `cancelTimer()` to other plugins and CLIs via `omarchy-shell shell invoke gerygerger.power-actions <method>`.

## Troubleshooting

**Widget not showing on bar**
1. `omarchy plugin list` — confirm `gerygerger.power-actions` shows as `enabled`.
2. Check `shell.json` bar.right includes `{ "id": "gerygerger.power-actions" }`.
3. `omarchy restart shell` after any change.
4. Check `journalctl --user -t omarchy-shell` for QML errors.

**Timer not persisting across restart**
1. Confirm `write-timer.sh` and `read-timer.sh` are executable.
2. `cat ~/.config/omarchy/shell.json | python3 -m json.tool | grep -A3 powerActions` — should show `timerAction` and `timerSeconds`.
3. Check scripts run manually: `bash ~/.config/omarchy/plugins/gerygerger.power-actions/write-timer.sh 2 300` then `bash ~/.config/omarchy/plugins/gerygerger.power-actions/read-timer.sh`.

**Power action fails**
1. `omarchy system shutdown --help` — confirm the omarchy command exists.
2. Fallback uses `systemctl power-off / reboot / suspend / logout` — confirm those work from a terminal.
3. Logout requires a session manager; on Hyprland this goes through `loginctl terminate-session`.

## Files

```
~/.config/omarchy/plugins/gerygerger.power-actions/
├── manifest.json          # Plugin manifest
├── Panel.qml              # Main UI (bar button + popup panel)
├── Model.js               # Shared JS utilities
├── read-timer.sh          # Reads timer state from shell.json
├── write-timer.sh         # Writes timer state to shell.json
└── remove-timer.sh        # Clears timer state from shell.json
```

## License

Same license as the Omarchy platform. Filled with ❤️ by Gerygerger.
