import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Trinity's mute, on the bar: a microphone while she listens for "Hey
// Trinity", a red crossed-out one while she's muted. A click mutes her (the
// wake word off, any conversation ended and her voice cut off) or unmutes her;
// so does Super+Alt+M. Super+Z still reaches her on purpose while she's muted.
// The state is the service's own setting, wakeWord in
// ~/.config/trinity/settings.json.
BarWidget {
  id: root
  moduleName: "marcho.trinity"

  readonly property string home: Quickshell.env("HOME")
  // The node and service that run Trinity, as installed by
  // trinity/install-service.sh.
  readonly property string node: home + "/.local/share/mise/installs/node/latest/bin/node"
  readonly property string service: home + "/projects/o-interfaces/trinity/service/trinity.mjs"
  property bool muted: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.muted ? "󰍭" : "󰍬"
    active: root.muted
    tooltipText: root.muted ? "Trinity is muted · click to unmute" : "Trinity is listening for “Hey Trinity” · click to mute"
    onPressed: function(button) {
      if (!toggle.running) toggle.running = true
    }
  }

  Process {
    id: toggle
    command: [root.node, root.service, "mute", "toggle"]
  }

  FileView {
    id: settingsFile
    path: root.home + "/.config/trinity/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.muted = JSON.parse(text()).wakeWord === false
      } catch (e) {
        root.muted = false
      }
    }
    onLoadFailed: root.muted = false
  }

  // The service replaces the file whole, which a watch can lose.
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: settingsFile.reload()
  }
}
