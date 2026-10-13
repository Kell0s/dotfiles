// Kellos Music — плашка трека по центру панели + мини-плеер
//   ЛКМ — пауза · ПКМ — следующий · колёсико (клик) — мини-плеер
//   свайп двумя пальцами: влево — следующий, вправо — предыдущий
//   наведение — полное название
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

ShellRoot {
  id: root

  // ---------- палитра Kellos ----------
  readonly property color cBase: "#160e24"
  readonly property color cSurface: "#271a3d"
  readonly property color cMauve: "#b48efa"
  readonly property color cPink: "#f5a9e0"
  readonly property color cText: "#e0d4f5"
  readonly property color cDim: "#8c7aa8"
  readonly property string iconFont: "Font Awesome 6 Free"
  readonly property string textFont: "JetBrains Mono"

  // если свайпы работают наоборот — поменяй на -1
  readonly property int swipeDirection: 1
  // вертикальное положение плашки (больше — ниже)
  readonly property int pillTop: 4

  // ---------- состояние ----------
  property bool barHidden: false
  property bool popupOpen: false
  property bool tipOpen: false

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    for (let i = 0; i < players.length; i++)
      if (players[i].isPlaying) return players[i];
    return players.length > 0 ? players[0] : null;
  }
  readonly property bool hasTrack: player !== null && (player.trackTitle || "") !== ""
  readonly property bool playing: player ? player.isPlaying : false
  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string fullText: artist !== "" ? artist + " — " + title : title
  readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
  readonly property real length: player && player.length > 0 && player.length < 1e9 ? player.length : 0
  property real position: 0

  // ---------- геометрия: плашка стоит слева от часов waybar ----------
  property var now: new Date()
  Timer { interval: 30000; repeat: true; running: true; onTriggered: root.now = new Date() }
  TextMetrics {
    id: clockMetrics
    font.family: root.textFont
    font.pixelSize: 13
    font.bold: true
    font.letterSpacing: 1
    text: Qt.formatDateTime(root.now, "HH:mm") + "   " + root.now.toLocaleDateString(Qt.locale("en_US"), "dddd, dd MMMM")
  }
  readonly property real gap: 22
  property real screenW: 1920
  readonly property real pillRight: screenW / 2 - clockMetrics.advanceWidth / 2 - gap
  readonly property real pillLeft: pill.shown ? pillRight - pill.width : pillRight
  function under(w) {   // x для окна шириной w по центру под плашкой
    const c = pillRight - pill.width / 2;
    return Math.max(8, Math.min(screenW - w - 8, c - w / 2));
  }

  // Cassette во время игры отдаёт позицию 0, а настоящую — только на паузе.
  // Поэтому время считаем сами: от последней известной позиции + сколько прошло.
  property real basePos: 0
  property real baseTime: Date.now()
  function safePos() {
    const v = Number(root.player ? root.player.position : 0);
    return isFinite(v) && v >= 0 ? v : 0;
  }
  function anchor(p) { root.basePos = p; root.baseTime = Date.now(); root.position = p; }
  onPlayingChanged: {
    const p = root.safePos();
    anchor(p > 0 ? p : root.position);   // пауза/продолжение — с того же места
  }
  onTitleChanged: anchor(0)
  onPlayerChanged: anchor(root.safePos())
  Timer {
    interval: 250
    repeat: true
    running: root.player !== null
    onTriggered: {
      const reported = root.safePos();
      if (root.playing) {
        let pos = root.basePos + (Date.now() - root.baseTime) / 1000;
        // если плеер честно сообщает позицию и она сильно отличается — верим ему
        if (reported > 0 && Math.abs(reported - pos) > 2) { root.anchor(reported); return; }
        if (root.length > 0) pos = Math.min(pos, root.length);
        root.position = pos;
      } else if (reported > 0 && Math.abs(reported - root.position) > 0.5) {
        root.anchor(reported);
      }
    }
  }

  function fmt(sec) {
    if (!sec || sec < 0) return "0:00";
    const s = Math.floor(sec % 60);
    return Math.floor(sec / 60) + ":" + (s < 10 ? "0" : "") + s;
  }
  function next() { if (player) player.next(); }
  function prev() { if (player) player.previous(); }
  function toggle() { if (player) player.togglePlaying(); }

  IpcHandler {
    target: "music"
    function popup(): void { root.popupOpen = !root.popupOpen; }
    function togglebar(): void { root.barHidden = !root.barHidden; }
  }

  // ================= ИКОНКИ СПРАВА (StatusBar.qml) =================
  StatusBar {
    barHidden: root.barHidden
    topMargin: root.pillTop
  }

  // ================= КАЛЕНДАРЬ (Calendar.qml) =================
  Apps {
    barHidden: root.barHidden
    topMargin: root.pillTop
    rightLimit: root.pillLeft - 14
  }
  Calendar {
    topMargin: root.pillTop
  }

  // ================= ПЛАШКА =================
  PanelWindow {
    id: pillWin
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: root.pillTop
    implicitHeight: 24
    color: "transparent"
    mask: Region { item: pill }
    onWidthChanged: root.screenW = width
    Component.onCompleted: root.screenW = width
    visible: pill.opacity > 0.01
    WlrLayershell.namespace: "kellos-music-pill"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: pill
      readonly property bool shown: root.hasTrack && !root.barHidden
      x: root.pillRight - width
      height: 24
      width: Math.min(row.implicitWidth + 28, 260)
      radius: 8
      color: area.containsMouse ? Qt.rgba(0.706, 0.557, 0.98, 0.30) : Qt.rgba(0.706, 0.557, 0.98, 0.18)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, root.playing ? 0.40 : 0.18)
      opacity: shown ? 1 : 0
      scale: shown ? 1 : 0.85
      Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
      Behavior on scale   { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
      Behavior on width   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      Behavior on color   { ColorAnimation { duration: 150 } }

      Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        clip: false

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.playing ? "" : ""
          font.family: root.iconFont
          font.weight: Font.Black
          font.pixelSize: 11
          color: root.playing ? root.cPink : root.cDim
          Behavior on color { ColorAnimation { duration: 200 } }
        }

        Item {
          width: Math.min(label.implicitWidth, 200)
          height: 24
          clip: true
          Text {
            id: label
            property string shownText: ""
            width: Math.min(implicitWidth, 200)
            anchors.verticalCenter: parent.verticalCenter
            text: shownText
            elide: Text.ElideRight
            font.family: root.textFont
            font.pixelSize: 12
            color: root.playing ? root.cPink : root.cDim
            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }
      }

      // анимация смены трека: старый уезжает вверх, новый выезжает снизу
      SequentialAnimation {
        id: trackSwap
        ParallelAnimation {
          NumberAnimation { target: label; property: "opacity"; to: 0; duration: 140 }
          NumberAnimation { target: label; property: "anchors.verticalCenterOffset"; to: -10; duration: 140; easing.type: Easing.InCubic }
        }
        ScriptAction { script: label.shownText = root.fullText }
        PropertyAction { target: label; property: "anchors.verticalCenterOffset"; value: 10 }
        ParallelAnimation {
          NumberAnimation { target: label; property: "opacity"; to: 1; duration: 220 }
          NumberAnimation { target: label; property: "anchors.verticalCenterOffset"; to: 0; duration: 220; easing.type: Easing.OutCubic }
        }
      }
      Connections {
        target: root
        function onFullTextChanged() {
          if (label.shownText === "") label.shownText = root.fullText;
          else trackSwap.restart();
        }
      }
      Component.onCompleted: label.shownText = root.fullText

      MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => {
          if (m.button === Qt.LeftButton) root.toggle();
          else if (m.button === Qt.RightButton) root.next();
          else root.popupOpen = !root.popupOpen;
        }
        onContainsMouseChanged: containsMouse ? tipTimer.restart() : (tipTimer.stop(), root.tipOpen = false)
      }
      Timer { id: tipTimer; interval: 550; onTriggered: root.tipOpen = !root.popupOpen }

      // свайп двумя пальцами (горизонтальная прокрутка)
      WheelHandler {
        id: swipe
        property real acc: 0
        property bool cooldown: false
        onWheel: (e) => {
          if (cooldown || e.angleDelta.x === 0) return;
          acc += e.angleDelta.x * root.swipeDirection;
          if (acc <= -120) { root.next(); acc = 0; cooldown = true; cool.restart(); }
          else if (acc >= 120) { root.prev(); acc = 0; cooldown = true; cool.restart(); }
        }
      }
      Timer { id: cool; interval: 650; onTriggered: { swipe.cooldown = false; swipe.acc = 0; } }
    }
  }

  // ================= ПОДСКАЗКА =================
  PanelWindow {
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: root.pillTop + 30
    implicitHeight: 30
    color: "transparent"
    mask: Region { item: tip }
    visible: tip.opacity > 0.01
    WlrLayershell.namespace: "kellos-music-tip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: tip
      height: parent.height
      width: Math.min(tipText.implicitWidth + 24, 700)
      x: root.under(width)
      radius: 8
      color: Qt.rgba(0.102, 0.063, 0.157, 0.95)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.45)
      opacity: root.tipOpen && root.hasTrack ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      Text {
        id: tipText
        anchors.centerIn: parent
        text: root.fullText
        color: root.cText
        font.family: root.textFont
        font.pixelSize: 12
      }
    }
  }

  // ================= МИНИ-ПЛЕЕР =================
  Timer { id: hideTimer; interval: 700; onTriggered: root.popupOpen = false }
  Timer { id: graceTimer; interval: 4000; onTriggered: if (!popHover.hovered) root.popupOpen = false }
  onPopupOpenChanged: { if (popupOpen) { tipOpen = false; graceTimer.restart(); } }

  PanelWindow {
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: root.pillTop + 32
    implicitHeight: 156
    color: "transparent"
    mask: Region { item: card }
    visible: card.opacity > 0.01
    WlrLayershell.namespace: "kellos-music-player"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: card
      width: 420
      height: parent.height
      x: root.under(width)
      radius: 14
      color: Qt.rgba(0.086, 0.055, 0.141, 0.94)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.35)
      transformOrigin: Item.Top
      opacity: root.popupOpen && root.player ? 1 : 0
      scale: root.popupOpen ? 1 : 0.92
      y: root.popupOpen ? 0 : -8
      Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      Behavior on scale   { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
      Behavior on y       { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

      HoverHandler {
        id: popHover
        onHoveredChanged: hovered ? hideTimer.stop() : hideTimer.restart()
      }

      Row {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // обложка с плавной сменой
        Item {
          id: art
          width: 124
          height: 124
          anchors.verticalCenter: parent.verticalCenter
          property string src: ""

          Image {
            id: coverImg
            anchors.fill: parent
            source: art.src
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
          }
          Rectangle { id: coverMask; anchors.fill: parent; radius: 10; visible: false; layer.enabled: true }
          MultiEffect {
            id: coverFx
            anchors.fill: parent
            source: coverImg
            maskEnabled: true
            maskSource: coverMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            visible: coverImg.status === Image.Ready
          }
          Rectangle {
            anchors.fill: parent
            radius: 10
            color: root.cSurface
            visible: coverImg.status !== Image.Ready
            Text {
              anchors.centerIn: parent
              text: ""
              font.family: root.iconFont
              font.weight: Font.Black
              font.pixelSize: 34
              color: root.cMauve
            }
          }
          SequentialAnimation {
            id: artSwap
            NumberAnimation { target: art; property: "opacity"; to: 0; duration: 150 }
            ScriptAction { script: art.src = root.artUrl }
            NumberAnimation { target: art; property: "opacity"; to: 1; duration: 260 }
          }
          Connections {
            target: root
            function onArtUrlChanged() { art.src === "" ? (art.src = root.artUrl) : artSwap.restart(); }
          }
          Component.onCompleted: src = root.artUrl
        }

        Column {
          width: parent.width - art.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          Text {
            width: parent.width
            text: root.title
            color: root.cText
            font.family: root.textFont
            font.pixelSize: 15
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: root.artist
            color: root.cPink
            font.family: root.textFont
            font.pixelSize: 12
            elide: Text.ElideRight
          }

          // прогресс с перемоткой (клик или перетаскивание)
          Item {
            width: parent.width
            height: 16
            Rectangle {
              id: bar
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: seek.containsMouse || seek.pressed ? 6 : 4
              radius: height / 2
              color: root.cSurface
              Behavior on height { NumberAnimation { duration: 120 } }
              Rectangle {
                width: root.length > 0 ? parent.width * Math.min(1, root.position / root.length) : 0
                height: parent.height
                radius: height / 2
                color: root.cMauve
              }
            }
            MouseArea {
              id: seek
              anchors.fill: parent
              hoverEnabled: true
              enabled: root.player !== null && root.player.canSeek && root.length > 0
              cursorShape: Qt.PointingHandCursor
              function go(x) {
                const p = Math.max(0, Math.min(1, x / width)) * root.length;
                root.player.position = p;
                root.anchor(p);
              }
              onPressed: (m) => go(m.x)
              onPositionChanged: (m) => { if (pressed) go(m.x); }
            }
          }
          Row {
            width: parent.width
            Text { width: parent.width / 2; text: root.fmt(root.position); color: root.cDim; font.family: root.textFont; font.pixelSize: 10 }
            Text { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: root.length > 0 ? root.fmt(root.length) : "--:--"; color: root.cDim; font.family: root.textFont; font.pixelSize: 10 }
          }

          Row {
            spacing: 16
            anchors.horizontalCenter: parent.horizontalCenter
            Repeater {
              model: ["prev", "play", "next"]
              Rectangle {
                id: btnBg
                required property string modelData
                readonly property bool big: modelData === "play"
                width: big ? 38 : 30
                height: width
                radius: width / 2
                color: big ? root.cMauve : (btnArea.containsMouse ? Qt.rgba(0.706, 0.557, 0.98, 0.2) : "transparent")
                scale: btnArea.pressed ? 0.88 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }
                Text {
                  anchors.centerIn: parent
                  text: btnBg.modelData === "prev" ? "" : btnBg.modelData === "next" ? "" : (root.playing ? "" : "")
                  font.family: root.iconFont
                  font.weight: Font.Black
                  font.pixelSize: btnBg.big ? 14 : 12
                  color: btnBg.big ? root.cBase : root.cText
                }
                MouseArea {
                  id: btnArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: btnBg.modelData === "prev" ? root.prev() : btnBg.modelData === "next" ? root.next() : root.toggle()
                }
              }
            }
          }
        }
      }
    }
  }
}
