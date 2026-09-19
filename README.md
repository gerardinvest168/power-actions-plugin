# Power Actions — Quick Start

A bar widget for **Shutdown**, **Restart**, **Sleep** and **Log off**, each with optional countdown
timers. Armed actions keep counting down whether or not the panel is open, and survive a shell
restart.

## Requirements

- Omarchy with the Omarchy shell (Quickshell) — this is a shell plugin, not a standalone app.
- `systemctl` / `loginctl` from systemd, plus the standard `omarchy` CLI (all present on Omarchy).
- `bash` for the helper scripts. No Python.

## Install

### Automated (one command)

```bash
omarchy plugin add https://github.com/gerardinvest168/power-actions-plugin --enable
```

The repository is private, so the automated route needs GitHub credentials already cached on the machine.

### Manual

```bash
# 1. Copy the checkout into Omarchy's plugin dir
cp -r <path-to-checkout> ~/.config/omarchy/plugins/gerygerger.power-actions

# 2. Make the shell helper scripts executable
chmod +x ~/.config/omarchy/plugins/gerygerger.power-actions/*.sh

# 3. Rescan so Omarchy picks it up
omarchy-shell shell rescanPlugins

# 4. Enable it
omarchy plugin enable gerygerger.power-actions

# 5. Add it to the bar (append to your bar.right layout in ~/.config/omarchy/shell.json)
#    { "id": "gerygerger.power-actions" }
```

Then restart the shell:

```bash
omarchy restart shell
```

> **After any change to this plugin, run `omarchy restart shell`.**
> Saving a file under `~/.config/omarchy/plugins/` makes the shell log
> `Local plugin changed, reloading: gerygerger.power-actions`, but the bar widget
> instance is **not** re-created — the live widget keeps running the old code.
> This was verified by adding a new IPC method and calling it: the running
> instance answered `Function not found.` until the shell was restarted.

### Remove

```bash
omarchy plugin disable gerygerger.power-actions
omarchy plugin remove gerygerger.power-actions
rm -rf ~/.local/state/gerygerger.power-actions      # optional: drop saved timer state
```

## Using it

### Bar icon

- **Left-click** the 󰐥 icon → opens the Power Actions panel.
- **Right-click** → cancels an armed action or timer. If nothing is armed, it opens the panel.

While something is armed the bar icon shows it without you hovering, and without the panel being
open — icon, remaining time, and the theme's urgent colour:

```
󰐥 5s        an action is 5 seconds from firing
󰜉 4m 32s     a restart is armed for 4m 32s from now
󰐥            nothing armed
```

The tooltip spells it out in words ("Restarting in 4m 32s — right-click to cancel").

### Quick actions

The four icon buttons across the top arm an action immediately. **Selecting one starts a 5 second
countdown** with a progress bar and a **Cancel** button; when it reaches zero the action runs, and
the panel closes.

Escape cancels an armed action (a second Escape closes the panel), and so does right-clicking the
bar icon. Closing the panel also cancels, so an action can never fire while its countdown is off
screen.

### Action rows

Below the quick actions, each row has:

- A **label and icon** — clicking the row arms that action with the same 5 second countdown.
- **Timer preset chips** — 1m, 15m, 30m, 1h. Click a chip to schedule that action with that countdown.
- A **"+"** button — opens a custom timer picker for that action: set any countdown from **1 to 120
  minutes**, then press **Enter** or **Start**. The chip shows the running custom value (e.g. "12m")
  until the timer ends or is cancelled.

Timer presets arm the action for later instead of counting down now, so they never ask for confirmation.

### Timers

- The armed row is highlighted and its chip stays filled **regardless of where the pointer is** — the
  armed state is not tied to hover.
- The panel shows a **countdown box** with the action name and remaining time in red, plus a
  **Cancel timer** button.

### Failures

Power actions are executed by `power-action.sh`, which reports what went wrong. If every command for
an action fails, the panel stays open and shows the reason:

```
Power action failed
Call to PowerOff failed: Interactive authentication required.
[Dismiss]
```

Failing loudly matters here: the widget used to run every command with `2>/dev/null` and close the
panel on exit, so a failed shutdown looked exactly like a successful one.

## Timer persistence

Timers are stored in `~/.local/state/gerygerger.power-actions/timer` as `action:deadline` — the
action number, and the absolute epoch second at which it fires.

- The deadline is absolute, so a shell restart reads back the **time actually left** rather than
  restarting the original duration.
- State is restored at start-up, so a timer still fires if the panel is never opened.
- If a timer came due while the shell was down it fires as soon as the shell is back. A timer that
  expired more than **90 seconds** ago (e.g. the machine was off) is dropped instead of firing a
  shutdown on login.
- This plugin never writes to `shell.json`. (Earlier versions rewrote it on every timer change and
  fell back to writing `{}` when it failed to parse, which destroyed the whole bar layout.)

## How it works

- **Power actions** run through `power-action.sh`, which tries each command for an action in order and
  reports the failure if none succeed:
  - *Shutdown*: `omarchy system shutdown`, then `systemctl poweroff`.
  - *Restart*: `omarchy system reboot`, then `systemctl reboot`.
  - *Sleep*: `systemctl suspend` — `omarchy system` has no suspend verb.
  - *Log off*: `omarchy system logout`, then `loginctl terminate-session "$XDG_SESSION_ID"`, then
    `loginctl terminate-user "$USER"`. (`terminate-session` requires a session id; the old
    fallback passed none and could not work.)
- **Countdowns** use 1-second `Timer` elements. The 5-second action countdown fires the action at
  zero; the long timer recomputes from its deadline every tick, so it self-corrects after a restart.
- **State persistence** is three shell scripts — `read-timer.sh`, `write-timer.sh`, `remove-timer.sh` —
  reading and writing only this plugin's own state file, atomically (temp file + rename).
- **IPC** exposes `shutdown()`, `restart()`, `sleep()`, `logoff()`, `cancelTimer()` and
  `readTimerState()` on the `gerygerger.power-actions` target:

  ```bash
  omarchy-shell gerygerger.power-actions cancelTimer
  omarchy-shell gerygerger.power-actions shutdown     # also uses the 5 second countdown
  ```

## Timer presets

| Chip | Countdown |
|------|-----------|
| 1m   | 60 seconds |
| 15m  | 900 seconds |
| 30m  | 1800 seconds |
| 1h   | 3600 seconds |
| +    | custom — 1 to 120 minutes (inline picker) |

## Troubleshooting

**Widget not showing on bar**
1. `omarchy plugin list` — confirm `gerygerger.power-actions` shows as `enabled`.
2. Check `shell.json` bar.right includes `{ "id": "gerygerger.power-actions" }`.
3. `omarchy restart shell` after any change.
4. Check `journalctl --user -t omarchy-shell` for QML errors.

**A change or fix isn't taking effect**
Run `omarchy restart shell`. Editing files under `~/.config/omarchy/plugins/` is logged as a reload
but does not re-create an already-instantiated bar widget.

**Timer not persisting across restart**
1. Confirm `cat ~/.local/state/gerygerger.power-actions/timer` shows `<action>:<deadline>`.
2. Check the scripts run manually:
   `bash ~/.config/omarchy/plugins/gerygerger.power-actions/write-timer.sh 2 $(( $(date +%s) + 300 ))`
   then `bash ~/.config/omarchy/plugins/gerygerger.power-actions/read-timer.sh`.
3. Remember a timer more than 90 seconds past its deadline is intentionally dropped.

**Power action fails**
The panel shows the error from the failing commands. To reproduce it in a terminal, run the action
script directly — it prints the same message and exits non-zero:

```bash
bash ~/.config/omarchy/plugins/gerygerger.power-actions/power-action.sh sleep
bash ~/.config/omarchy/plugins/gerygerger.power-actions/power-action.sh shutdown
```

If the message is a polkit error, the action needs interactive authentication in that context.
Logout requires a session manager; on Hyprland this goes through `loginctl`.

## Files

```
~/.config/omarchy/plugins/gerygerger.power-actions/
├── manifest.json          # Plugin manifest
├── Panel.qml              # Main UI (bar button + popup panel)
├── power-action.sh        # Runs a power action, reports failures
├── read-timer.sh          # Reads timer state
├── write-timer.sh         # Writes timer state (atomic)
└── remove-timer.sh        # Clears timer state
```

## License

Same license as the Omarchy platform. Filled with ❤️ by Gerygerger.
