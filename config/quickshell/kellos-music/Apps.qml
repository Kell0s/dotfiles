// Kellos Apps — левая часть панели: рабочие столы │ открытые окна
//   окна не залезают на плашку музыки: что не влезло — в кнопку «+N» со списком
//   ЛКМ — перейти к окну · СКМ — закрыть · колёсико над столами — листать
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
  id: apps

  property bool barHidden: false
  property int topMargin: 4
  property real rightLimit: 600          // правая граница (левый край плашки музыки)

  readonly property color cBase: "#160e24"
  readonly property color cMauve: "#b48efa"
  readonly property color cLilac: "#c4a7ff"
  readonly property color cPink: "#f5a9e0"
  readonly property color cText: "#e0d4f5"
  readonly property color cDim: "#6b5a85"
  readonly property string iconFont: "Font Awesome 6 Free"
  readonly property string textFont: "JetBrains Mono"

  // ================= ДАННЫЕ ИЗ NIRI =================
  property var wsMap: ({})
  property var winMap: ({})
  property var workspaces: []
  property var windows: []
  property int focusedId: -1

  function rebuild() {
    const ws = Object.values(wsMap).sort((a, b) => (a.output || "").localeCompare(b.output || "") || a.idx - b.idx);
    workspaces = ws;
    const wsIdx = {};
    for (const w of ws) wsIdx[w.id] = w.idx;
    windows = Object.values(winMap).sort((a, b) => {
      const wa = wsIdx[a.workspace_id] || 0, wb = wsIdx[b.workspace_id] || 0;
      if (wa !== wb) return wa - wb;
      const pa = a.layout && a.layout.pos_in_scrolling_layout ? a.layout.pos_in_scrolling_layout[0] : 0;
      const pb = b.layout && b.layout.pos_in_scrolling_layout ? b.layout.pos_in_scrolling_layout[0] : 0;
      return pa - pb || a.id - b.id;
    });
  }

  function handle(ev) {
    if (ev.WorkspacesChanged) {
      const m = {};
      for (const w of ev.WorkspacesChanged.workspaces) m[w.id] = w;
      wsMap = m;
    } else if (ev.WorkspaceActivated) {
      const id = ev.WorkspaceActivated.id, out = wsMap[id] ? wsMap[id].output : null;
      const m = Object.assign({}, wsMap);
      for (const k in m) {
        if (m[k].output === out) m[k] = Object.assign({}, m[k], { is_active: m[k].id === id });
        if (ev.WorkspaceActivated.focused) m[k] = Object.assign({}, m[k], { is_focused: m[k].id === id });
      }
      wsMap = m;
    } else if (ev.WindowsChanged) {
      const m = {};
      for (const w of ev.WindowsChanged.windows) { m[w.id] = w; if (w.is_focused) focusedId = w.id; }
      winMap = m;
    } else if (ev.WindowOpenedOrChanged) {
      const w = ev.WindowOpenedOrChanged.window;
      const m = Object.assign({}, winMap); m[w.id] = w; winMap = m;
      if (w.is_focused) focusedId = w.id;
    } else if (ev.WindowClosed) {
      const m = Object.assign({}, winMap); delete m[ev.WindowClosed.id]; winMap = m;
    } else if (ev.WindowFocusChanged) {
      focusedId = ev.WindowFocusChanged.id === null ? -1 : ev.WindowFocusChanged.id;
    } else if (ev.WindowLayoutsChanged) {
      const m = Object.assign({}, winMap);
      for (const pair of ev.WindowLayoutsChanged.changes) {
        if (m[pair[0]]) m[pair[0]] = Object.assign({}, m[pair[0]], { layout: pair[1] });
      }
      winMap = m;
    } else return;
    rebuild();
  }

  Process {
    id: stream
    running: true
    command: ["niri", "msg", "--json", "event-stream"]
    stdout: SplitParser {
      onRead: (line) => { try { apps.handle(JSON.parse(line)); } catch (e) {} }
    }
    onExited: restart.start()
  }
  Timer { id: restart; interval: 2000; onTriggered: stream.running = true }

  function niri(args) { Quickshell.execDetached(["niri", "msg", "action"].concat(args)); }

  // иконка окна: .desktop-файл → тема иконок → запасная
  function iconFor(appId) {
    let name = appId || "";
    if (/^brave-.*music\.yandex/.test(name)) return Quickshell.iconPath("yandex-music", "brave-browser");
    if (/^brave-/.test(name) && name !== "brave-browser") name = "brave-browser";
    let e = null;
    try {
      e = typeof DesktopEntries.heuristicLookup === "function" ? DesktopEntries.heuristicLookup(name) : DesktopEntries.byId(name);
    } catch (err) {}
    const icon = e && e.icon ? e.icon : name;
    return Quickshell.iconPath(icon, "application-x-executable");
  }

  // ================= СКОЛЬКО ОКОН ВЛЕЗАЕТ =================
  readonly property int cellW: 30
  readonly property real appsX: wsRow.width + 22         // после столов и разделителя
  readonly property int capacity: Math.max(1, Math.floor((rightLimit - appsX - 8) / cellW))
  readonly property bool overflow: windows.length > capacity
  readonly property var shown: {
    if (!overflow) return windows;
    const n = capacity - 1;                                 // одно место под «+N»
    let list = windows.slice(0, n);
    const f = windows.find(w => w.id === focusedId);
    if (f && !list.some(w => w.id === f.id) && n > 0) list = list.slice(0, n - 1).concat([f]);
    return list;
  }
  readonly property var hidden: windows.filter(w => !shown.some(s => s.id === w.id))

  // подсказка
  property string tipText: ""
  property real tipX: 0
  property bool tipOpen: false
  Timer { id: tipDelay; interval: 350; onTriggered: apps.tipOpen = !apps.moreOpen }

  property bool moreOpen: false
  Timer { id: moreHide; interval: 600; onTriggered: apps.moreOpen = false }

  // ================= ПОЛОСА =================
  PanelWindow {
    id: bar
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: apps.topMargin
    implicitHeight: 24
    color: "transparent"
    mask: Region { item: strip }
    visible: strip.opacity > 0.01
    WlrLayershell.namespace: "kellos-apps"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Item {
      id: strip
      x: 8
      height: 24
      width: apps.appsX + appsRow.width
      opacity: apps.barHidden ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 220 } }

      // ---------- рабочие столы ----------
      Row {
        id: wsRow
        height: 24
        spacing: 3
        Repeater {
          model: apps.workspaces
          Rectangle {
            id: wsBtn
            required property var modelData
            readonly property bool active: modelData.is_active
            readonly property bool hasWin: apps.windows.some(w => w.workspace_id === modelData.id)
            width: active ? 30 : 22
            height: 22
            anchors.verticalCenter: parent.verticalCenter
            radius: 7
            color: active ? apps.cMauve : wsMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : "transparent"
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 180 } }
            Text {
              anchors.centerIn: parent
              text: wsBtn.modelData.name || wsBtn.modelData.idx
              font.family: apps.textFont; font.pixelSize: 11; font.bold: wsBtn.active
              color: wsBtn.active ? apps.cBase : wsBtn.hasWin ? apps.cText : apps.cDim
            }
            MouseArea {
              id: wsMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: apps.niri(["focus-workspace", String(wsBtn.modelData.idx)])
              onWheel: (w) => apps.niri([w.angleDelta.y > 0 ? "focus-workspace-up" : "focus-workspace-down"])
            }
          }
        }
      }

      // разделитель
      Rectangle {
        x: wsRow.width + 10
        anchors.verticalCenter: parent.verticalCenter
        width: 1; height: 14
        color: Qt.rgba(0.769, 0.655, 1.0, 0.28)
      }

      // ---------- окна ----------
      Row {
        id: appsRow
        x: apps.appsX
        height: 24
        spacing: 0
        Repeater {
          model: apps.shown
          Item {
            id: win
            required property var modelData
            readonly property bool focused: modelData.id === apps.focusedId
            width: apps.cellW
            height: 24
            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              radius: 7
              color: win.focused ? Qt.rgba(0.706, 0.557, 0.98, 0.22)
                     : winMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.14) : "transparent"
              Behavior on color { ColorAnimation { duration: 160 } }
            }
            IconImage {
              anchors.centerIn: parent
              implicitSize: 16
              source: apps.iconFor(win.modelData.app_id)
              opacity: win.focused || winMa.containsMouse ? 1 : 0.75
              Behavior on opacity { NumberAnimation { duration: 160 } }
            }
            Rectangle {      // точка под активным
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              width: win.focused ? 10 : 0; height: 2; radius: 1
              color: apps.cPink
              Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
            MouseArea {
              id: winMa
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton
              cursorShape: Qt.PointingHandCursor
              onClicked: (m) => {
                apps.tipOpen = false;
                if (m.button === Qt.MiddleButton) apps.niri(["close-window", "--id", String(win.modelData.id)]);
                else apps.niri(["focus-window", "--id", String(win.modelData.id)]);
              }
              onContainsMouseChanged: {
                if (containsMouse) {
                  apps.tipX = strip.x + appsRow.x + win.x + win.width / 2;
                  apps.tipText = win.modelData.title || win.modelData.app_id || "";
                  if (!apps.tipOpen) tipDelay.restart();
                } else { tipDelay.stop(); apps.tipOpen = false; }
              }
            }
          }
        }

        // ---------- «+N» ----------
        Rectangle {
          id: moreBtn
          visible: apps.overflow
          width: moreText.implicitWidth + 14
          height: 22
          anchors.verticalCenter: parent.verticalCenter
          radius: 7
          color: apps.moreOpen ? Qt.rgba(0.706, 0.557, 0.98, 0.3) : moreMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : Qt.rgba(0.769, 0.655, 1.0, 0.08)
          Behavior on color { ColorAnimation { duration: 160 } }
          Text {
            id: moreText
            anchors.centerIn: parent
            text: "+" + apps.hidden.length
            font.family: apps.textFont; font.pixelSize: 11; font.bold: true
            color: apps.moreOpen ? apps.cPink : apps.cLilac
          }
          MouseArea {
            id: moreMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { apps.tipOpen = false; apps.moreOpen = !apps.moreOpen; }
            onContainsMouseChanged: containsMouse ? moreHide.stop() : (apps.moreOpen ? moreHide.restart() : null)
          }
        }
      }
    }
  }

  // ================= СПИСОК СКРЫТЫХ ОКОН =================
  PanelWindow {
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: apps.topMargin + 30
    implicitHeight: 480
    color: "transparent"
    visible: more.opacity > 0.01
    mask: Region { item: more }
    WlrLayershell.namespace: "kellos-apps-more"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: more
      x: Math.max(8, strip.x + apps.appsX + appsRow.width - width)
      width: 280
      height: moreCol.implicitHeight + 12
      radius: 14
      color: Qt.rgba(0.086, 0.055, 0.141, 0.96)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.35)
      transformOrigin: Item.Top
      opacity: apps.moreOpen && apps.overflow ? 1 : 0
      scale: apps.moreOpen ? 1 : 0.94
      y: apps.moreOpen ? 0 : -6
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
      Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      HoverHandler { onHoveredChanged: hovered ? moreHide.stop() : moreHide.restart() }

      Column {
        id: moreCol
        x: 6; y: 6
        width: parent.width - 12
        Repeater {
          model: apps.hidden
          Rectangle {
            id: hw
            required property var modelData
            width: moreCol.width
            height: 32
            radius: 8
            color: hwMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.16) : "transparent"
            Behavior on color { ColorAnimation { duration: 140 } }
            IconImage {
              x: 10
              anchors.verticalCenter: parent.verticalCenter
              implicitSize: 16
              source: apps.iconFor(hw.modelData.app_id)
            }
            Text {
              x: 36
              width: parent.width - 46
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: hw.modelData.title || hw.modelData.app_id
              font.family: apps.textFont; font.pixelSize: 11
              color: apps.cText
            }
            MouseArea {
              id: hwMa
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton
              cursorShape: Qt.PointingHandCursor
              onClicked: (m) => {
                if (m.button === Qt.MiddleButton) apps.niri(["close-window", "--id", String(hw.modelData.id)]);
                else { apps.moreOpen = false; apps.niri(["focus-window", "--id", String(hw.modelData.id)]); }
              }
            }
          }
        }
      }
    }
  }

  // ================= ПОДСКАЗКА =================
  PanelWindow {
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: apps.topMargin + 28
    implicitHeight: 34
    color: "transparent"
    visible: tip.opacity > 0.01
    mask: Region {}
    WlrLayershell.namespace: "kellos-apps-tip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: tip
      width: Math.min(tipLabel.implicitWidth + 20, 420)
      height: 26
      x: Math.max(8, apps.tipX - width / 2)
      radius: 8
      color: Qt.rgba(0.086, 0.055, 0.141, 0.96)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.3)
      opacity: apps.tipOpen ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }
      Text {
        id: tipLabel
        anchors.centerIn: parent
        width: Math.min(implicitWidth, 400)
        elide: Text.ElideRight
        text: apps.tipText
        font.family: apps.textFont; font.pixelSize: 11
        color: apps.cText
      }
    }
  }
}
