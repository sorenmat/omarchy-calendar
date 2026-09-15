pragma ComponentBehavior: Bound
import QtQuick

// Vector cat: separate feet and a bobbing body give it a little walking gait.
Item {
  id: root
  width: 216; height: 164
  property bool walking: true
  property real stride: 0

  SequentialAnimation on stride {
    running: root.walking; loops: Animation.Infinite
    NumberAnimation { from: -1; to: 1; duration: 240; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1; to: -1; duration: 240; easing.type: Easing.InOutSine }
  }

  Rectangle {
    x: 33; y: 153; width: 90; height: 8; radius: 4
    color: "#30000000"
  }
  Repeater {
    model: 2
    Rectangle {
      required property int index
      x: 57 + index * 29; y: 127; width: 18; height: 29; radius: 8
      color: index === 0 ? "#cb8c5b" : "#efb77f"
      border.color: "#49342d"; border.width: 2
      transformOrigin: Item.Top
      rotation: root.stride * (index === 0 ? 23 : -23)
    }
  }

  Item {
    anchors.fill: parent
    transform: Translate { y: -Math.abs(root.stride) * 3 }
    // The tail, body, ears, and face are drawn once; walking moves this item.
    Canvas {
      width: 135; height: 145
      onPaint: {
        var c = getContext("2d")
        c.reset()
        c.lineCap = "round"; c.lineJoin = "round"
        c.strokeStyle = "#49342d"; c.lineWidth = 15
        c.beginPath(); c.moveTo(53, 122); c.bezierCurveTo(10, 129, 14, 87, 29, 96); c.stroke()
        c.strokeStyle = "#efb77f"; c.lineWidth = 10; c.stroke()
        c.lineWidth = 2.5; c.strokeStyle = "#49342d"; c.fillStyle = "#efb77f"
        c.beginPath(); c.ellipse(45, 80, 62, 63); c.fill(); c.stroke()
        c.fillStyle = "#ffe6c7"
        c.beginPath(); c.ellipse(64, 99, 30, 36); c.fill()
        c.fillStyle = "#efb77f"
        c.beginPath(); c.moveTo(44, 66); c.lineTo(43, 30); c.lineTo(66, 45)
        c.bezierCurveTo(75, 41, 88, 43, 93, 45); c.lineTo(111, 31); c.lineTo(113, 67)
        c.bezierCurveTo(124, 105, 35, 111, 44, 66); c.fill(); c.stroke()
        c.fillStyle = "#df9286"
        c.beginPath(); c.moveTo(49, 40); c.lineTo(50, 59); c.lineTo(61, 49); c.closePath(); c.fill()
        c.beginPath(); c.moveTo(105, 41); c.lineTo(97, 51); c.lineTo(108, 60); c.closePath(); c.fill()
        c.fillStyle = "#49342d"
        c.beginPath(); c.ellipse(64, 66, 5, 8); c.fill()
        c.beginPath(); c.ellipse(94, 66, 5, 8); c.fill()
        c.fillStyle = "#ffe6c7"
        c.beginPath(); c.ellipse(69, 78, 29, 15); c.fill()
        c.fillStyle = "#a55756"
        c.beginPath(); c.moveTo(79, 78); c.lineTo(87, 78); c.lineTo(83, 83); c.closePath(); c.fill()
        c.lineWidth = 1.5
        c.beginPath(); c.moveTo(83, 83); c.lineTo(83, 87); c.stroke()
        c.beginPath(); c.moveTo(56, 79); c.lineTo(37, 75); c.moveTo(56, 85); c.lineTo(38, 88)
        c.moveTo(105, 79); c.lineTo(122, 75); c.moveTo(105, 85); c.lineTo(122, 88); c.stroke()
        c.strokeStyle = "#cb8c5b"; c.lineWidth = 4
        c.beginPath(); c.moveTo(71, 47); c.lineTo(74, 54); c.moveTo(82, 46); c.lineTo(82, 53); c.stroke()
      }
    }
    Rectangle {
      x: 125; y: 40; width: 7; height: 98; radius: 3
      color: "#a77550"; border.color: "#49342d"; border.width: 2
      rotation: -5
    }
    Rectangle {
      x: 101; y: 104; width: 31; height: 16; radius: 8; rotation: -12
      color: "#efb77f"; border.color: "#49342d"; border.width: 2
    }
    Rectangle {
      x: 108; y: 7; width: 106; height: 57; radius: 7; rotation: -5
      color: "#fff3d9"; border.color: "#49342d"; border.width: 3
      Text {
        anchors.centerIn: parent
        text: "MEETING\nNOW!"; color: "#49342d"
        horizontalAlignment: Text.AlignHCenter
        font.family: "sans-serif"; font.pixelSize: 17; font.bold: true
      }
    }
  }
}
