import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "gerygerger.power-actions"
  ipcTarget: "gerygerger.power-actions"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------- Actions ----------
  // 1=shutdown, 2=restart, 3=sleep, 4=logoff, 0=nothing armed.
  readonly property var actionIcons: ["", "󰐥", "󰜉", "󰤄", "󰍃"]
  readonly property var actionNames: ["", "Shutdown", "Restart", "Sleep", "Logoff"]
  readonly property var actionVerbs: ["", "Shutting down", "Restarting", "Sleeping", "Logging off"]

  // ---------- Timer state ----------
  // A timer holds an absolute deadline, not a countdown, so a shell restart
  // reads back the time actually left instead of restarting the full duration.
  property int timerAction: 0
  property real timerDeadline: 0
  property int timerSeconds: 0
  readonly property bool timerActive: timerAction > 0
  readonly property string timerLabel: actionNames[timerAction]

  // A timer that came due while the shell was down is only honoured when it
  // expired recently. An older one is dropped rather than firing a shutdown on
  // start-up hours later.
  readonly property int missedTimerGrace: 90

  // ---------- Armed action (5 second countdown) ----------
  // Confirming a destructive action is a visible, cancelable countdown rather
  // than a modal Yes/No dialog: it cannot leave a stale dialog armed behind a
  // closed panel, and it shares the Escape / right-click cancel path.
  readonly property int countdownSeconds: 5
  property int pendingAction: 0
  property int pendingSeconds: 0
  readonly property bool pendingActive: pendingAction > 0
  property string actionError: ""

  // ---------- Bar indicator ----------
  // Visible whether or not the panel is open, and whether or not the pointer is
  // over the widget, so an armed action is never silent.
  readonly property int armedAction: pendingActive ? pendingAction : timerAction
  readonly property bool armed: armedAction > 0
  readonly property string barIcon: armed ? actionIcons[armedAction] : "󰐥"
  readonly property string barTime: pendingActive ? Math.max(pendingSeconds, 0) + "s"
    : timerActive ? formatTime(timerSeconds) : ""
  readonly property string barText: barTime === "" ? barIcon : barIcon + " " + barTime
  readonly property string barTooltip: !armed ? "Power Actions"
    : pendingActive ? actionVerbs[pendingAction] + " in " + pendingSeconds + "s — right-click to cancel"
    : timerLabel + " in " + formatTime(timerSeconds) + " — right-click to cancel"

  // ---------- Helpers ----------
  function nowSeconds() {
    return Math.floor(Date.now() / 1000)
  }

  function formatTime(secs) {
    secs = parseInt(secs, 10)
    if (isNaN(secs) || secs <= 0) return "now"
    var h = Math.floor(secs / 3600)
    var m = Math.floor((secs % 3600) / 60)
    var s = secs % 60
    if (h > 0) return h + "h " + m + "m"
    if (m > 0) return m + "m " + s + "s"
    return s + "s"
  }

  function actionName(action) {
    switch (action) {
      case 1: return "shutdown"
      case 2: return "restart"
      case 3: return "sleep"
      case 4: return "logoff"
    }
    return ""
  }

  // ---------- Power actions ----------
  // Every entry point — bar panel, right-click, IPC — goes through the countdown.
  function shutdown() { requestAction(1) }
  function restart() { requestAction(2) }
  function sleep() { requestAction(3) }
  function logoff() { requestAction(4) }

  function requestAction(action) {
    if (action < 1 || action > 4) return
    actionError = ""
    pendingAction = action
    pendingSeconds = countdownSeconds
  }

  function clearPending() {
    pendingAction = 0
    pendingSeconds = 0
  }

  function cancelTimer() {
    clearPending()
    if (!timerActive) return
    timerAction = 0
    timerSeconds = 0
    timerDeadline = 0
    removeTimerState()
  }

  function executeAction(action) {
    var name = actionName(action)
    if (name === "") return
    actionError = ""
    actionProc.command = ["bash", powerActionScript, name]
    actionProc.running = true
  }

  // ---------- Armed action countdown ----------
  Timer {
    id: pendingTimer
    interval: 1000
    running: root.pendingActive
    repeat: true
    onTriggered: {
      if (root.pendingSeconds > 1) {
        root.pendingSeconds--
      } else {
        var action = root.pendingAction
        root.clearPending()
        root.executeAction(action)
      }
    }
  }

  // ---------- Timer countdown ----------
  // Recomputes the remaining time from the deadline rather than decrementing a
  // counter, so it stays correct across shell restarts and clock drift.
  Timer {
    id: countdownTimer
    interval: 1000
    running: root.timerActive
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var remaining = Math.round(root.timerDeadline - root.nowSeconds())
      if (remaining <= 0) {
        var action = root.timerAction
        root.cancelTimer()
        root.executeAction(action)
      } else {
        root.timerSeconds = remaining
      }
    }
  }

  // ---------- Timer presets ----------
  readonly property var timerPresets: [
    { label: "1m",  seconds: 60   },
    { label: "15m", seconds: 900  },
    { label: "30m", seconds: 1800 },
    { label: "1h",  seconds: 3600 }
  ]

  function setTimerPreset(action, presetIndex) {
    startTimer(action, timerPresets[presetIndex].seconds)
  }

  function startTimer(action, seconds) {
    if (action < 1 || action > 4 || seconds <= 0) return
    actionError = ""
    clearPending()
    // Deadline first, action last: `timerAction` starts the countdown Timer,
    // which would otherwise trigger once against an unset deadline.
    timerDeadline = nowSeconds() + seconds
    timerSeconds = seconds
    timerAction = action
    writeTimerState()
  }

  function isPresetSeconds(secs) {
    for (var i = 0; i < timerPresets.length; i++) {
      if (timerPresets[i].seconds === secs) return true
    }
    return false
  }

  // ---------- Custom timer ----------
  property int customOpen: 0    // actionType with an open custom input, 0 = none
  property int customMinutes: 5
  // True while the inline minutes field holds focus, so the panel key catcher
  // routes Enter / Escape / arrows to the field instead of swallowing them.
  property bool editorFocused: false

  // ---------- Persistent timer state ----------
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/gerygerger.power-actions"
  readonly property string timerReadScript: pluginDir + "/read-timer.sh"
  readonly property string timerWriteScript: pluginDir + "/write-timer.sh"
  readonly property string timerRemoveScript: pluginDir + "/remove-timer.sh"
  readonly property string powerActionScript: pluginDir + "/power-action.sh"

  function writeTimerState() {
    timerWriteProc.command = ["bash", timerWriteScript, String(timerAction), String(Math.round(timerDeadline))]
    timerWriteProc.running = true
  }

  function readTimerState() {
    if (timerReadProc.running) return
    timerReadProc.running = true
  }

  function removeTimerState() {
    if (removeTimerProc.running) return
    removeTimerProc.running = true
  }

  function applyTimerState(action, deadline) {
    if (action < 1 || action > 4 || deadline <= 0) return
    var now = nowSeconds()
    if (deadline <= now) {
      if (now - deadline <= missedTimerGrace) executeAction(action)
      else removeTimerState()
      return
    }
    timerDeadline = deadline
    timerSeconds = Math.round(deadline - now)
    timerAction = action
  }

  // Restore on start-up: a timer set before a shell restart has to keep running
  // (and still fire) without the panel ever being opened.
  Component.onCompleted: readTimerState()

  onOpenedChanged: {
    if (opened) readTimerState()
    else clearPending()
  }

  // ---------- IPC ----------
  IpcHandler {
    target: "gerygerger.power-actions"
    function shutdown() { root.shutdown() }
    function restart() { root.restart() }
    function sleep() { root.sleep() }
    function logoff() { root.logoff() }
    function cancelTimer() { root.cancelTimer() }
    function readTimerState() { root.readTimerState() }
  }

  // ---------- Processes ----------
  Process { id: timerWriteProc
    command: ["true"]
  }

  Process { id: timerReadProc
    command: ["bash", root.timerReadScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(":")
        if (parts.length < 2) return
        var action = parseInt(parts[0], 10)
        var deadline = parseInt(parts[1], 10)
        if (isNaN(action) || isNaN(deadline)) return
        root.applyTimerState(action, deadline)
      }
    }
  }

  Process { id: removeTimerProc
    command: ["bash", root.timerRemoveScript]
  }

  // Failures are reported instead of hidden: the old `2>/dev/null` meant a
  // failed shutdown closed the panel looking exactly like a successful one.
  Process { id: actionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.actionError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.close()
        return
      }
      if (root.actionError === "") root.actionError = "Power action failed (exit " + exitCode + ")"
    }
  }

  // ---------- Bar button ----------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    slotSize: Style.bar.iconSlot * (root.armed && !button.vertical ? 3 : 1)
    active: root.armed
    tooltipText: root.barTooltip
    onPressed: function(b) {
      if (b === Qt.RightButton && root.armed) root.cancelTimer()
      else root.open()
    }
  }

  // ---------- Panel content ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editorFocused
      // Escape backs out of an armed action first, and only then closes the panel.
      onCloseRequested: {
        if (root.pendingActive) root.clearPending()
        else root.close()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.panelGap

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroTextColumn.implicitHeight)

          Text {
            id: heroIcon
            text: root.armed ? root.barIcon : "󰐥"
            color: root.armed ? "#ff6b6b" : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroTextColumn
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: heroBadge.left
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs

            Text {
              text: "Power Actions"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: "SYSTEM CONTROL"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroBadge
            visible: root.armed
            text: root.pendingActive ? "CONFIRM" : "ARMED"
            color: "#ff6b6b"
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Quick actions ----------
        Row {
          id: quickRow
          width: parent.width
          spacing: Style.space(6)
          readonly property real cellWidth: (width - spacing * 3) / 4

          Button {
            iconText: "󰐥"
            iconSize: Style.font.iconLarge
            tooltipText: "Shut down"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: root.timerAction === 1 || root.pendingAction === 1
            width: quickRow.cellWidth
            onClicked: root.requestAction(1)
          }

          Button {
            iconText: "󰜉"
            iconSize: Style.font.iconLarge
            tooltipText: "Restart"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: root.timerAction === 2 || root.pendingAction === 2
            width: quickRow.cellWidth
            onClicked: root.requestAction(2)
          }

          Button {
            iconText: "󰤄"
            iconSize: Style.font.iconLarge
            tooltipText: "Sleep"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: root.timerAction === 3 || root.pendingAction === 3
            width: quickRow.cellWidth
            onClicked: root.requestAction(3)
          }

          Button {
            iconText: "󰍃"
            iconSize: Style.font.iconLarge
            tooltipText: "Log off"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: root.timerAction === 4 || root.pendingAction === 4
            width: quickRow.cellWidth
            onClicked: root.requestAction(4)
          }
        }

        // ---------- Armed action countdown ----------
        Rectangle {
          id: pendingCard
          visible: root.pendingActive
          width: parent.width
          implicitHeight: pendingColumn.implicitHeight + Style.spacing.popupPadding * 2
          radius: Style.cornerRadius
          color: Qt.rgba(1, 0.42, 0.42, 0.12)
          border.color: Qt.rgba(1, 0.42, 0.42, 0.35)
          border.width: 1

          Column {
            id: pendingColumn
            anchors.centerIn: parent
            width: parent.width - Style.spacing.popupPadding * 2
            spacing: Style.spacing.sm

            Text {
              text: root.actionVerbs[root.pendingAction] + " in " + root.pendingSeconds + "s"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.horizontalCenter: parent.horizontalCenter
            }

            Rectangle {
              width: parent.width
              height: Math.max(3, Style.space(4))
              radius: height / 2
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.16)

              Rectangle {
                height: parent.height
                radius: parent.radius
                color: "#ff6b6b"
                width: parent.width * Math.max(0, Math.min(1, root.pendingSeconds / root.countdownSeconds))
                Behavior on width { NumberAnimation { duration: 250 } }
              }
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Cancel"
              fontSize: Style.font.caption
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.clearPending()
            }
          }
        }

        // ---------- Failure report ----------
        Rectangle {
          id: errorCard
          visible: root.actionError !== ""
          width: parent.width
          implicitHeight: errorColumn.implicitHeight + Style.spacing.popupPadding * 2
          radius: Style.cornerRadius
          color: Qt.rgba(1, 0.42, 0.42, 0.12)
          border.color: Qt.rgba(1, 0.42, 0.42, 0.35)
          border.width: 1

          Column {
            id: errorColumn
            anchors.centerIn: parent
            width: parent.width - Style.spacing.popupPadding * 2
            spacing: Style.spacing.sm

            Text {
              text: "Power action failed"
              color: "#ff6b6b"
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.actionError
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.75)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Button {
              text: "Dismiss"
              fontSize: Style.font.caption
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.actionError = ""
            }
          }
        }

        // ---------- Countdown card ----------
        Rectangle {
          id: timerCard
          visible: root.timerActive
          width: parent.width
          implicitHeight: timerCardColumn.implicitHeight + Style.spacing.popupPadding * 2
          radius: Style.cornerRadius
          color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.09)
          border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14)
          border.width: 1

          Column {
            id: timerCardColumn
            anchors.centerIn: parent
            spacing: Style.spacing.sm

            Text {
              text: root.timerLabel + " in"
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.65)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.0
              anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
              text: root.formatTime(root.timerSeconds)
              color: "#ff6b6b"
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              anchors.horizontalCenter: parent.horizontalCenter
            }

            Button {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Cancel timer"
              fontSize: Style.font.caption
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.cancelTimer()
            }
          }
        }

        // ---------- Actions ----------
        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: "ACTIONS"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.spacing.lg

          ActionRow { label: "Shut down"; icon: "󰐥"; actionType: 1; timerPresets: root.timerPresets }
          ActionRow { label: "Restart"; icon: "󰜉"; actionType: 2; timerPresets: root.timerPresets }
          ActionRow { label: "Sleep"; icon: "󰤄"; actionType: 3; timerPresets: root.timerPresets }
          ActionRow { label: "Log off"; icon: "󰍃"; actionType: 4; timerPresets: root.timerPresets }
        }
      }
    }
  }

  // ---------- Action row component ----------
  component ActionRow: Item {
    id: row
    required property string label
    required property string icon
    required property int actionType
    required property var timerPresets

    readonly property bool isArmed: root.timerAction === actionType
    readonly property bool isPending: root.pendingAction === actionType

    width: parent.width
    implicitHeight: labelHit.implicitHeight + Style.spacing.xxs + chipRow.implicitHeight
      + (root.customOpen === actionType ? customRow.implicitHeight + Style.spacing.sm : 0)

    // Clicking the label arms the action: 5 second countdown, cancelable.
    MouseArea {
      id: labelHit
      width: parent.width
      implicitHeight: labelStack.implicitHeight
      onClicked: root.requestAction(row.actionType)

      Row {
        id: labelStack
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          id: labelIcon
          text: row.icon
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.icon
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          text: row.label
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.isArmed || row.isPending
          elide: Text.ElideRight
          width: parent.width - labelIcon.implicitWidth - parent.spacing
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Flow {
      id: chipRow
      anchors.top: labelHit.bottom
      anchors.topMargin: Style.spacing.xxs
      width: parent.width
      spacing: Style.spacing.sm

      Repeater {
        model: timerPresets
        Button {
          required property var modelData
          required property int index
          text: modelData.label
          fontSize: Style.font.caption
          foreground: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.75)
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          bordered: true
          active: root.timerAction === row.actionType && root.timerSeconds === modelData.seconds
          onClicked: {
            if (root.customOpen === row.actionType) root.customOpen = 0
            root.setTimerPreset(row.actionType, index)
          }
        }
      }

      Button {
        text: root.timerAction === row.actionType && !root.isPresetSeconds(root.timerSeconds)
          ? String(Math.round(root.timerSeconds / 60)) + "m" : "+"
        fontSize: Style.font.caption
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true
        active: root.customOpen === row.actionType
          || (root.timerAction === row.actionType && !root.isPresetSeconds(root.timerSeconds))
        onClicked: root.customOpen = (root.customOpen === row.actionType) ? 0 : row.actionType
      }
    }

    Row {
      id: customRow
      visible: root.customOpen === row.actionType
      anchors.top: chipRow.bottom
      anchors.topMargin: Style.spacing.sm
      spacing: Style.spacing.sm
      onVisibleChanged: if (visible) customMinutesField.forceActiveFocus()

      function parseCustomMinutes() {
        var v = parseInt(customMinutesField.text, 10)
        if (isNaN(v)) return
        if (v < 1) v = 1
        if (v > 120) v = 120
        root.customMinutes = v
        customMinutesField.text = String(v)
      }

      function startCustomTimer() {
        customRow.parseCustomMinutes()
        root.startTimer(row.actionType, root.customMinutes * 60)
        root.customOpen = 0
      }

      TextField {
        id: customMinutesField
        width: Style.space(72)
        text: String(root.customMinutes)
        placeholderText: "min"
        validator: IntValidator { bottom: 1; top: 120 }
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        selectByMouse: true
        foreground: root.bar.foreground
        onActiveFocusChanged: root.editorFocused = activeFocus
        onAccepted: customRow.startCustomTimer()
        onEditingFinished: customRow.parseCustomMinutes()
      }

      Text {
        text: "min"
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.55)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: customMinutesField.verticalCenter
      }

      Button {
        text: "Start"
        fontSize: Style.font.caption
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true
        onClicked: customRow.startCustomTimer()
      }
    }
  }
}
