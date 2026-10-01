import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "smo.calendar"
  ipcTarget: "smo.calendar"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/smo.calendar"
  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("calendarctl")).replace(/^file:\/\//, ""))
  property var eventDoc: null
  property date now: new Date()
  property bool settingsOpen: false
  property string statusMessage: ""
  property string operation: ""
  readonly property var hiddenCalendars: setting("hiddenCalendars", [])
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property var visibleEventList: Model.mergedEvents(eventDoc ? eventDoc.events : [], hiddenCalendars, {hideDeclined: setting("hideDeclined", false), doneEvents: setting("doneEvents", [])})
  readonly property bool needsAttention: !!eventDoc && (eventDoc.accounts || []).some(function(a) { return !!a.error || !a.syncedAt || root.now.getTime() - Date.parse(a.syncedAt) > 1200000 })

  function persist(values) {
    var entry = {id: root.moduleName}
    for (var k in root.settings) entry[k] = root.settings[k]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (hostWidget) hostWidget.settings = entry
    if (bar && bar.shell) bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function toggleWeekStart() { persist({weekStartDay: Model.weekStartSettingName(Model.toggledWeekStart(weekStart))}) }
  function toggleDone(event) {
    var key = Model.occurrenceKey(event)
    var done = setting("doneEvents", [])
    persist({doneEvents: done.indexOf(key) === -1 ? done.concat([key]) : done.filter(function(k) { return k !== key })})
  }
  function markDone(event) {
    if (!event) return
    var key = Model.occurrenceKey(event)
    var done = setting("doneEvents", [])
    if (done.indexOf(key) === -1) persist({doneEvents: done.concat([key])})
  }
  function joinMeeting(event) { root.openLink(Model.meetingUrlFor(event)); root.markDone(event) }
  function refresh() { root.now = new Date(); eventsFile.reload() }
  function open() { refresh(); calendar.today(); root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? close() : open() }
  function run(args) {
    if (backend.running) return
    operation = args[0]
    statusMessage = operation === "connect" ? "Complete Google sign-in in your browser…" : operation === "respond" ? "Sending response…" : "Updating calendar…"
    backend.command = ["python3", helper, "--state-dir", stateDir].concat(args)
    backend.running = true
  }
  function connect(path, account) {
    var args = ["connect"]
    if (path) args = args.concat(["--client", path])
    if (account) args = args.concat(["--account", account])
    run(args)
  }
  function openLink(url) { if (Model.safeUrl(url)) { Qt.openUrlExternally(url); close() } }

  FileView {
    id: eventsFile
    path: root.stateDir + "/events.json"
    watchChanges: true; printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var doc = JSON.parse(text())
        if (doc.version !== 1 || !Array.isArray(doc.events)) throw new Error("Invalid calendar cache")
        root.eventDoc = doc
      } catch (error) { root.statusMessage = "Could not read calendar cache. Last loaded events are retained." }
    }
  }
  Process {
    id: backend
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          root.statusMessage = result.error || (root.operation === "respond" ? "Response sent." : result.accounts.some(function(a) { return !!a.error }) ? "Some accounts need attention. Cached events are still shown." : "Calendar updated.")
        } catch (error) { root.statusMessage = "Calendar helper could not finish. Try again." }
      }
    }
    onExited: function(code, status) { eventsFile.reload(); if (code !== 0 && !root.statusMessage) root.statusMessage = "Calendar helper failed." }
  }
  Timer { interval: 300000; running: true; repeat: true; onTriggered: if (root.eventDoc && root.eventDoc.accounts.length) root.run(["sync"]) }
  Timer { interval: 1500; running: true; onTriggered: if (root.eventDoc && root.eventDoc.accounts.length) root.run(["sync"]) }
  SystemClock { precision: SystemClock.Minutes; onDateChanged: root.now = date }

  EventAlerts {
    events: root.visibleEventList
    helper: root.helper
    stateDir: root.stateDir
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem; owner: root.barIdentity; bar: root.bar
    open: root.opened; centerOnBar: true; focusTarget: content
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(Math.min(Style.space(850), column.implicitHeight))
    Item {
      id: content
      anchors.fill: parent; focus: true
      Keys.onEscapePressed: { if (root.settingsOpen) root.settingsOpen = false; else root.close() }
      Keys.onPressed: function(event) {
        if (root.settingsOpen || event.modifiers !== Qt.NoModifier) return
        if (event.key === Qt.Key_Left) calendar.moveDay(-1)
        else if (event.key === Qt.Key_Right) calendar.moveDay(1)
        else if (event.key === Qt.Key_Up) calendar.moveDay(-7)
        else if (event.key === Qt.Key_Down) calendar.moveDay(7)
        else if (event.text === "[") calendar.step(-1)
        else if (event.text === "]") calendar.step(1)
        else if (event.text === "t") calendar.today()
        else if (event.text === "r") root.run(["sync"])
        else if (event.text === "s") root.settingsOpen = true
        else if (event.text === "m") root.joinMeeting(calendar.featured)
        else return
        event.accepted = true
      }
      Flickable {
        anchors.fill: parent; clip: true
        contentWidth: width; contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: column; width: parent.width; spacing: Style.space(12)
          Row {
            width: parent.width
            Text {
              width: parent.width - actions.width; anchors.verticalCenter: parent.verticalCenter
              text: root.settingsOpen ? qsTr("Accounts & calendars") : qsTr("Calendar")
              textFormat: Text.PlainText; color: Color.foreground
              font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true
            }
            Row {
              id: actions
              Button {
                text: qsTr("Test now"); tooltipText: qsTr("Show the walking cat with its Meeting now sign")
                bordered: true; focusable: true
                onClicked: { root.close(); if (root.hostWidget) root.hostWidget.previewMascot() }
              }
              Button { text: backend.running ? "…" : "↻"; tooltipText: qsTr("Refresh calendars"); focusable: true; enabled: !backend.running; onClicked: root.run(["sync"]) }
              Button { text: root.settingsOpen ? "←" : "⚙"; tooltipText: root.settingsOpen ? qsTr("Back to calendar") : qsTr("Accounts and settings"); focusable: true; onClicked: root.settingsOpen = !root.settingsOpen }
            }
          }
          Button {
            visible: root.needsAttention && !root.settingsOpen
            width: parent.width; text: qsTr("Calendar may be out of date · Check accounts")
            foreground: Color.urgent; focusable: true; onClicked: root.settingsOpen = true
          }
          CalendarView {
            id: calendar
            visible: !root.settingsOpen; width: parent.width
            events: root.visibleEventList; document: root.eventDoc; now: root.now; weekStart: root.weekStart
            busy: backend.running; message: root.statusMessage
            onRespondRequested: function(event, response) { root.run(["respond", event.accountId, event.calendarId, event.id, response]) }
            onDoneRequested: function(event) { root.toggleDone(event) }
            onJoinRequested: function(event) { root.joinMeeting(event) }
            onOpenUrl: function(url) { root.openLink(url) }
            onConnectRequested: root.settingsOpen = true
          }
          SettingsView {
            visible: root.settingsOpen; width: parent.width
            document: root.eventDoc; hiddenCalendars: root.hiddenCalendars
            busy: backend.running; message: root.statusMessage
            weekStartsMonday: root.weekStart === 1; hideDeclined: root.setting("hideDeclined", false)
            startPulseMinutes: root.setting("startPulseMinutes", 3)
            meetingMascot: root.setting("meetingMascot", true)
            onMeetingMascotToggled: root.persist({meetingMascot: !root.setting("meetingMascot", true)})
            onMascotPreviewRequested: { root.close(); if (root.hostWidget) root.hostWidget.previewMascot() }
            onStartPulseMinutesEdited: function(minutes) { root.persist({startPulseMinutes: minutes}) }
            onConnectRequested: function(path, account) { root.connect(path, account) }
            onRemoveRequested: function(account) { root.run(["remove", account]) }
            onCalendarToggled: function(id) { root.persist({hiddenCalendars: Model.toggleHiddenCalendar(root.hiddenCalendars, id)}) }
            onWeekStartToggled: root.toggleWeekStart()
            onDeclinedToggled: root.persist({hideDeclined: !root.setting("hideDeclined", false)})
          }
        }
      }
    }
  }
}
