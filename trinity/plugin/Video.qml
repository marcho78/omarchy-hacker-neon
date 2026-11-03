import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.Commons

// The video Trinity plays on the desktop. The service says which (play_video:
// {id, title, channel, duration}) and passes on her controls; this plays it
// through Uber TV's streamer (its om-pg-streamer, run here as our own copy),
// which serves a YouTube video as a playlist Qt's player can show: the best
// H.264 up to 1080p with the original audio, seekable.
//
// Three sizes: "panel", on the desktop between the Agent Radar and the HUD,
// behind the windows; "full", over everything, bar included; and "window", a
// floating window in front of the apps on every workspace, which Omarchy's
// picture-in-picture rule (apps/pip.lua) floats, pins and keeps 16:9 because
// it is titled Picture-in-Picture.
Item {
  id: video

  property var trinity: null
  // {id, title, channel, duration, at}, or null.
  readonly property var current: trinity ? trinity.video : null
  property string mode: "panel"
  readonly property string streamer: Quickshell.env("HOME") + "/.config/omarchy/plugins/marcho78.om-pg/bin/om-pg-streamer"
  // http://127.0.0.1:<port>/<secret>, once the streamer has started.
  property string base: ""
  property string problem: ""

  readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
  readonly property bool loading: !!current && !problem && (player.mediaStatus === MediaPlayer.LoadingMedia
    || player.mediaStatus === MediaPlayer.BufferingMedia || player.mediaStatus === MediaPlayer.StalledMedia
    || player.mediaStatus === MediaPlayer.NoMedia)
  readonly property real position: player.position
  readonly property real length: player.duration > 0 ? player.duration : (current ? current.duration * 1000 : 0)
  readonly property real volume: audio.volume

  onCurrentChanged: start()

  function start() {
    problem = ""
    if (!current) {
      player.stop()
      player.source = ""
      mode = "panel"
      streamerProcess.running = false
      return
    }
    // A new video shows even if the last one was hidden.
    if (trinity.videoHidden) trinity.widgets(["show", "video"])
    if (!base) {
      streamerProcess.running = true
      return
    }
    player.source = base + "/play/" + current.id + ".m3u8"
    player.play()
  }

  function control(command, seconds) {
    if (!current) return
    var ms = (Number(seconds) || 60) * 1000
    if (command === "pause") player.pause()
    else if (command === "resume") player.play()
    else if (command === "toggle") playing ? player.pause() : player.play()
    else if (command === "louder") audio.volume = Math.min(1, audio.volume + 0.15)
    else if (command === "quieter") audio.volume = Math.max(0, audio.volume - 0.15)
    else if (command === "forward") player.position = Math.min(Math.max(0, player.duration - 1000), player.position + ms)
    else if (command === "back") player.position = Math.max(0, player.position - ms)
    else if (command === "full_screen") mode = "full"
    else if (command === "window") mode = "window"
    else if (command === "panel") mode = "panel"
    else if (command === "stop") stop()
  }

  function seekTo(fraction) {
    if (player.duration > 0) player.position = Math.max(0, Math.min(1, fraction)) * player.duration
  }

  function stop() {
    trinity.command("video stop")
  }

  // "03:12", or "1:03:12" past an hour.
  function clock(ms) {
    var s = Math.max(0, Math.floor(ms / 1000))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var pad = function(n) { return (n < 10 ? "0" : "") + n }
    return (h > 0 ? h + ":" + pad(m) : pad(m)) + ":" + pad(s % 60)
  }

  // omarchy-shell marcho.trinity.video status|toggle|stop|full|window|panel
  ShellIpc {
    target: "marcho.trinity.video"

    function status(): string {
      return JSON.stringify(video.current ? {
        title: video.current.title, mode: video.mode, playing: video.playing, loading: video.loading,
        problem: video.problem, position: Math.round(video.position / 1000), length: Math.round(video.length / 1000),
      } : null)
    }
    function toggle(): void { video.control("toggle") }
    function stop(): void { video.control("stop") }
    function full(): void { video.control("full_screen") }
    function window(): void { video.control("window") }
    function panel(): void { video.control("panel") }
  }

  // The streamer prints "<port> <secret>" when it's ready.
  Process {
    id: streamerProcess
    command: [video.streamer]
    stdout: SplitParser {
      onRead: (line) => {
        var m = String(line).match(/^(\d+) (\S+)$/)
        if (m && !video.base) {
          video.base = "http://127.0.0.1:" + m[1] + "/" + m[2]
          video.start()
        }
      }
    }
    onExited: (code) => {
      video.base = ""
      if (video.current) video.problem = "The video streamer stopped (" + code + ")."
    }
  }

  MediaDevices {
    id: devices
  }

  MediaPlayer {
    id: player
    audioOutput: AudioOutput {
      id: audio
      device: devices.defaultAudioOutput
      volume: 0.8
    }
    videoOutput: video.mode === "full" ? fullWindow.output : (video.mode === "window" ? popWindow.output : panelWindow.output)
    onErrorOccurred: (error, errorString) => video.problem = errorString || "The video couldn't be played."
    onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) video.stop()
  }

  VideoPanel {
    id: panelWindow
    video: video
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  VideoFull {
    id: fullWindow
    video: video
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  VideoPop {
    id: popWindow
    video: video
  }
}
