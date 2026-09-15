import QtQuick
import Quickshell
import ".."
ShellRoot {
  id: test
  MeetingWalk { id: overlay; anchorItem: null; screen: Quickshell.screens[0] }
  property real firstX: 0
  property real firstStride: 0
  property bool failed: false
  function check(ok, message) { if (!ok) { failed = true; console.error(message) } }
  Timer { interval: 100; running: true; onTriggered: overlay.preview() }
  Timer {
    interval: 600; running: true
    onTriggered: {
      test.check(overlay.visible, "Preview did not become visible")
      test.firstX = overlay.contentItem.children[0].x
      test.firstStride = overlay.contentItem.children[0].stride
      test.check(overlay.exclusionMode === ExclusionMode.Ignore, "Overlay reserved screen space")
    }
  }
  Timer {
    interval: 850; running: true
    onTriggered: {
      test.check(overlay.contentItem.children[0].x > test.firstX, "Cat did not walk right")
      test.check(overlay.contentItem.children[0].stride !== test.firstStride, "Feet did not move")
    }
  }
  Timer {
    interval: 12400; running: true
    onTriggered: {
      test.check(!overlay.visible, "Preview did not finish")
      overlay.active = true
      test.check(overlay.visible, "Meeting start did not trigger walk")
      overlay.active = false
      test.check(!overlay.visible, "Walk did not stop when meeting ceased to pulse")
      console.log(test.failed ? "WALK CHECK FAILED" : "WALK CHECK PASSED")
      Qt.quit()
    }
  }
}
