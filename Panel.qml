import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "oma.gemi"
  ipcTarget: "oma.gemi"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var settings: ({})

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usagePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage/gemini.json"

  property var record: null
  property bool cursorActive: false
  property double nowMs: Date.now()

  readonly property var balance: record ? (record.balance || null) : null
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    return formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
  }

  FileView {
    path: root.usagePath
    watchChanges: true
    printErrors: false
    onLoaded: root.parse(text())
    onLoadFailed: root.record = null
  }

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.record = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      root.record = null
    }
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function formatTokenCount(n) {
    if (n === undefined || n === null) return "0"
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(n)
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    var prefix = currency === "EUR" ? "€" : "$"
    return prefix + amount.toFixed(2)
  }

  function refreshNow() {
    refreshProcess.running = true
  }

  // Processes for refreshing and toggling
  Process {
    id: refreshProcess
    command: ["python3", root.home + "/.config/omarchy/plugins/oma.gemi/collector.py"]
  }

  Process {
    id: saveConfigProcess
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.refreshNow()
      }
    }
  }

  readonly property var days: root.record ? (root.record.recentDays || []) : []
  readonly property real weekPeak: {
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return Math.max(1, peak)
  }

  readonly property var models: {
    var usageByModel = root.record ? (root.record.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function friendlyModelName(id) {
    if (!id) return "Unknown"
    var name = String(id).replace(/^gemini-/, "").replace(/-\d{8}$/, "")
    var parts = name.split("-")
    var words = []
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i]
      if (part === "") continue
      words.push(part.charAt(0).toUpperCase() + part.slice(1))
    }
    return words.length > 0 ? words.join(" ") : "Unknown"
  }

  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + root.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    if (today && root.record)
      text += " · " + Number(root.record.todayPrompts || 0) + " prompts · "
        + Number(root.record.todaySessions || 0) + " sessions"
    return text
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + root.formatTokenCount(row.input)
      + " · out " + root.formatTokenCount(row.output)
      + " · cache read " + root.formatTokenCount(row.cacheRead)
      + " · cache write " + root.formatTokenCount(row.cacheWrite)
  }

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    root.refreshNow()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Google Gemini"
            meta: root.record ? root.record.tierLabel : "Pay-as-you-go"
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display
                Image {
                  id: heroLogo
                  anchors.fill: parent
                  source: Qt.resolvedUrl("assets/gemini.svg")
                  fillMode: Image.PreserveAspectFit
                  visible: false
                }
                MultiEffect {
                  source: heroLogo
                  anchors.fill: heroLogo
                  colorization: 1.0
                  colorizationColor: root.foreground
                }
              }
            }
          }

          // ---------- Balance Section ----------
          PanelSeparator {
            visible: !!root.balance
            foreground: root.foreground
          }

          Column {
            id: balanceSection
            visible: !!root.balance
            width: parent.width
            spacing: Style.space(10)

            readonly property real ratio: root.balance && root.balance.funded > 0
              ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
              : -1

            PanelSectionHeader {
              width: parent.width
              text: "BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                text: "Prepaid credits"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                color: root.balanceAlarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              visible: balanceSection.ratio >= 0
              width: parent.width
              value: balanceSection.ratio
              alarming: root.balanceAlarming
            }

            Text {
              visible: text !== ""
              width: parent.width
              text: root.balanceDetailText(root.balance)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- Details Section ----------
          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoPair { label: "Today's Prompts"; value: root.record ? String(root.record.todayPrompts) : "0" }
            InfoPair { label: "Today's Sessions"; value: root.record ? String(root.record.todaySessions) : "0" }
            InfoPair { label: "Total Tokens Today"; value: root.record ? root.formatTokenCount(root.record.todayTotalTokens) : "0" }
            InfoPair { label: "Active Days"; value: root.record ? String(root.record.activeDays) : "0" }
          }

          // ---------- Top-up Input Section ----------
          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              width: parent.width
              text: "GUTHABEN VERWALTEN"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // 1. Top-up Row
            Row {
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: parent.width - Style.space(120)
                spacing: Style.space(4)
                Text {
                  text: "Betrag aufladen (€) — addiert automatisch"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TextField {
                  id: topUpField
                  width: parent.width
                  placeholderText: "z.B. 20.00"
                  text: ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  padding: Style.space(6)
                  background: Rectangle {
                    color: root.alpha(root.foreground, 0.05)
                    border.color: topUpField.activeFocus ? root.track : root.dim
                    border.width: 1
                    radius: Style.cornerRadius
                  }
                }
              }

              Button {
                id: topUpButton
                width: Style.space(112)
                anchors.bottom: parent.bottom
                text: "Aufladen"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  var val = parseFloat(topUpField.text)
                  if (!isNaN(val) && val > 0) {
                    saveConfigProcess.command = ["python3", "-c", 
                      "import json, os, datetime; " +
                      "path = os.path.expanduser('~/.config/omarchy/agents/gemini.json'); " +
                      "data = {'fundedAmount': 25.0, 'currentBalance': 6.78, 'currency': 'EUR', 'fundedAt': '" + (root.record ? root.record.updatedAt.substring(0, 10) : datetime.date.today().isoformat()) + "'}; " +
                      "if os.path.exists(path): " +
                      "  try: " +
                      "    with open(path, 'r') as f: data = json.load(f) " +
                      "  except: pass; " +
                      "data['fundedAmount'] = float(data.get('fundedAmount', 0)) + " + val + "; " +
                      "data['currentBalance'] = float(data.get('currentBalance', 0)) + " + val + "; " +
                      "with open(path, 'w') as f: json.dump(data, f, indent=2)"
                    ]
                    saveConfigProcess.running = true
                    topUpField.text = ""
                  }
                }
              }
            }

            // 2. Correction Row
            Row {
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: parent.width - Style.space(120)
                spacing: Style.space(4)
                Text {
                  text: "Echten Kontostand korrigieren (€)"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                TextField {
                  id: balanceField
                  width: parent.width
                  placeholderText: "z.B. 6.78"
                  text: root.balance ? root.balance.remaining.toFixed(2) : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  padding: Style.space(6)
                  background: Rectangle {
                    color: root.alpha(root.foreground, 0.05)
                    border.color: balanceField.activeFocus ? root.track : root.dim
                    border.width: 1
                    radius: Style.cornerRadius
                  }
                }
              }

              Button {
                id: correctButton
                width: Style.space(112)
                anchors.bottom: parent.bottom
                text: "Korrigieren"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  var val = parseFloat(balanceField.text)
                  if (!isNaN(val)) {
                    saveConfigProcess.command = ["python3", "-c", 
                      "import json, os, datetime; " +
                      "path = os.path.expanduser('~/.config/omarchy/agents/gemini.json'); " +
                      "data = {'fundedAmount': 25.0, 'currentBalance': 6.78, 'currency': 'EUR', 'fundedAt': '" + (root.record ? root.record.updatedAt.substring(0, 10) : datetime.date.today().isoformat()) + "'}; " +
                      "if os.path.exists(path): " +
                      "  try: " +
                      "    with open(path, 'r') as f: data = json.load(f) " +
                      "  except: pass; " +
                      "data['currentBalance'] = " + val + "; " +
                      "with open(path, 'w') as f: json.dump(data, f, indent=2)"
                    ]
                    saveConfigProcess.running = true
                  }
                }
              }
            }
          }

          // ---------- Tokens by Day Section ----------
          PanelSeparator {
            visible: root.days.length > 0
            foreground: root.foreground
          }

          Column {
            id: usageSection
            visible: root.days.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY DAY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.days

              DayRow {
                required property var modelData
                required property int index

                width: usageSection.width
                day: modelData
                ratio: Number(modelData.messageCount || 0) / root.weekPeak
                today: String(modelData.date || "") === root.todayDate()
              }
            }
          }

          // ---------- Tokens by Model Section ----------
          PanelSeparator {
            visible: root.models.length > 0
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: root.models.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY MODEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.models

              ModelRow {
                required property var modelData
                width: modelSection.width
                row: modelData
                share: modelData.total / Math.max(1, root.models[0].total)
              }
            }
          }
        }
      }
    }
  }

  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      text: root.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      text: modelRow.row ? root.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }

  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    visible: true
    width: parent.width
    spacing: Style.space(8)
    Text {
      text: label
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    Text {
      text: value
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
