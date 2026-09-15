import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root
  property var document: null
  property var hiddenCalendars: []
  property bool busy: false
  property bool weekStartsMonday: true
  property bool hideDeclined: false
  property int startPulseMinutes: 3
  property bool meetingMascot: true
  property string message: ""
  property string removing: ""
  property bool advancedOpen: false
  signal connectRequested(string path, string account)
  signal removeRequested(string account)
  signal calendarToggled(string id)
  signal weekStartToggled()
  signal declinedToggled()
  signal startPulseMinutesEdited(int minutes)
  signal meetingMascotToggled()
  signal mascotPreviewRequested()
  spacing: Style.space(12)
  component Label: Text {
    textFormat: Text.PlainText; color: Color.foreground
    font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
  }
  component Action: Button { focusable: true; fontSize: Style.font.bodySmall }
  Label { text: qsTr("GOOGLE ACCOUNTS"); font.bold: true; font.letterSpacing: 1; opacity: 0.6 }
  Label {
    width: parent.width; wrapMode: Text.WordWrap; opacity: 0.7
    text: qsTr("Connect your Google accounts to show calendars and respond to invitations. Previously connected accounts need to reconnect once to enable Accept and Reject.")
  }
  Repeater {
    model: root.document ? root.document.accounts || [] : []
    Column {
      id: account
      required property var modelData
      width: parent.width; spacing: Style.space(5)
      Label { width: parent.width; text: account.modelData.email; elide: Text.ElideRight; font.bold: true }
      Label {
        width: parent.width; wrapMode: Text.WordWrap
        text: account.modelData.error || (account.modelData.syncedAt ? qsTr("Synced ") + Qt.formatDateTime(new Date(account.modelData.syncedAt), "d MMM HH:mm") : qsTr("Waiting for first sync"))
        color: account.modelData.error ? Color.urgent : Color.foreground; opacity: 0.7
      }
      RowLayout {
        Action { text: qsTr("Reconnect"); enabled: !root.busy; onClicked: root.connectRequested("", account.modelData.id) }
        Action { text: qsTr("Remove"); enabled: !root.busy; onClicked: root.removing = account.modelData.id }
      }
      Column {
        visible: root.removing === account.modelData.id
        width: parent.width; spacing: Style.space(4)
        Label { width: parent.width; wrapMode: Text.WordWrap; text: qsTr("Remove this account's saved login and cached events from this device?") }
        Row {
          Action { text: qsTr("Remove account"); enabled: !root.busy; onClicked: { root.removeRequested(account.modelData.id); root.removing = "" } }
          Action { text: qsTr("Cancel"); onClicked: root.removing = "" }
        }
      }
      Repeater {
        model: root.document ? (root.document.calendars || []).filter(function(c) { return c.accountId === account.modelData.id }) : []
        Action {
          required property var modelData
          width: parent.width
          text: (root.hiddenCalendars.indexOf(modelData.id) === -1 ? "✓  " : "○  ") + Model.truncateTitle(modelData.name, 48)
          tooltipText: modelData.name
          horizontalPadding: Style.space(16)
          Rectangle {
            x: Style.space(5); anchors.verticalCenter: parent.verticalCenter
            width: Style.space(3); height: Style.space(14); radius: 2
            color: parent.modelData.color
          }
          accent: modelData.color; foreground: modelData.color; leftAlign: true
          selected: root.hiddenCalendars.indexOf(modelData.id) === -1
          onClicked: root.calendarToggled(modelData.id)
        }
      }
    }
  }
  RowLayout {
    width: parent.width
    Action { text: qsTr("Connect Google account"); selected: true; enabled: !root.busy; onClicked: root.connectRequested("", "") }
  }
  FileDialog {
    id: picker
    title: qsTr("Choose Google Desktop OAuth credentials")
    nameFilters: ["Google credentials (*.json)"]
    onAccepted: root.connectRequested(decodeURIComponent(String(selectedFile).replace(/^file:\/\//, "")), "")
  }
  Label {
    width: parent.width; wrapMode: Text.WordWrap; opacity: 0.6
    text: qsTr("Sign in through your browser and choose the calendars to display. Your login stays in your desktop keyring.")
  }
  Action {
    text: (root.advancedOpen ? "▾ " : "▸ ") + qsTr("Advanced setup")
    onClicked: root.advancedOpen = !root.advancedOpen
  }
  Label {
    visible: root.advancedOpen
    width: parent.width; wrapMode: Text.WordWrap; opacity: 0.6
    text: qsTr("Use your own Google OAuth app instead of the shared registration. Import a Desktop app credentials JSON, then sign in. This preference applies to new accounts on this device.")
  }
  Action {
    visible: root.advancedOpen
    text: qsTr("Import credentials…"); bordered: true; enabled: !root.busy; onClicked: picker.open()
  }
  Action {
    visible: root.advancedOpen
    text: qsTr("Open Google Cloud setup")
    onClicked: Qt.openUrlExternally("https://console.cloud.google.com/auth/clients")
  }
  Label { text: qsTr("DISPLAY"); font.bold: true; font.letterSpacing: 1; opacity: 0.6 }
  Action { text: (root.weekStartsMonday ? "✓  " : "○  ") + qsTr("Week starts Monday"); onClicked: root.weekStartToggled() }
  Action { text: (!root.hideDeclined ? "✓  " : "○  ") + qsTr("Show declined invitations"); onClicked: root.declinedToggled() }
  NumberField {
    label: qsTr("Meeting start pulse (minutes, 0 = off)")
    value: root.startPulseMinutes; from: 0; to: 60
    onModified: function(value) { root.startPulseMinutesEdited(value) }
  }
  Action { text: (root.meetingMascot ? "✓  " : "○  ") + qsTr("Walking cat at meeting start"); onClicked: root.meetingMascotToggled() }
  Action {
    text: qsTr("Test now"); bordered: true
    tooltipText: qsTr("Show the walking cat with its Meeting now sign")
    onClicked: root.mascotPreviewRequested()
  }
  Label { width: parent.width; wrapMode: Text.WordWrap; visible: text !== ""; text: root.message; color: Color.accent }
}
