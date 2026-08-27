import QtQuick
import Quickshell.Io

Item {
  id: root

  // Resolve the path to the collector script inside the active plugin folder
  readonly property string collectorPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/stolli.omagemi/collector.py"

  Timer {
    id: refreshTimer
    interval: 300000 // Refresh every 5 minutes
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.runCollector()
  }

  Process {
    id: collectorProcess
    command: ["python3", root.collectorPath]
    
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("omagemi", "Collector script exited with non-zero code", exitCode)
      } else {
        console.log("omagemi", "Collector script ran successfully")
      }
    }
  }

  function runCollector() {
    if (!collectorProcess.running) {
      collectorProcess.running = true
    }
  }

  Component.onCompleted: runCollector()
}
