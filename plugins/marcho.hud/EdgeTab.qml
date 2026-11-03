import QtQuick
import qs.Commons
import qs.Commons as Commons

// The slim tab a hidden widget leaves at its screen edge: its name, brighter
// under the mouse; a click brings the widget back. The same file is in each
// widget's plugin (the Neon HUD, the Agent Radar, Trinity).
Rectangle {
  id: tab

  property string label: ""
  // Upright along a side edge, or lying along the top.
  property bool vertical: true
  // Reads downward (the right edge) rather than upward (the left).
  property bool downward: false
  property color accent: Commons.Color.accent

  signal activated()

  readonly property int thick: Math.round(22 * Style.fontScale)

  width: vertical ? thick : name.implicitWidth + Math.round(28 * Style.fontScale)
  height: vertical ? name.implicitWidth + Math.round(28 * Style.fontScale) : thick
  color: Util.alpha(accent, mouse.containsMouse ? 0.16 : 0.06)
  border.width: 1
  border.color: Util.alpha(accent, mouse.containsMouse ? 0.7 : 0.3)

  Text {
    id: name
    anchors.centerIn: parent
    rotation: tab.vertical ? (tab.downward ? 90 : -90) : 0
    text: tab.label
    textFormat: Text.PlainText
    color: Util.alpha(tab.accent, mouse.containsMouse ? 1 : 0.6)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: Math.round(3 * Style.fontScale)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tab.activated()
  }
}
