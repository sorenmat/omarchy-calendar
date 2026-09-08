import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root
  property var events: []
  property var document: null
  property date now: new Date()
  property int weekStart: 1
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string selectedKey: Model.keyForDate(now)
  property int viewYear: now.getFullYear()
  property int viewMonth: now.getMonth()
  property bool upcoming: true
  readonly property var featured: Model.featuredEvent(events, now.getTime())
  readonly property bool live: !!featured && Date.parse(featured.start) <= now.getTime()
  readonly property var groups: Model.agendaGroups(events, upcoming ? Model.keyForDate(now) : selectedKey, upcoming ? 7 : 1, now.getTime())
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, Model.keyForDate(now), Model.indexEventsByDate(events))
  signal openUrl(string url)
  signal connectRequested()
  spacing: Style.space(12)

  function today() {
    selectedKey = Model.keyForDate(now)
    viewYear = now.getFullYear(); viewMonth = now.getMonth()
    upcoming = true
  }
  function step(delta) {
    var target = Model.stepMonth(viewYear, viewMonth, delta)
    viewYear = target.year; viewMonth = target.month
  }
  function moveDay(delta) {
    var date = Model.dateFromKey(selectedKey, now)
    date.setDate(date.getDate() + delta)
    selectedKey = Model.keyForDate(date)
    viewYear = date.getFullYear(); viewMonth = date.getMonth(); upcoming = false
  }
  function dayLabel(key) {
    var tomorrow = new Date(now); tomorrow.setDate(tomorrow.getDate() + 1)
    var name = key === Model.keyForDate(now) ? qsTr("Today") : key === Model.keyForDate(tomorrow) ? qsTr("Tomorrow") : Qt.formatDate(Model.dateFromKey(key, now), "dddd")
    return name + " · " + Qt.formatDate(Model.dateFromKey(key, now), "d MMM")
  }
  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
  component Action: Button { focusable: true; fontFamily: root.fontFamily; fontSize: Style.font.bodySmall }

  RowLayout {
    width: parent.width
    Label {
      Layout.fillWidth: true
      text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Action { text: qsTr("Today"); onClicked: root.today() }
    Action { text: "‹"; tooltipText: qsTr("Previous month"); onClicked: root.step(-1) }
    Action { text: "›"; tooltipText: qsTr("Next month"); onClicked: root.step(1) }
  }

  Column {
    width: parent.width
    spacing: Style.space(2)
    Row {
      width: parent.width
      Label { width: parent.width / 8; horizontalAlignment: Text.AlignHCenter; text: "W"; opacity: 0.4 }
      Repeater {
        model: Model.weekdayOrder(root.weekStart)
        Label {
          required property int modelData
          width: parent.width / 8
          horizontalAlignment: Text.AlignHCenter
          text: Qt.locale().dayName(modelData, Locale.ShortFormat).replace(/\.$/, "").toUpperCase()
          font.pixelSize: Style.font.caption
          opacity: 0.6
        }
      }
    }
    Repeater {
      model: root.weeks
      Row {
        id: week
        required property var modelData
        width: parent.width
        Label {
          width: parent.width / 8; height: Style.space(35)
          horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
          text: week.modelData.week; opacity: 0.35; font.pixelSize: Style.font.caption
        }
        Repeater {
          model: week.modelData.days
          Item {
            id: day
            required property var modelData
            width: parent.width / 8; height: Style.space(35)
            Action {
              anchors.fill: parent; anchors.margins: Style.space(2)
              text: String(day.modelData.day)
              selected: day.modelData.key === root.selectedKey
              bordered: day.modelData.today
              opacity: day.modelData.inMonth ? 1 : 0.35
              tooltipText: root.dayLabel(day.modelData.key)
              onClicked: { root.selectedKey = day.modelData.key; root.upcoming = false }
            }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
              spacing: Style.space(2)
              Repeater {
                model: day.modelData.dots
                Rectangle {
                  required property string modelData
                  width: Style.space(3); height: width; radius: width / 2; color: modelData
                }
              }
            }
          }
        }
      }
    }
  }

  // NextEvent's prominent meeting card, using the month calendar's event contract.
  Rectangle {
    visible: !!root.featured
    width: parent.width
    height: hero.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.055)
    border.width: root.live ? 1 : 0
    border.color: Color.accent
    Rectangle {
      anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
      anchors.margins: Style.space(2); width: Style.space(3); radius: 2
      color: root.featured ? root.featured.color : Color.accent
    }
    Column {
      id: hero
      x: Style.space(14); y: Style.space(12)
      width: parent.width - Style.space(28)
      spacing: Style.space(6)
      RowLayout {
        width: parent.width
        Label {
          Layout.fillWidth: true
          text: root.live ? qsTr("HAPPENING NOW") : qsTr("UP NEXT")
          font.pixelSize: Style.font.caption; font.letterSpacing: 1; font.bold: true
          color: root.live ? Color.accent : root.foreground; opacity: 0.7
        }
        Label {
          text: !root.featured ? "" : root.live
            ? Math.ceil((Date.parse(root.featured.end) - root.now.getTime()) / 60000) + qsTr(" min left")
            : Model.formatCountdown(Model.millisUntil(root.featured, root.now.getTime())) || root.dayLabel(root.featured.dateKey)
          font.bold: true; color: Color.accent
        }
      }
      Label {
        width: parent.width; text: root.featured ? root.featured.title : ""
        font.pixelSize: Style.font.title; font.bold: true
        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
      }
      Label {
        width: parent.width
        text: root.featured ? Qt.formatTime(new Date(root.featured.start), "HH:mm") + " – " + Qt.formatTime(new Date(root.featured.end), "HH:mm") + " · " + root.featured.calendarName : ""
        opacity: 0.7; elide: Text.ElideRight
      }
      RowLayout {
        width: parent.width
        Action {
          Layout.fillWidth: true
          visible: !!Model.meetingUrlFor(root.featured)
          text: qsTr("Join meeting"); iconText: "󰕧"; selected: true
          onClicked: root.openUrl(Model.meetingUrlFor(root.featured))
        }
        Action {
          Layout.fillWidth: true
          visible: !!Model.eventUrlFor(root.featured)
          text: qsTr("Open event"); bordered: true
          onClicked: root.openUrl(Model.eventUrlFor(root.featured))
        }
      }
    }
  }

  RowLayout {
    width: parent.width
    Action { text: qsTr("Next 7 days"); selected: root.upcoming; onClicked: root.upcoming = true }
    Action { text: qsTr("Selected day"); selected: !root.upcoming; onClicked: root.upcoming = false }
    Item { Layout.fillWidth: true }
  }

  Repeater {
    model: root.groups
    Column {
      id: group
      required property var modelData
      width: parent.width; spacing: Style.space(5)
      Label {
        width: parent.width
        text: root.dayLabel(group.modelData.key).toUpperCase()
        font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1; opacity: 0.6
      }
      Repeater {
        model: group.modelData.items
        Rectangle {
          id: event
          required property var modelData
          width: parent.width; height: eventContent.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: mouse.containsMouse || activeFocus ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07) : "transparent"
          activeFocusOnTab: !!Model.eventUrlFor(modelData)
          Accessible.role: Accessible.Button
          Accessible.name: modelData.title
          Keys.onReturnPressed: root.openUrl(Model.eventUrlFor(modelData))
          MouseArea {
            id: mouse; anchors.fill: parent; hoverEnabled: true
            enabled: !!Model.eventUrlFor(event.modelData)
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openUrl(Model.eventUrlFor(event.modelData))
          }
          RowLayout {
            id: eventContent
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(6); spacing: Style.space(10)
            Rectangle { width: 3; height: Style.space(28); radius: 2; color: event.modelData.color }
            Label {
              Layout.preferredWidth: Style.space(45)
              text: event.modelData.allDay ? qsTr("All day") : Qt.formatTime(new Date(event.modelData.start), "HH:mm")
              font.pixelSize: Style.font.caption; opacity: 0.6
            }
            Column {
              Layout.fillWidth: true; spacing: Style.space(3)
              Label {
                width: parent.width; text: event.modelData.title; elide: Text.ElideRight
                font.strikeout: Model.isDeclined(event.modelData)
                opacity: Model.isDeclined(event.modelData) ? 0.5 : 1
              }
              Label {
                width: parent.width; text: event.modelData.calendarName + (event.modelData.accountEmail ? " · " + event.modelData.accountEmail : "")
                font.pixelSize: Style.font.caption; opacity: 0.45; elide: Text.ElideRight
              }
            }
            Action {
              visible: !Model.isDeclined(event.modelData) && Model.isJoinableNow(event.modelData, root.now.getTime(), Model.keyForDate(root.now))
              text: qsTr("Join"); onClicked: root.openUrl(Model.meetingUrlFor(event.modelData))
            }
          }
        }
      }
      Label { visible: group.modelData.items.length === 0; text: qsTr("Nothing scheduled"); opacity: 0.5 }
    }
  }
  Label {
    width: parent.width
    visible: root.groups.length === 0
    text: !root.document || !(root.document.accounts || []).length ? qsTr("Connect your Google accounts to see your schedule here.") : qsTr("No upcoming events in the next seven days.")
    wrapMode: Text.WordWrap; opacity: 0.6
  }
  Action {
    visible: !root.document || !(root.document.accounts || []).length
    text: qsTr("Connect Google account"); bordered: true; onClicked: root.connectRequested()
  }
  Label {
    width: parent.width
    visible: !!root.document && !!root.document.windowStart && !root.upcoming && (root.selectedKey <= root.document.windowStart || root.selectedKey >= root.document.windowEnd)
    text: qsTr("This date is outside the synced range (past month through next three months).")
    wrapMode: Text.WordWrap; color: Color.urgent
  }
}
