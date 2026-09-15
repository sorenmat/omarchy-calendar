import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: root
  required property Item anchorItem
  property bool active: false
  property string eventKey: ""
  property bool previewing: false
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null

  function preview() { previewing = true; walk.restart() }
  onActiveChanged: {
    if (active) walk.restart()
    else if (!previewing) walk.stop()
  }
  onEventKeyChanged: if (active) walk.restart()

  screen: anchorWindow ? anchorWindow.screen : null
  anchors { bottom: true; left: true; right: true }
  margins.bottom: 36
  implicitHeight: 180
  visible: walk.running
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-calendar-mascot"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {}

  MeetingMascot {
    id: mascot
    y: 8
    walking: walk.running
  }
  NumberAnimation {
    id: walk
    target: mascot; property: "x"
    from: -mascot.width; to: root.screen ? root.screen.width : root.width
    duration: 12000
    onFinished: root.previewing = false
  }
}
