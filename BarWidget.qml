import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "oma.gemi"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false

  property var settings: ({})

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usagePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage/gemini.json"

  property var record: null

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

  function formatTokenCount(n) {
    if (n === undefined || n === null) return "0"
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(n)
  }

  visible: !!record && record.ready === true

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function refreshCollector() {
    refreshProcess.running = true
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.settings = root.settings
  }

  onBarChanged: injectPanel()

  Process {
    id: refreshProcess
    command: ["python3", root.home + "/.config/omarchy/plugins/oma.gemi/collector.py"]
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshCollector(); return "ok" }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      if (!record) return "Gemini"
      var todayPrompts = record.todayPrompts || 0
      var todayTokens = record.todayTotalTokens || 0
      return "Gemini — " + todayPrompts + " prompts (" + formatTokenCount(todayTokens) + " tokens) today"
    }

    iconComponent: Component {
      Item {
        anchors.fill: parent
        Image {
          id: logoImage
          source: Qt.resolvedUrl("assets/gemini.svg")
          anchors.centerIn: parent
          width: Style.bar.iconFont
          height: width
          fillMode: Image.PreserveAspectFit
          visible: false
        }

        MultiEffect {
          source: logoImage
          anchors.fill: logoImage
          colorization: 1.0
          colorizationColor: {
            var activeCol = root.bar ? root.bar.foreground : Color.foreground
            if (root.opened || button.hovered) return activeCol
            return Qt.rgba(activeCol.r, activeCol.g, activeCol.b, 0.65)
          }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        root.refreshCollector()
      } else if (buttonCode !== Qt.MiddleButton) {
        root.toggle()
      }
    }
  }
}
