import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root
  required property var events
  required property string helper
  required property string stateDir
  property var notified: ({})
  property var pending: []

  function check() {
    if (sender.running) return
    var now = Date.now()
    for (var key in notified) if (now - notified[key] >= 60000) delete notified[key]
    pending = Model.startAlerts(events, now, notified)
    if (!pending.length) return
    sender.command = ["python3", helper, "--state-dir", stateDir, "notify", JSON.stringify(pending)]
    sender.running = true
  }

  // Runs while the calendar popup is closed too.
  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.check() }
  Process {
    id: sender
    onExited: function(code, status) {
      if (code === 0) {
        for (var i = 0; i < root.pending.length; i++)
          root.notified[root.pending[i].key] = root.pending[i].start
      } else console.warn("Calendar start notification failed; will retry shortly.")
    }
  }
}
