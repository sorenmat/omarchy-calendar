import QtQuick
import QtQuick.Window
import Quickshell
import "Plugin"
import qs.Commons

Window {
  id: window
  visible: true; width: 540; height: 950; color: Color.background
  Rectangle { anchors.fill: parent; color: Color.background }
  CalendarView {
    id: calendar
    visible: Quickshell.env("PREVIEW_SCREEN") !== "settings"
    x: 20; y: 20; width: parent.width - 40
    now: new Date(2026, 8, 8, 13, 50)
    events: [
      {id:"a", calendarId:"work", calendarName:"Work", color:"#89b4fa", accountEmail:"alex@studio.example", dateKey:"2026-09-08", start:"2026-09-08T14:00:00+02:00", end:"2026-09-08T14:45:00+02:00", allDay:false, title:"Design review", meetingUrl:"https://meet.google.com/example", eventUrl:"https://calendar.google.com"},
      {id:"b", calendarId:"personal", calendarName:"Personal", color:"#a6da95", accountEmail:"alex@example.com", dateKey:"2026-09-08", start:"2026-09-08T16:00:00+02:00", end:"2026-09-08T16:30:00+02:00", allDay:false, title:"Pick up the kids", eventUrl:"https://calendar.google.com"},
      {id:"c", calendarId:"work", calendarName:"Work", color:"#89b4fa", dateKey:"2026-09-09", start:"2026-09-09T09:30:00+02:00", end:"2026-09-09T10:00:00+02:00", allDay:false, title:"Weekly planning", eventUrl:"https://calendar.google.com"},
      {id:"d", calendarId:"family", calendarName:"Family", color:"#f5bde6", dateKey:"2026-09-10", start:"2026-09-10T00:00:00+02:00", end:"2026-09-11T00:00:00+02:00", allDay:true, title:"Emma’s birthday"}
    ]
    document: ({accounts:[{id:"demo", email:"alex@example.com"}]})
  }
  SettingsView {
    visible: Quickshell.env("PREVIEW_SCREEN") === "settings"
    x: 20; y: 20; width: parent.width - 40
    document: ({accounts:[{id:"a",email:"alex@example.com",syncedAt:"2026-09-08T11:45:00Z"},{id:"b",email:"alex@studio.example",error:"Authorization expired. Reconnect this account."}],calendars:[{id:"a:c",accountId:"a",name:"Personal",color:"#a6da95"},{id:"b:c",accountId:"b",name:"Work",color:"#89b4fa"}]})
  }
  Timer { interval: 1800; running: true; onTriggered: window.contentItem.grabToImage(function(result) { result.saveToFile(Quickshell.env("PREVIEW_OUTPUT")); Qt.quit() }) }
}
