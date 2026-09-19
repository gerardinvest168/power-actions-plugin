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

  // ---------- Timer state ----------
  property int timerAction: 0          // 0=none, 1=shutdown, 2=restart, 3=sleep, 4=logoff
  property int timerSeconds: 0
  readonly property string timerLabel: timerLabels[timerAction]
  readonly property var timerLabels: ["—", "Shutdown", "Restart", "Sleep", "Logoff"]
  readonly property bool timerActive: timerAction > 0

  // ---------- Countdown ----------
  Timer {
    id: countdownTimer
    interval: 1000
    running: root.timerActive
    repeat: true
    triggeredOnStart: false
    onTriggered: {
      if (root.timerSeconds > 1) {
        root.timerSeconds--
      } else {
        root.executeTimerAction()
      }
    }
  }

  function startTimer(action, seconds) {
    root.timerAction = action
    root.timerSeconds = seconds
    root.writeTimerState()
  }

  function cancelTimer() {
    root.timerAction = 0
    root.timerSeconds = 0
    root.removeTimerState()
  }

  function executeTimerAction() {
    var action = root.timerAction
    root.cancelTimer()
    switch (action) {
      case 1: root.shutdown(true); break
      case 2: root.restart(true); break
      case 3: root.sleep(true); break
      case 4: root.logoff(true); break
    }
  }

  function formatTime(secs) {
    secs = parseInt(secs, 10)
    if (secs <= 0) return "now"
    var h = Math.floor(secs / 3600)
    var m = Math.floor((secs % 3600) / 60)
    var s = secs % 60
    if (h > 0) return h + "h " + m + "m"
    if (m > 0) return m + "m " + s + "s"
    return s + "s"
  }

  function runImmediate(action) {
    switch (action) {
      case 1: root.shutdown(); break
      case 2: root.restart(); break
      case 3: root.sleep(); break
      case 4: root.logoff(); break
    }
  }

  // ---------- Power actions ----------
  function shutdown(noConfirm) {
    if (!noConfirm && !confirmAction("shutdown")) return
    root.runAction("power-off")
  }

  function restart(noConfirm) {
    if (!noConfirm && !confirmAction("restart")) return
    root.runAction("reboot")
  }

  function sleep(noConfirm) {
    if (!noConfirm && !confirmAction("sleep")) return
    root.runAction("suspend")
  }

  function logoff(noConfirm) {
    if (!noConfirm && !confirmAction("logoff")) return
    root.runAction("logout")
  }

  function confirmAction(action) {
    confirmLabel = ({
      "shutdown": "Shut down the system now?",
      "restart": "Restart the system now?",
      "sleep": "Put the system to sleep now?",
      "logoff": "Log out of your session now?"
    })[action] || "Proceed?"
    confirmType = action
    visibleConfirm = true
    confirmFade.restart()
    return false
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

  // ---------- Custom timer ----------
  property int customOpen: 0    // actionType with an open custom input, 0 = none
  property int customMinutes: 5

  function isPresetSeconds(secs) {
    for (var i = 0; i < timerPresets.length; i++) {
      if (timerPresets[i].seconds === secs) return true
    }
    return false
  }

  // ---------- Persistent timer state ----------
  readonly property string timerReadScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/gerygerger.power-actions/read-timer.sh"
  readonly property string timerWriteScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/gerygerger.power-actions/write-timer.sh"
  readonly property string timerRemoveScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/gerygerger.power-actions/remove-timer.sh"

  function writeTimerState() {
    timerWriteProc.command = ["bash", root.timerWriteScript, String(root.timerAction), String(root.timerSeconds)]
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

  onOpenedChanged: { if (opened) readTimerState() }

  // ---------- Processes ----------
  Process { id: timerWriteProc
    command: ["true"]
  }

  Process { id: timerReadProc
    command: ["bash", root.timerReadScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split(":")
        if (parts.length >= 2) {
          var a = parseInt(parts[0], 10)
          var s = parseInt(parts[1], 10)
          if (!isNaN(a) && !isNaN(s) && a > 0 && s > 0) {
            root.timerAction = a
            root.timerSeconds = s
          }
        }
      }
    }
  }

  Process { id: removeTimerProc
    command: ["bash", root.timerRemoveScript]
    onExited: { root.timerAction = 0; root.timerSeconds = 0 }
  }

  Process { id: actionProc
    onExited: root.close()
  }

  function runAction(action) {
    var cmd
    if (action === "logout") {
      cmd = "omarchy system logout 2>/dev/null || loginctl terminate-session 2>/dev/null"
    } else {
      cmd = "omarchy system " + action + " 2>/dev/null || systemctl " + action + " 2>/dev/null"
    }
    actionProc.command = ["bash", "-c", cmd]
    actionProc.running = true
  }

  // ---------- Confirm dialog ----------
  property bool visibleConfirm: false
  property int confirmType: 0
  property real confirmOpacity: 0
  property alias confirmLabel: confirmLabelItem.text

  Timer {
    id: confirmFade
    interval: 80
    running: root.visibleConfirm
    repeat: false
    onTriggered: { confirmOpacity = 1 }
  }

  // ---------- Bar button ----------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰐥"
    slotSize: Style.bar.iconSlot
    tooltipText: "Power Actions"
    onPressed: function(b) {
      if (b === Qt.RightButton && root.timerActive) root.cancelTimer()
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
      onCloseRequested: root.close()

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
            text: "󰐥"
            color: root.bar.foreground
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
            visible: root.timerActive
            text: "TIMER"
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.7)
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
            active: root.timerAction === 1
            width: quickRow.cellWidth
            onClicked: root.runImmediate(1)
          }

          Button {
            iconText: "󰜉"
            iconSize: Style.font.iconLarge
            tooltipText: "Restart"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: root.timerAction === 2
            width: quickRow.cellWidth
            onClicked: root.runImmediate(2)
          }

          Button {
            iconText: "󰤄"
            iconSize: Style.font.iconLarge
            tooltipText: "Sleep"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: root.timerAction === 3
            width: quickRow.cellWidth
            onClicked: root.runImmediate(3)
          }

          Button {
            iconText: "󰍃"
            iconSize: Style.font.iconLarge
            tooltipText: "Log off"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: root.timerAction === 4
            width: quickRow.cellWidth
            onClicked: root.runImmediate(4)
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

    // ---------- Confirmation overlay ----------
    Rectangle {
      anchors.fill: parent
      visible: root.visibleConfirm
      color: Qt.rgba(0, 0, 0, 0.55)

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      Rectangle {
        anchors.centerIn: parent
        width: Math.min(Style.space(340), parent.width - Style.spacing.popupPadding * 2)
        implicitHeight: confirmColumn.implicitHeight + Style.spacing.popupPadding * 2
        radius: Style.cornerRadius
        color: root.bar.background
        border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.18)
        border.width: 1
        opacity: root.confirmOpacity

        Column {
          id: confirmColumn
          anchors.centerIn: parent
          width: parent.width - Style.spacing.popupPadding * 2
          spacing: Style.spacing.md

          Text {
            id: confirmLabelItem
            width: parent.width
            text: root.confirmLabel
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          Row {
            anchors.right: parent.right
            spacing: Style.spacing.sm

            Button {
              text: "No"
              fontSize: Style.font.body
              foreground: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.55)
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.visibleConfirm = false
            }

            Button {
              text: "Yes"
              fontSize: Style.font.body
              foreground: "#4ade80"
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: { root.confirmExecute(); root.visibleConfirm = false }
            }
          }
        }
      }
    }
  }

  function confirmExecute() {
    switch (root.confirmType) {
      case 1: root.shutdown(true); break
      case 2: root.restart(true); break
      case 3: root.sleep(true); break
      case 4: root.logoff(true); break
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

    width: parent.width
    implicitHeight: labelHit.implicitHeight + Style.spacing.xxs + chipRow.implicitHeight
      + (root.customOpen === actionType ? customRow.implicitHeight + Style.spacing.sm : 0)

    // Clicking the label runs the action immediately (with confirmation).
    MouseArea {
      id: labelHit
      width: parent.width
      implicitHeight: labelStack.implicitHeight
      onClicked: root.runImmediate(row.actionType)

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
          font.bold: row.isArmed
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