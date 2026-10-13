// Kellos Status — иконки справа на панели с плавными подсказками
//   нагрузка CPU/RAM · раскладка · звук · сеть · яркость · батарея
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Niri
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Scope {
  id: sb

  property bool barHidden: false
  property int topMargin: 4

  // ---------- палитра ----------
  readonly property color cBase: "#160e24"
  readonly property color cMauve: "#b48efa"
  readonly property color cLilac: "#c4a7ff"
  readonly property color cPink: "#f5a9e0"
  readonly property color cText: "#e0d4f5"
  readonly property color cDim: "#6b5a85"
  readonly property color cGreen: "#a6e3a1"
  readonly property color cYellow: "#f9e2af"
  readonly property color cRed: "#f38ba8"
  readonly property string iconFont: "Font Awesome 6 Free"
  readonly property string textFont: "JetBrains Mono"

  function run(cmd) { Quickshell.execDetached(cmd); }

  // ================= ДАННЫЕ =================

  // --- CPU ---
  property real cpu: 0
  property var cpuPrev: null
  FileView {
    id: statFile
    path: "/proc/stat"
    onLoaded: {
      const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
      const idle = f[3] + (f[4] || 0);
      const total = f.reduce((a, b) => a + b, 0);
      if (sb.cpuPrev) {
        const dt = total - sb.cpuPrev.total, di = idle - sb.cpuPrev.idle;
        if (dt > 0) sb.cpu = Math.round(100 * (1 - di / dt));
      }
      sb.cpuPrev = { total: total, idle: idle };
    }
  }

  // --- RAM ---
  property real memUsed: 0
  property real memTotal: 1
  property real swapUsed: 0
  property real swapTotal: 0
  readonly property int memPct: Math.round(100 * memUsed / Math.max(1, memTotal))
  FileView {
    id: memFile
    path: "/proc/meminfo"
    onLoaded: {
      const m = {};
      text().split("\n").forEach(l => { const p = l.split(/:\s+/); if (p.length > 1) m[p[0]] = parseInt(p[1]); });
      sb.memTotal = (m.MemTotal || 1) / 1048576;
      sb.memUsed = ((m.MemTotal || 0) - (m.MemAvailable || 0)) / 1048576;
      sb.swapTotal = (m.SwapTotal || 0) / 1048576;
      sb.swapUsed = ((m.SwapTotal || 0) - (m.SwapFree || 0)) / 1048576;
    }
  }
  Timer {
    interval: 2000; repeat: true; running: true; triggeredOnStart: true
    onTriggered: { statFile.reload(); memFile.reload(); }
  }

  // --- раскладка (Niri) ---
  readonly property string layoutName: Niri.currentKeyboardLayoutName || ""
  readonly property string layoutShort: {
    const n = layoutName.toLowerCase();
    if (n.startsWith("russian")) return "RU";
    if (n.startsWith("english")) return "EN";
    return n ? n.slice(0, 2).toUpperCase() : "EN";
  }

  // --- звук ---
  readonly property var sink: Pipewire.ready ? Pipewire.defaultAudioSink : null
  PwObjectTracker { objects: sb.sink ? [sb.sink] : [] }
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  function setVolume(v) { if (sink && sink.audio) sink.audio.volume = Math.max(0, Math.min(1, v)); }

  // --- сеть ---
  property string netType: "none"     // wifi / ethernet / none
  property string ssid: ""
  property int signal: 0
  Process {
    id: netProc
    command: ["sh", "-c", "nmcli -t -f TYPE,STATE,CONNECTION dev 2>/dev/null; echo ---; nmcli -t -f IN-USE,SIGNAL,SSID dev wifi list --rescan no 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.split("---");
        const devs = (parts[0] || "").split("\n");
        let type = "none", name = "";
        for (const l of devs) {
          const f = l.split(":");
          if (f[1] === "connected" && f[0] === "ethernet") { type = "ethernet"; name = f.slice(2).join(":"); break; }
          if (f[1] === "connected" && f[0] === "wifi") { type = "wifi"; name = f.slice(2).join(":"); }
        }
        let sig = 0;
        for (const l of (parts[1] || "").split("\n")) {
          if (l.startsWith("*:")) { const f = l.split(":"); sig = parseInt(f[1]) || 0; name = f.slice(2).join(":") || name; }
        }
        sb.netType = type; sb.ssid = name; sb.signal = sig;
      }
    }
  }
  Timer { interval: 5000; repeat: true; running: true; triggeredOnStart: true; onTriggered: netProc.running = true }

  // --- bluetooth ---
  property bool btAvail: false
  property bool btOn: false
  property var btDevs: []        // подключённые устройства
  Process {
    id: btProc
    command: ["sh", "-c", "bluetoothctl show 2>/dev/null | grep -E 'Powered:'; echo ---; bluetoothctl devices Connected 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.split("---");
        sb.btAvail = (parts[0] || "").indexOf("Powered") >= 0;
        sb.btOn = (parts[0] || "").indexOf("yes") >= 0;
        const devs = [];
        for (const l of (parts[1] || "").split("\n")) {
          const m = l.match(/^Device\s+\S+\s+(.+)$/);
          if (m) devs.push(m[1]);
        }
        sb.btDevs = devs;
      }
    }
  }
  Timer { interval: 5000; repeat: true; running: true; triggeredOnStart: true; onTriggered: btProc.running = true }

  // --- яркость ---
  property string blDev: ""
  property real blMax: 1
  property real blCur: 0
  readonly property int brightness: Math.round(100 * blCur / Math.max(1, blMax))
  Process {
    command: ["sh", "-c", "ls /sys/class/backlight | head -1"]
    running: true
    stdout: StdioCollector { onStreamFinished: sb.blDev = text.trim() }
  }
  FileView {
    path: sb.blDev ? "/sys/class/backlight/" + sb.blDev + "/max_brightness" : ""
    onLoaded: sb.blMax = parseInt(text()) || 1
  }
  FileView {
    id: blFile
    path: sb.blDev ? "/sys/class/backlight/" + sb.blDev + "/brightness" : ""
    watchChanges: true
    onLoaded: sb.blCur = parseInt(text()) || 0
    onFileChanged: reload()
  }
  function setBrightness(delta) {
    run(["brightnessctl", "set", delta > 0 ? "+5%" : "5%-"]);
    Qt.callLater(() => blFile.reload());
  }

  // --- батарея ---
  readonly property var bat: UPower.displayDevice
  readonly property bool hasBat: bat && bat.isPresent
  readonly property int batPct: hasBat ? Math.round((bat.percentage || 0) * 100) : 0
  readonly property bool charging: hasBat && bat.state === UPowerDeviceState.Charging
  readonly property bool plugged: hasBat && (bat.state === UPowerDeviceState.FullyCharged || bat.state === UPowerDeviceState.PendingCharge)
  function dur(sec) {
    if (!sec || sec <= 0) return "";
    const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
    return h > 0 ? h + " ч " + m + " мин" : m + " мин";
  }

  // ---------- история нагрузки для графиков (последние 60 замеров) ----------
  property var cpuHist: []
  property var memHist: []
  onCpuChanged: { const a = cpuHist.slice(-59); a.push(cpu); cpuHist = a; }
  onMemPctChanged: { const a = memHist.slice(-59); a.push(memPct); memHist = a; }

  // ================= ИКОНКИ =================
  // слева: раскладка, сеть, звук, яркость | справа: память, процессор, батарея
  property bool trayOpen: false
  readonly property var keys: ["lang", "net", "bt", "vol", "bl", "sep", "mem", "cpu", "bat", "sep2", "power"]

  function level(p, warn, crit) { return p >= crit ? cRed : p >= warn ? cYellow : cLilac; }

  function info(key) {
    switch (key) {
    case "cpu":
      return { icon: "", color: level(cpu, 60, 85), load: cpu,
               tip: "Процессор: " + cpu + "%\nКлик — подробности" };
    case "mem":
      return { icon: "", color: level(memPct, 70, 90), load: memPct,
               tip: "Память: " + memUsed.toFixed(1) + " / " + memTotal.toFixed(1) + " ГБ (" + memPct + "%)"
                    + (swapTotal > 0 ? "\nПодкачка: " + swapUsed.toFixed(1) + " / " + swapTotal.toFixed(1) + " ГБ" : "")
                    + "\nКлик — подробности" };
    case "lang":
      return { text: layoutShort, color: cPink, tip: (layoutName || "Раскладка") + "\nКлик — переключить" };
    case "vol":
      return { icon: muted || volume <= 0.001 ? "" : volume < 0.34 ? "" : volume < 0.67 ? "" : "",
               color: muted ? cDim : cLilac,
               tip: (muted ? "Звук выключен" : "Громкость: " + Math.round(volume * 100) + "%")
                    + (sink && sink.description ? "\n" + sink.description : "")
                    + "\nКолёсико — громкость · ПКМ — без звука" };
    case "net":
      return { icon: netType === "ethernet" ? "" : netType === "wifi" ? "" : "",
               color: netType === "none" ? cDim : cLilac,
               tip: (netType === "wifi" ? ssid + "\nСигнал: " + signal + "%"
                    : netType === "ethernet" ? "Кабель: " + ssid : "Нет подключения") + "\nКлик — сети · ПКМ — настройки" };
    case "bl":
      return { icon: "", color: cLilac, tip: "Яркость: " + brightness + "%\nКолёсико — изменить", hidden: blDev === "" };
    case "bat":
      return { icon: charging ? "" : plugged ? ""
                     : batPct > 90 ? "" : batPct > 65 ? "" : batPct > 40 ? "" : batPct > 15 ? "" : "",
               color: (charging || plugged) ? cGreen : batPct <= 10 ? cRed : batPct <= 25 ? cYellow : cLilac,
               tip: (charging ? "Заряжается: " : plugged ? "Подключено: " : "Батарея: ") + batPct + "%"
                    + (charging && bat.timeToFull > 0 ? "\nДо полной: " + dur(bat.timeToFull) : "")
                    + (hasBat && !charging && !plugged && bat.timeToEmpty > 0 ? "\nОсталось: " + dur(bat.timeToEmpty) : ""),
               hidden: !hasBat };
    case "bt":
      return { icon: "\uf294", font: "Font Awesome 6 Brands",
               color: !btOn ? cDim : btDevs.length > 0 ? cPink : cLilac,
               tip: !btOn ? "Bluetooth выключен\nКлик — устройства · ПКМ — включить"
                    : (btDevs.length > 0 ? btDevs.join("\n") : "Bluetooth: нет подключений")
                      + "\nКлик — устройства · ПКМ — выключить",
               hidden: !btAvail };
    case "power":
      return { icon: "\uf011", color: powerOpen ? cPink : cLilac, tip: "Питание" };
    }
    return { icon: "", color: cLilac, tip: "" };
  }

  function handleClick(key, button) {
    if (key === "cpu" || key === "mem") { sb.powerOpen = false; sb.wifiOpen = false; sb.btOpen = false; sb.monOpen = !sb.monOpen; }
    else if (key === "bt") {
      if (button === Qt.RightButton) {
        run(["bluetoothctl", "power", btOn ? "off" : "on"]);
        btOn = !btOn;
        btRefresh.restart();
      } else {
        sb.monOpen = false; sb.powerOpen = false; sb.wifiOpen = false;
        sb.btX = sb.tipCenter;
        sb.btOpen = !sb.btOpen;
      }
    }
    else if (key === "power") { sb.monOpen = false; sb.wifiOpen = false; sb.btOpen = false; sb.powerOpen = !sb.powerOpen; }
    else if (key === "lang") run(["niri", "msg", "action", "switch-layout", "next"]);
    else if (key === "vol") {
      if (button === Qt.RightButton) { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; }
      else run(["pavucontrol"]);
    }
    else if (key === "net") {
      if (button === Qt.RightButton) { run(["nm-connection-editor"]); return; }
      sb.monOpen = false; sb.powerOpen = false; sb.btOpen = false;
      sb.wifiX = sb.tipCenter;
      sb.wifiOpen = !sb.wifiOpen;
    }
  }
  function handleWheel(key, dy) {
    if (key === "vol") setVolume(volume + (dy > 0 ? 0.05 : -0.05));
    else if (key === "bl") setBrightness(dy);
  }

  Timer { id: btRefresh; interval: 1500; onTriggered: btProc.running = true }

  // подсказка
  property string tipText: ""
  property real tipCenter: 0
  property bool tipOpen: false
  Timer { id: tipDelay; interval: 350; onTriggered: sb.tipOpen = !sb.monOpen && !sb.powerOpen && !sb.wifiOpen && !sb.btOpen }

  // ================= ОКНО ИКОНОК =================
  PanelWindow {
    id: iconsWin
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: sb.topMargin
    implicitHeight: 24
    color: "transparent"
    mask: Region { item: row }
    visible: row.opacity > 0.01
    WlrLayershell.namespace: "kellos-status"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Row {
      id: row
      x: iconsWin.width - width - 10
      height: 24
      spacing: 2
      opacity: sb.barHidden ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 220 } }

      // ---------- трей: стрелочка + выезжающие иконки ----------
      Item {
        id: trayArrow
        width: 26
        height: 24
        Rectangle {
          anchors.fill: parent
          radius: 8
          color: arrowMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : "transparent"
          Behavior on color { ColorAnimation { duration: 180 } }
        }
        Text {
          anchors.centerIn: parent
          text: "\uf053"
          rotation: sb.trayOpen ? 180 : 0
          Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
          font.family: sb.iconFont
          font.weight: Font.Black
          font.pixelSize: 10
          color: arrowMa.containsMouse || sb.trayOpen ? sb.cPink : sb.cDim
          Behavior on color { ColorAnimation { duration: 180 } }
        }
        MouseArea {
          id: arrowMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { sb.tipOpen = false; sb.trayOpen = !sb.trayOpen; }
        }
      }

      Item {
        id: trayClip
        height: 24
        width: sb.trayOpen ? trayRow.implicitWidth + 4 : 0
        Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        clip: true
        opacity: sb.trayOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }

        Row {
          id: trayRow
          x: 4
          height: 24
          spacing: 2
          Repeater {
            model: SystemTray.items
            Item {
              id: tItem
              required property var modelData
              width: 28
              height: 24
              Rectangle {
                anchors.fill: parent
                radius: 8
                color: tMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : "transparent"
                Behavior on color { ColorAnimation { duration: 180 } }
                scale: tMa.pressed ? 0.9 : 1
                Behavior on scale { NumberAnimation { duration: 90 } }
              }
              IconImage {
                anchors.centerIn: parent
                implicitSize: 16
                source: tItem.modelData.icon
              }
              MouseArea {
                id: tMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (m) => {
                  sb.tipOpen = false;
                  const it = tItem.modelData;
                  const cx = tItem.mapToItem(null, tItem.width / 2, 0).x;
                  if (m.button === Qt.MiddleButton) it.secondaryActivate();
                  else if (m.button === Qt.RightButton || it.onlyMenu) {
                    if (it.hasMenu) sb.openTrayMenu(it, cx);
                    else it.secondaryActivate();
                  } else it.activate();
                }
                onWheel: (w) => tItem.modelData.scroll(w.angleDelta.y, false)
                onContainsMouseChanged: {
                  if (containsMouse) {
                    sb.tipCenter = tItem.mapToItem(null, tItem.width / 2, 0).x;
                    sb.tipText = tItem.modelData.tooltipTitle || tItem.modelData.title || tItem.modelData.id;
                    if (sb.tipOpen) return;
                    tipDelay.restart();
                  } else {
                    tipDelay.stop();
                    sb.tipOpen = false;
                  }
                }
              }
            }
          }
        }
      }

      Item {
        width: 13
        height: 24
        Rectangle { anchors.centerIn: parent; width: 1; height: 14; color: Qt.rgba(0.769, 0.655, 1.0, 0.28) }
      }

      Repeater {
        model: sb.keys
        Item {
          id: cell
          required property string modelData
          readonly property bool isSep: modelData.startsWith("sep")
          readonly property var info: isSep ? ({}) : sb.info(modelData)
          readonly property bool hasLoad: info.load !== undefined
          visible: !info.hidden
          height: 24
          width: isSep ? 13 : Math.max(30, label.implicitWidth + 18 + (hasLoad ? 8 : 0))

          // разделитель
          Rectangle {
            visible: cell.isSep
            anchors.centerIn: parent
            width: 1
            height: 14
            color: Qt.rgba(0.769, 0.655, 1.0, 0.28)
          }

          Rectangle {
            visible: !cell.isSep
            anchors.fill: parent
            radius: 8
            color: ma.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : "transparent"
            Behavior on color { ColorAnimation { duration: 180 } }
            scale: ma.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }

            Row {
              anchors.centerIn: parent
              spacing: 5

              // вертикальная полоска нагрузки
              Item {
                visible: cell.hasLoad
                width: 4
                height: 14
                anchors.verticalCenter: parent.verticalCenter
                Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(0.769, 0.655, 1.0, 0.15) }
                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: Math.max(2, parent.height * Math.min(100, cell.info.load || 0) / 100)
                  radius: 2
                  color: cell.info.color
                  Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                  Behavior on color { ColorAnimation { duration: 300 } }
                }
              }

              Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: cell.isSep ? "" : (cell.info.text !== undefined ? cell.info.text : cell.info.icon)
                font.family: cell.info.text !== undefined ? sb.textFont : (cell.info.font || sb.iconFont)
                font.weight: cell.info.text !== undefined ? Font.Bold : cell.info.font ? Font.Normal : Font.Black
                font.pixelSize: cell.info.text !== undefined ? 12 : 13
                color: ma.containsMouse ? sb.cText : (cell.info.color || sb.cLilac)
                Behavior on color { ColorAnimation { duration: 200 } }
              }
            }
          }

          MouseArea {
            id: ma
            enabled: !cell.isSep
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (m) => { sb.tipOpen = false; sb.handleClick(cell.modelData, m.button); }
            onWheel: (w) => sb.handleWheel(cell.modelData, w.angleDelta.y)
            onContainsMouseChanged: {
              if (containsMouse) {
                sb.tipCenter = row.x + cell.x + cell.width / 2;
                sb.tipText = Qt.binding(() => cell.info.tip || "");
                if (sb.tipOpen) return;
                tipDelay.restart();
              } else {
                tipDelay.stop();
                sb.tipOpen = false;
              }
            }
          }
        }
      }
    }
  }

  // ================= МЕНЮ ТРЕЯ (ПКМ) =================
  property var menuItem: null
  property real menuX: 0
  property bool menuOpen: false
  property var menuStack: []
  function openTrayMenu(item, x) {
    menuStack = [];
    menuOpener.menu = item.menu;
    menuItem = item;
    menuX = x;
    menuOpen = true;
    menuHide.stop();
    menuGrace.restart();
  }
  function closeMenu() { menuOpen = false; }
  function cleanText(t) { return (t || "").replace(/&&/g, "\u0001").replace(/[&_]/g, "").replace(/\u0001/g, "&"); }

  QsMenuOpener { id: menuOpener }
  Timer { id: menuHide; interval: 700; onTriggered: sb.menuOpen = false }
  Timer { id: menuGrace; interval: 4000; onTriggered: if (!menuHover.hovered) sb.menuOpen = false }

  PanelWindow {
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: sb.topMargin + 28
    implicitHeight: 600
    color: "transparent"
    visible: menuCard.opacity > 0.01
    mask: Region { item: menuCard }
    WlrLayershell.namespace: "kellos-traymenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: menuCard
      width: Math.max(180, menuCol.implicitWidth + 12)
      height: menuCol.implicitHeight + 12
      x: Math.max(8, Math.min(parent.width - width - 8, sb.menuX - width / 2))
      radius: 12
      color: Qt.rgba(0.086, 0.055, 0.141, 0.96)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.35)
      transformOrigin: Item.Top
      opacity: sb.menuOpen ? 1 : 0
      scale: sb.menuOpen ? 1 : 0.94
      y: sb.menuOpen ? 0 : -6
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
      Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      HoverHandler {
        id: menuHover
        onHoveredChanged: hovered ? menuHide.stop() : menuHide.restart()
      }

      Column {
        id: menuCol
        x: 6; y: 6
        width: parent.width - 12

        // назад из подменю
        Rectangle {
          visible: sb.menuStack.length > 0
          width: parent.width
          height: 28
          radius: 7
          color: backMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : "transparent"
          Text {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            text: "\uf053   Назад"
            font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 11
            color: sb.cDim
          }
          MouseArea {
            id: backMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              const st = sb.menuStack.slice();
              menuOpener.menu = st.pop();
              sb.menuStack = st;
            }
          }
        }

        Repeater {
          model: menuOpener.children
          Item {
            id: entry
            required property var modelData
            width: menuCol.width
            height: modelData.isSeparator ? 9 : 28

            Rectangle {
              visible: entry.modelData.isSeparator
              anchors.centerIn: parent
              width: parent.width - 12
              height: 1
              color: Qt.rgba(0.769, 0.655, 1.0, 0.2)
            }

            Rectangle {
              visible: !entry.modelData.isSeparator
              anchors.fill: parent
              radius: 7
              color: entryMa.containsMouse && entry.modelData.enabled ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : "transparent"
              Behavior on color { ColorAnimation { duration: 140 } }

              Row {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                // галочка/кружок для переключателей
                Text {
                  visible: entry.modelData.buttonType !== QsMenuButtonType.None
                  anchors.verticalCenter: parent.verticalCenter
                  width: 12
                  text: entry.modelData.checkState === Qt.Checked
                        ? (entry.modelData.buttonType === QsMenuButtonType.RadioButton ? "\uf192" : "\uf00c") : ""
                  font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 10
                  color: sb.cPink
                }
                IconImage {
                  visible: (entry.modelData.icon || "") !== ""
                  anchors.verticalCenter: parent.verticalCenter
                  implicitSize: 14
                  source: entry.modelData.icon || ""
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: sb.cleanText(entry.modelData.text)
                  font.family: sb.textFont
                  font.pixelSize: 12
                  color: entry.modelData.enabled ? sb.cText : sb.cDim
                }
              }
              Text {
                visible: entry.modelData.hasChildren
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf054"
                font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 9
                color: sb.cDim
              }
              MouseArea {
                id: entryMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: entry.modelData.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  const e = entry.modelData;
                  if (e.hasChildren) {
                    const st = sb.menuStack.slice();
                    st.push(menuOpener.menu);
                    sb.menuStack = st;
                    menuOpener.menu = e;
                  } else {
                    e.triggered();
                    sb.menuOpen = false;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // ================= МЕНЮ ПИТАНИЯ =================
  property bool powerOpen: false
  property string armed: ""      // "reboot"/"poweroff" — ждём второго клика
  onPowerOpenChanged: { armed = ""; if (powerOpen) { powerGrace.restart(); tipOpen = false; } }
  Timer { id: powerHide; interval: 700; onTriggered: sb.powerOpen = false }
  Timer { id: powerGrace; interval: 4000; onTriggered: if (!powerHover.hovered) sb.powerOpen = false }
  Timer { id: disarm; interval: 3000; onTriggered: sb.armed = "" }
  function powerAction(a) {
    if (a === "suspend") {
      powerOpen = false;
      run(["sh", "-c", "swaylock -f; systemctl suspend"]);
      return;
    }
    if (armed !== a) { armed = a; disarm.restart(); return; }
    powerOpen = false;
    run(["systemctl", a]);
  }

  PanelWindow {
    anchors.top: true
    anchors.right: true
    margins.top: sb.topMargin + 30
    margins.right: 8
    implicitWidth: 210
    implicitHeight: 140
    color: "transparent"
    visible: pw.opacity > 0.01
    mask: Region { item: pw }
    WlrLayershell.namespace: "kellos-power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: pw
      width: parent.width
      height: pwCol.implicitHeight + 12
      radius: 14
      color: Qt.rgba(0.086, 0.055, 0.141, 0.96)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.35)
      transformOrigin: Item.TopRight
      opacity: sb.powerOpen ? 1 : 0
      scale: sb.powerOpen ? 1 : 0.92
      y: sb.powerOpen ? 0 : -8
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
      Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

      HoverHandler {
        id: powerHover
        onHoveredChanged: hovered ? powerHide.stop() : powerHide.restart()
      }

      Column {
        id: pwCol
        x: 6; y: 6
        width: parent.width - 12
        spacing: 2
        Repeater {
          model: [
            { a: "suspend",  icon: "\uf186", t: "Спящий режим",  c: "#c4a7ff" },
            { a: "reboot",   icon: "\uf2f9", t: "Перезагрузка",  c: "#f9e2af" },
            { a: "poweroff", icon: "\uf011", t: "Выключение",    c: "#f38ba8" }
          ]
          Rectangle {
            id: pbtn
            required property var modelData
            readonly property bool isArmed: sb.armed === modelData.a
            width: pwCol.width
            height: 36
            radius: 9
            color: isArmed ? Qt.rgba(0.953, 0.545, 0.659, 0.22)
                   : pMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.16) : "transparent"
            Behavior on color { ColorAnimation { duration: 160 } }
            scale: pMa.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
            Row {
              x: 12
              anchors.verticalCenter: parent.verticalCenter
              spacing: 12
              Text {
                width: 16
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
                text: pbtn.modelData.icon
                font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 13
                color: pbtn.modelData.c
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pbtn.isArmed ? "Нажми ещё раз" : pbtn.modelData.t
                font.family: sb.textFont; font.pixelSize: 12; font.bold: pbtn.isArmed
                color: pbtn.isArmed ? "#f38ba8" : sb.cText
              }
            }
            MouseArea {
              id: pMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: sb.powerAction(pbtn.modelData.a)
            }
          }
        }
      }
    }
  }

  // ================= WI-FI =================
  property bool wifiOpen: false
  property real wifiX: 0
  property bool wifiOn: true
  property bool scanning: false
  property var wifiList: []
  property string expanded: ""        // сеть, для которой открыто поле пароля
  property string busySsid: ""        // к какой сети сейчас подключаемся
  property string wifiStatus: ""
  property bool wifiStatusErr: false
  property bool showPass: false

  onWifiOpenChanged: {
    if (wifiOpen) {
      expanded = ""; wifiStatus = ""; showPass = false;
      scanWifi(false);
      rescanLater.restart();
      wifiGrace.restart();
      tipOpen = false;
    }
  }
  Timer { id: rescanLater; interval: 400; onTriggered: sb.scanWifi(true) }
  Timer { id: wifiHide; interval: 700; onTriggered: if (sb.expanded === "" && sb.busySsid === "") sb.wifiOpen = false }
  Timer { id: wifiGrace; interval: 6000; onTriggered: if (!wifiHover.hovered && sb.expanded === "" && sb.busySsid === "") sb.wifiOpen = false }
  Timer { interval: 8000; repeat: true; running: sb.wifiOpen && sb.busySsid === ""; onTriggered: sb.scanWifi(false) }

  // разбор строк nmcli -t: двоеточия внутри имён экранированы как "\:"
  function splitT(line) {
    const out = []; let cur = "";
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (ch === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
      if (ch === ":") { out.push(cur); cur = ""; continue; }
      cur += ch;
    }
    out.push(cur);
    return out;
  }

  function scanWifi(rescan) {
    if (wifiScan.running) return;
    scanning = rescan;
    wifiScan.command = ["sh", "-c",
      "nmcli -t -f WIFI radio; echo ---; nmcli -t -f NAME,TYPE con show; echo ---; "
      + "nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID dev wifi list --rescan " + (rescan ? "yes" : "no") + " 2>/dev/null"];
    wifiScan.running = true;
  }
  Process {
    id: wifiScan
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.split("---\n");
        sb.wifiOn = (parts[0] || "").trim() === "enabled";
        const known = {};
        for (const l of (parts[1] || "").split("\n")) {
          const f = sb.splitT(l);
          if (f[1] === "802-11-wireless") known[f[0]] = true;
        }
        const seen = {}; const list = [];
        for (const l of (parts[2] || "").split("\n")) {
          if (!l) continue;
          const f = sb.splitT(l);
          const ssid = f.slice(3).join(":");
          if (!ssid) continue;
          const item = { ssid: ssid, inUse: f[0] === "*", signal: parseInt(f[1]) || 0,
                         secure: (f[2] || "") !== "" && f[2] !== "--", known: !!known[ssid] };
          if (seen[ssid] !== undefined) {
            const old = list[seen[ssid]];
            if (item.inUse || item.signal > old.signal) list[seen[ssid]] = Object.assign(item, { inUse: item.inUse || old.inUse });
          } else { seen[ssid] = list.length; list.push(item); }
        }
        list.sort((a, b) => (b.inUse - a.inUse) || (b.known - a.known) || (b.signal - a.signal));
        sb.wifiList = list.slice(0, 14);
        sb.scanning = false;
      }
    }
  }

  // действия: подключение / отключение / забыть / вкл-выкл
  Process {
    id: wifiAct
    property string kind: ""
    stdout: StdioCollector { id: actOut }
    stderr: StdioCollector { id: actErr }
    onExited: (code) => {
      const ssid = sb.busySsid;
      sb.busySsid = "";
      if (kind === "connect") {
        if (code === 0) {
          sb.wifiStatus = "Подключено к " + ssid; sb.wifiStatusErr = false; sb.expanded = "";
        } else {
          const err = (actErr.text + actOut.text).toLowerCase();
          sb.wifiStatus = err.indexOf("secrets") >= 0 || err.indexOf("password") >= 0 || err.indexOf("802-1x") >= 0
            ? "Неверный пароль" : "Не удалось подключиться";
          sb.wifiStatusErr = true;
          sb.expanded = ssid;
          // неудачная новая сеть не должна оставаться сохранённой
          if (wifiAct.fresh) Quickshell.execDetached(["nmcli", "con", "delete", "id", ssid]);
        }
      }
      netProc.running = true;
      sb.scanWifi(false);
    }
    property bool fresh: false
  }
  function wifiRun(kind, cmd, ssid, fresh) {
    if (wifiAct.running) return;
    wifiAct.kind = kind;
    wifiAct.fresh = !!fresh;
    busySsid = ssid || "";
    wifiStatus = kind === "connect" ? "Подключаюсь к " + ssid + "…" : "";
    wifiStatusErr = false;
    wifiAct.command = cmd;
    wifiAct.running = true;
  }
  function clickNet(n) {
    if (n.inUse) return;
    if (n.known) wifiRun("connect", ["nmcli", "con", "up", "id", n.ssid], n.ssid, false);
    else if (!n.secure) wifiRun("connect", ["nmcli", "dev", "wifi", "connect", n.ssid], n.ssid, true);
    else { expanded = expanded === n.ssid ? "" : n.ssid; wifiStatus = ""; showPass = false; }
  }
  function connectWithPass(ssid, pass) {
    if (pass.length < 8) { wifiStatus = "Пароль Wi-Fi — минимум 8 символов"; wifiStatusErr = true; return; }
    wifiRun("connect", ["nmcli", "dev", "wifi", "connect", ssid, "password", pass], ssid, true);
  }

  PanelWindow {
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: sb.topMargin + 30
    implicitHeight: 620
    color: "transparent"
    visible: wf.opacity > 0.01
    mask: Region { item: wf }
    WlrLayershell.namespace: "kellos-wifi"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: sb.wifiOpen && sb.expanded !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      id: wf
      width: 320
      height: wfCol.implicitHeight + 24
      x: Math.max(8, Math.min(parent.width - width - 8, sb.wifiX - width / 2))
      radius: 16
      clip: true
      color: Qt.rgba(0.086, 0.055, 0.141, 0.96)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.35)
      transformOrigin: Item.Top
      opacity: sb.wifiOpen ? 1 : 0
      scale: sb.wifiOpen ? 1 : 0.92
      y: sb.wifiOpen ? 0 : -8
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
      Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

      HoverHandler {
        id: wifiHover
        onHoveredChanged: hovered ? wifiHide.stop() : wifiHide.restart()
      }

      Column {
        id: wfCol
        x: 12; y: 12
        width: parent.width - 24
        spacing: 8

        // ---------- заголовок: Wi-Fi, обновить, тумблер ----------
        Item {
          width: parent.width
          height: 28
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Wi-Fi"
            font.family: sb.textFont; font.pixelSize: 14; font.bold: true
            color: sb.cText
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
              width: 28; height: 28; radius: 8
              visible: sb.wifiOn
              color: rsMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : "transparent"
              Behavior on color { ColorAnimation { duration: 150 } }
              Text {
                id: rsIcon
                anchors.centerIn: parent
                text: ""
                font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 11
                color: sb.scanning ? sb.cPink : sb.cLilac
                RotationAnimation on rotation {
                  running: sb.scanning
                  loops: Animation.Infinite
                  from: 0; to: 360; duration: 900
                  onRunningChanged: if (!running) rsIcon.rotation = 0
                }
              }
              MouseArea { id: rsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.scanWifi(true) }
            }
            // тумблер
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 40; height: 22; radius: 11
              color: sb.wifiOn ? sb.cMauve : Qt.rgba(0.769, 0.655, 1.0, 0.15)
              Behavior on color { ColorAnimation { duration: 200 } }
              Rectangle {
                width: 16; height: 16; radius: 8
                y: 3
                x: sb.wifiOn ? parent.width - width - 3 : 3
                color: sb.wifiOn ? sb.cBase : sb.cDim
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  sb.wifiOn = !sb.wifiOn;
                  sb.wifiRun("radio", ["nmcli", "radio", "wifi", sb.wifiOn ? "on" : "off"], "", false);
                  if (sb.wifiOn) rescanLater.restart();
                }
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(0.769, 0.655, 1.0, 0.15) }

        Text {
          visible: !sb.wifiOn || (sb.wifiList.length === 0)
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          topPadding: 10; bottomPadding: 10
          text: !sb.wifiOn ? "Wi-Fi выключен" : sb.scanning ? "Ищу сети…" : "Сетей не найдено"
          font.family: sb.textFont; font.pixelSize: 12
          color: sb.cDim
        }

        // ---------- список сетей ----------
        Flickable {
          visible: sb.wifiOn && sb.wifiList.length > 0
          width: parent.width
          height: Math.min(netCol.implicitHeight, 340)
          contentHeight: netCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: netCol
            width: parent.width
            spacing: 2
            Repeater {
              model: sb.wifiList
              Rectangle {
                id: net
                required property var modelData
                readonly property bool open: sb.expanded === modelData.ssid
                readonly property bool busy: sb.busySsid === modelData.ssid
                width: netCol.width
                height: open ? 82 : 38
                radius: 10
                clip: true
                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                color: modelData.inUse ? Qt.rgba(0.706, 0.557, 0.98, 0.18)
                       : (rowMa.containsMouse || open) ? Qt.rgba(0.769, 0.655, 1.0, 0.1) : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                  id: rowMa
                  width: parent.width; height: 38
                  hoverEnabled: true
                  cursorShape: net.modelData.inUse ? Qt.ArrowCursor : Qt.PointingHandCursor
                  onClicked: sb.clickNet(net.modelData)
                }

                // полоски сигнала
                Row {
                  x: 12; y: 13
                  spacing: 2
                  Repeater {
                    model: 4
                    Rectangle {
                      required property int index
                      anchors.bottom: parent.bottom
                      width: 3; height: 4 + index * 3
                      radius: 1
                      color: net.modelData.signal > index * 25 ? (net.modelData.inUse ? sb.cPink : sb.cLilac)
                                                               : Qt.rgba(0.769, 0.655, 1.0, 0.18)
                    }
                  }
                }
                Text {
                  x: 38; y: 0; height: 38
                  width: parent.width - 38 - rightInfo.width - 12
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                  text: net.modelData.ssid
                  font.family: sb.textFont; font.pixelSize: 12; font.bold: net.modelData.inUse
                  color: sb.cText
                }
                Row {
                  id: rightInfo
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  y: 0; height: 38
                  spacing: 8
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: net.busy || net.modelData.inUse || net.modelData.known
                    text: net.busy ? "…" : net.modelData.inUse ? "подключено" : "сохранена"
                    font.family: sb.textFont; font.pixelSize: 10
                    color: net.modelData.inUse ? sb.cGreen : sb.cDim
                  }
                  // отключиться / забыть — при наведении
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (rowMa.containsMouse || xMa.containsMouse) && (net.modelData.inUse || net.modelData.known)
                    text: net.modelData.inUse ? "" : ""
                    font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 10
                    color: xMa.containsMouse ? sb.cRed : sb.cDim
                    MouseArea {
                      id: xMa
                      anchors.fill: parent
                      anchors.margins: -6
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: net.modelData.inUse
                        ? sb.wifiRun("down", ["nmcli", "con", "down", "id", net.modelData.ssid], "", false)
                        : sb.wifiRun("forget", ["nmcli", "con", "delete", "id", net.modelData.ssid], "", false)
                    }
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: net.modelData.secure
                    text: ""
                    font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 9
                    color: sb.cDim
                  }
                }

                // ---------- пароль ----------
                Item {
                  x: 10; y: 42
                  width: parent.width - 20
                  height: 30
                  visible: net.open
                  Rectangle {
                    width: parent.width - goBtn.width - 6
                    height: 30
                    radius: 8
                    color: Qt.rgba(0.153, 0.102, 0.239, 1)
                    border.width: 1
                    border.color: pass.activeFocus ? sb.cMauve : "transparent"
                    TextInput {
                      id: pass
                      anchors.fill: parent
                      anchors.leftMargin: 10
                      anchors.rightMargin: 28
                      verticalAlignment: TextInput.AlignVCenter
                      echoMode: sb.showPass ? TextInput.Normal : TextInput.Password
                      color: sb.cText
                      selectionColor: sb.cMauve
                      font.family: sb.textFont; font.pixelSize: 12
                      clip: true
                      onAccepted: sb.connectWithPass(net.modelData.ssid, text)
                      Keys.onEscapePressed: sb.expanded = ""
                      Component.onCompleted: if (net.open) forceActiveFocus()
                      Connections {
                        target: net
                        function onOpenChanged() { if (net.open) { pass.text = ""; pass.forceActiveFocus(); } }
                      }
                      Text {
                        visible: pass.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "пароль"
                        font: pass.font
                        color: sb.cDim
                      }
                    }
                    Text {
                      anchors.right: parent.right
                      anchors.rightMargin: 8
                      anchors.verticalCenter: parent.verticalCenter
                      text: sb.showPass ? "" : ""
                      font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 10
                      color: eyeMa.containsMouse ? sb.cText : sb.cDim
                      MouseArea { id: eyeMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.showPass = !sb.showPass }
                    }
                  }
                  Rectangle {
                    id: goBtn
                    anchors.right: parent.right
                    width: goText.implicitWidth + 20
                    height: 30
                    radius: 8
                    color: goMa.containsMouse ? "#c9adff" : sb.cMauve
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                      id: goText
                      anchors.centerIn: parent
                      text: net.busy ? "…" : "Подключить"
                      font.family: sb.textFont; font.pixelSize: 11; font.bold: true
                      color: sb.cBase
                    }
                    MouseArea { id: goMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.connectWithPass(net.modelData.ssid, pass.text) }
                  }
                }
              }
            }
          }
        }

        // ---------- статус ----------
        Text {
          visible: sb.wifiStatus !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: sb.wifiStatus
          font.family: sb.textFont; font.pixelSize: 11
          color: sb.wifiStatusErr ? sb.cRed : sb.cPink
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(0.769, 0.655, 1.0, 0.15) }

        // ---------- низ ----------
        Item {
          width: parent.width
          height: 24
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sb.netType === "ethernet" ? "Кабель: " + sb.ssid : sb.netType === "wifi" ? "Сигнал " + sb.signal + "%" : "Не подключено"
            font.family: sb.textFont; font.pixelSize: 10
            color: sb.cDim
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Настройки сети"
            font.family: sb.textFont; font.pixelSize: 10
            color: setMa.containsMouse ? sb.cPink : sb.cLilac
            Behavior on color { ColorAnimation { duration: 150 } }
            MouseArea {
              id: setMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { sb.wifiOpen = false; sb.run(["nm-connection-editor"]); }
            }
          }
        }
      }
    }
  }

  // ================= BLUETOOTH =================
  property bool btOpen: false
  property real btX: 0
  property bool btScanning: false
  property var btList: []
  property string btBusy: ""
  property string btStatus: ""
  property bool btStatusErr: false

  onBtOpenChanged: {
    if (btOpen) { btStatus = ""; btListRefresh(); btGrace.restart(); tipOpen = false; }
    else if (btScanning) { Quickshell.execDetached(["bluetoothctl", "scan", "off"]); }
  }
  Timer { id: btHide; interval: 700; onTriggered: if (sb.btBusy === "") sb.btOpen = false }
  Timer { id: btGrace; interval: 6000; onTriggered: if (!btHover.hovered && sb.btBusy === "") sb.btOpen = false }
  Timer { interval: 2000; repeat: true; running: sb.btOpen; onTriggered: sb.btListRefresh() }

  // шумоподавление realme/OPPO/OnePlus (скрипт ~/.local/bin/buds)
  property string ancMode: ""
  property string ancBusy: ""
  Process {
    id: budsProc
    property string want: ""
    stdout: StdioCollector { id: budsOut }
    stderr: StdioCollector { id: budsErr }
    onExited: (code) => {
      sb.ancBusy = "";
      if (code === 0) { sb.ancMode = want; sb.btStatus = ""; }
      else { sb.btStatus = (budsErr.text || "Не получилось переключить режим").trim(); sb.btStatusErr = true; }
    }
  }
  function setAnc(m) {
    if (budsProc.running) return;
    ancBusy = m;
    budsProc.want = m;
    budsProc.command = [Quickshell.env("HOME") + "/.local/bin/buds", m];
    budsProc.running = true;
  }
  Process {
    id: budsState
    command: [Quickshell.env("HOME") + "/.local/bin/buds", "status"]
    running: true
    stdout: StdioCollector { onStreamFinished: sb.ancMode = text.trim() }
  }

  function btListRefresh() { if (!btListProc.running) btListProc.running = true; }
  Process {
    id: btListProc
    command: ["sh", Quickshell.env("HOME") + "/.config/quickshell/kellos-music/bt-list.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.split("---\n");
        const head = (parts[0] || "").split("\n");
        sb.btOn = head[0] === "on";
        sb.btAvail = head[0] === "on" || head[0] === "off";
        sb.btScanning = head[1] === "scanning";
        const list = [];
        for (const l of (parts[1] || "").split("\n")) {
          const f = l.split("\t");
          if (f.length < 6 || !f[0]) continue;
          const name = f.slice(5).join("\t");
          if (!name || /^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(name)) continue;  // безымянные — мусор
          list.push({ mac: f[0], paired: f[1] === "yes", connected: f[2] === "yes",
                      icon: f[3] || "", battery: parseInt(f[4]) || -1, name: name });
        }
        list.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name));
        sb.btList = list.slice(0, 14);
        sb.btDevs = list.filter(d => d.connected).map(d => d.name + (d.battery >= 0 ? " · " + d.battery + "%" : ""));
      }
    }
  }

  // поиск новых устройств (8 секунд)
  Process {
    id: btScanProc
    command: ["bluetoothctl", "--timeout", "10", "scan", "on"]
    onRunningChanged: { sb.btScanning = running; if (!running) sb.btListRefresh(); }
  }

  Process {
    id: btAct
    property string kind: ""
    stdout: StdioCollector { id: btOut }
    onExited: (code) => {
      const name = sb.btBusy;
      sb.btBusy = "";
      const out = btOut.text.toLowerCase();
      const ok = code === 0 && out.indexOf("failed") < 0 && out.indexOf("not available") < 0;
      if (kind === "connect" || kind === "pair") {
        sb.btStatus = ok ? "Подключено: " + name : "Не удалось подключить " + name;
        sb.btStatusErr = !ok;
      }
      sb.btListRefresh();
    }
  }
  function btRun(kind, cmd, name) {
    if (btAct.running) return;
    btAct.kind = kind;
    btBusy = name || "";
    btStatus = kind === "pair" ? "Сопрягаю с " + name + "…" : kind === "connect" ? "Подключаю " + name + "…" : "";
    btStatusErr = false;
    btAct.command = cmd;
    btAct.running = true;
  }
  function clickBt(d) {
    if (d.connected) return;
    if (d.paired) btRun("connect", ["bluetoothctl", "connect", d.mac], d.name);
    else btRun("pair", ["sh", "-c", "bluetoothctl pair " + d.mac + " && bluetoothctl trust " + d.mac
                        + " && bluetoothctl connect " + d.mac], d.name);
  }
  function btIcon(t) {
    if (t.indexOf("audio") === 0 || t.indexOf("headset") >= 0) return "\uf025";
    if (t === "phone") return "\uf3cd";
    if (t === "input-keyboard") return "\uf11c";
    if (t === "input-mouse") return "\uf8cc";
    if (t === "input-gaming") return "\uf11b";
    if (t === "computer") return "\uf109";
    return "\uf111";
  }

  PanelWindow {
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: sb.topMargin + 30
    implicitHeight: 620
    color: "transparent"
    visible: btw.opacity > 0.01
    mask: Region { item: btw }
    WlrLayershell.namespace: "kellos-bluetooth"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: btw
      width: 320
      height: btCol.implicitHeight + 24
      x: Math.max(8, Math.min(parent.width - width - 8, sb.btX - width / 2))
      radius: 16
      clip: true
      color: Qt.rgba(0.086, 0.055, 0.141, 0.96)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.35)
      transformOrigin: Item.Top
      opacity: sb.btOpen ? 1 : 0
      scale: sb.btOpen ? 1 : 0.92
      y: sb.btOpen ? 0 : -8
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
      Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

      HoverHandler {
        id: btHover
        onHoveredChanged: hovered ? btHide.stop() : btHide.restart()
      }

      Column {
        id: btCol
        x: 12; y: 12
        width: parent.width - 24
        spacing: 8

        // ---------- заголовок ----------
        Item {
          width: parent.width
          height: 28
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
            font.family: sb.textFont; font.pixelSize: 14; font.bold: true
            color: sb.cText
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
              visible: sb.btOn
              width: scanLbl.implicitWidth + 30; height: 26; radius: 8
              color: btScanMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : "transparent"
              Behavior on color { ColorAnimation { duration: 150 } }
              Row {
                anchors.centerIn: parent
                spacing: 6
                Text {
                  id: btScanIcon
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\uf2f1"
                  font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 10
                  color: sb.btScanning ? sb.cPink : sb.cLilac
                  RotationAnimation on rotation {
                    running: sb.btScanning
                    loops: Animation.Infinite
                    from: 0; to: 360; duration: 900
                    onRunningChanged: if (!running) btScanIcon.rotation = 0
                  }
                }
                Text {
                  id: scanLbl
                  anchors.verticalCenter: parent.verticalCenter
                  text: sb.btScanning ? "Ищу…" : "Поиск"
                  font.family: sb.textFont; font.pixelSize: 11
                  color: sb.btScanning ? sb.cPink : sb.cLilac
                }
              }
              MouseArea {
                id: btScanMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (!btScanProc.running) btScanProc.running = true
              }
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 40; height: 22; radius: 11
              color: sb.btOn ? sb.cMauve : Qt.rgba(0.769, 0.655, 1.0, 0.15)
              Behavior on color { ColorAnimation { duration: 200 } }
              Rectangle {
                width: 16; height: 16; radius: 8
                y: 3
                x: sb.btOn ? parent.width - width - 3 : 3
                color: sb.btOn ? sb.cBase : sb.cDim
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  sb.btOn = !sb.btOn;
                  sb.btRun("power", ["bluetoothctl", "power", sb.btOn ? "on" : "off"], "");
                }
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(0.769, 0.655, 1.0, 0.15) }

        Text {
          visible: !sb.btOn || sb.btList.length === 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          topPadding: 10; bottomPadding: 10
          text: !sb.btOn ? "Bluetooth выключен" : sb.btScanning ? "Ищу устройства…" : "Нет устройств — нажми «Поиск»"
          font.family: sb.textFont; font.pixelSize: 12
          color: sb.cDim
        }

        // ---------- устройства ----------
        Flickable {
          visible: sb.btOn && sb.btList.length > 0
          width: parent.width
          height: Math.min(btListCol.implicitHeight, 340)
          contentHeight: btListCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: btListCol
            width: parent.width
            spacing: 2
            Repeater {
              model: sb.btList
              Rectangle {
                id: dev
                required property var modelData
                readonly property bool busy: sb.btBusy === modelData.name
                readonly property bool isBuds: modelData.connected && /realme|oppo|oneplus|enco/i.test(modelData.name)
                width: btListCol.width
                height: isBuds ? 74 : 38
                clip: true
                radius: 10
                color: modelData.connected ? Qt.rgba(0.706, 0.557, 0.98, 0.18)
                       : devMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.1) : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                  id: devMa
                  width: parent.width; height: 38
                  hoverEnabled: true
                  cursorShape: dev.modelData.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                  onClicked: sb.clickBt(dev.modelData)
                }
                Text {
                  x: 12; width: 18; y: 0; height: 38
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignHCenter
                  text: sb.btIcon(dev.modelData.icon)
                  font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 12
                  color: dev.modelData.connected ? sb.cPink : sb.cLilac
                }
                Text {
                  x: 40; y: 0; height: 38
                  width: parent.width - 40 - devRight.width - 14
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                  text: dev.modelData.name
                  font.family: sb.textFont; font.pixelSize: 12; font.bold: dev.modelData.connected
                  color: sb.cText
                }
                // ---------- шумоподавление ----------
                Row {
                  visible: dev.isBuds
                  x: 10; y: 40
                  width: parent.width - 20
                  height: 26
                  spacing: 4
                  Repeater {
                    model: [{ m: "anc", t: "Шумодав" }, { m: "transparency", t: "Прозрачность" }, { m: "off", t: "Выкл" }]
                    Rectangle {
                      id: ancBtn
                      required property var modelData
                      readonly property bool active: sb.ancMode === modelData.m
                      width: (parent.width - 8) / 3
                      height: 26
                      radius: 8
                      color: active ? sb.cMauve : ancMa.containsMouse ? Qt.rgba(0.769, 0.655, 1.0, 0.18) : Qt.rgba(0.769, 0.655, 1.0, 0.08)
                      Behavior on color { ColorAnimation { duration: 160 } }
                      Text {
                        anchors.centerIn: parent
                        text: sb.ancBusy === ancBtn.modelData.m ? "…" : ancBtn.modelData.t
                        font.family: sb.textFont; font.pixelSize: 10; font.bold: ancBtn.active
                        color: ancBtn.active ? sb.cBase : sb.cText
                      }
                      MouseArea { id: ancMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sb.setAnc(ancBtn.modelData.m) }
                    }
                  }
                }
                Row {
                  id: devRight
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  y: 0; height: 38
                  spacing: 8
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: dev.modelData.connected && dev.modelData.battery >= 0
                    text: dev.modelData.battery + "%"
                    font.family: sb.textFont; font.pixelSize: 10
                    color: dev.modelData.battery <= 20 ? sb.cRed : sb.cGreen
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: dev.busy || dev.modelData.connected || dev.modelData.paired
                    text: dev.busy ? "…" : dev.modelData.connected ? "подключено" : "сохранено"
                    font.family: sb.textFont; font.pixelSize: 10
                    color: dev.modelData.connected ? sb.cGreen : sb.cDim
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (devMa.containsMouse || devX.containsMouse) && (dev.modelData.connected || dev.modelData.paired)
                    text: dev.modelData.connected ? "\uf127" : "\uf2ed"
                    font.family: sb.iconFont; font.weight: Font.Black; font.pixelSize: 10
                    color: devX.containsMouse ? sb.cRed : sb.cDim
                    MouseArea {
                      id: devX
                      anchors.fill: parent
                      anchors.margins: -6
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: dev.modelData.connected
                        ? sb.btRun("disconnect", ["bluetoothctl", "disconnect", dev.modelData.mac], "")
                        : sb.btRun("remove", ["bluetoothctl", "remove", dev.modelData.mac], "")
                    }
                  }
                }
              }
            }
          }
        }

        Text {
          visible: sb.btStatus !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: sb.btStatus
          font.family: sb.textFont; font.pixelSize: 11
          color: sb.btStatusErr ? sb.cRed : sb.cPink
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(0.769, 0.655, 1.0, 0.15) }

        Item {
          width: parent.width
          height: 24
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: sb.btDevs.length > 0 ? "Подключено: " + sb.btDevs.length : "Нет подключений"
            font.family: sb.textFont; font.pixelSize: 10
            color: sb.cDim
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Все настройки"
            font.family: sb.textFont; font.pixelSize: 10
            color: btSetMa.containsMouse ? sb.cPink : sb.cLilac
            Behavior on color { ColorAnimation { duration: 150 } }
            MouseArea {
              id: btSetMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { sb.btOpen = false; sb.run(["blueman-manager"]); }
            }
          }
        }
      }
    }
  }

  // ================= ОКНО ПОДСКАЗКИ =================
  PanelWindow {
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: sb.topMargin + 28
    implicitHeight: tip.height + 4
    color: "transparent"
    mask: Region { item: tip }
    visible: tip.opacity > 0.01
    WlrLayershell.namespace: "kellos-status-tip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: tip
      width: tipLabel.implicitWidth + 24
      height: tipLabel.implicitHeight + 14
      x: Math.max(8, Math.min(parent.width - width - 8, sb.tipCenter - width / 2))
      Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      radius: 8
      color: Qt.rgba(0.102, 0.063, 0.157, 0.95)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.45)
      opacity: sb.tipOpen && !sb.barHidden ? 1 : 0
      y: sb.tipOpen ? 0 : -4
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

      Text {
        id: tipLabel
        anchors.centerIn: parent
        text: sb.tipText
        color: sb.cText
        font.family: sb.textFont
        font.pixelSize: 12
        lineHeight: 1.15
      }
    }
  }

  // ================= МОНИТОР СИСТЕМЫ (клик по CPU/RAM) =================
  property bool monOpen: false
  property var procs: []
  property string uptime: ""
  property string loadAvg: ""
  property int temp: 0
  Process {
    id: monProc
    command: ["sh", "-c",
      "ps -eo comm,%cpu,%mem --sort=-%cpu --no-headers | head -6; echo ---; "
      + "cut -d' ' -f1-3 /proc/loadavg; echo ---; cut -d. -f1 /proc/uptime; echo ---; "
      + "for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type); "
      + "[ \"$t\" = x86_pkg_temp ] && cat $z/temp && break; done"]
    stdout: StdioCollector {
      onStreamFinished: {
        const p = text.split("---");
        sb.procs = (p[0] || "").trim().split("\n").filter(l => l.trim()).map(l => {
          const f = l.trim().split(/\s+/);
          return { name: f.slice(0, f.length - 2).join(" "), cpu: f[f.length - 2], mem: f[f.length - 1] };
        });
        sb.loadAvg = (p[1] || "").trim().split(" ").join("  ");
        const up = parseInt((p[2] || "0").trim()) || 0;
        const d = Math.floor(up / 86400), h = Math.floor(up % 86400 / 3600), m = Math.floor(up % 3600 / 60);
        sb.uptime = (d > 0 ? d + " д " : "") + h + " ч " + m + " мин";
        sb.temp = Math.round((parseInt((p[3] || "0").trim()) || 0) / 1000);
      }
    }
  }
  Timer { interval: 2000; repeat: true; running: sb.monOpen; triggeredOnStart: true; onTriggered: monProc.running = true }

  Timer { id: monHide; interval: 700; onTriggered: sb.monOpen = false }
  Timer { id: monGrace; interval: 5000; onTriggered: if (!monHover.hovered) sb.monOpen = false }
  onMonOpenChanged: if (monOpen) monGrace.restart()

  PanelWindow {
    anchors.top: true
    anchors.right: true
    margins.top: sb.topMargin + 30
    margins.right: 8
    implicitWidth: 520
    implicitHeight: 330
    color: "transparent"
    visible: mon.opacity > 0.01
    mask: Region { item: mon }
    WlrLayershell.namespace: "kellos-sysmon"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: mon
      width: parent.width
      height: parent.height
      radius: 16
      color: Qt.rgba(0.086, 0.055, 0.141, 0.95)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.35)
      transformOrigin: Item.TopRight
      opacity: sb.monOpen ? 1 : 0
      scale: sb.monOpen ? 1 : 0.92
      y: sb.monOpen ? 0 : -8
      Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
      Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

      HoverHandler {
        id: monHover
        onHoveredChanged: hovered ? monHide.stop() : monHide.restart()
      }

      Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // заголовок
        Item {
          width: parent.width
          height: 20
          Text {
            text: "Система"
            color: sb.cText
            font.family: sb.textFont; font.pixelSize: 15; font.bold: true
          }
          Text {
            anchors.right: parent.right
            text: "в работе " + sb.uptime + (sb.temp > 0 ? "   " + sb.temp + "°C" : "")
            color: sb.cDim
            font.family: sb.textFont; font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // два графика
        Row {
          width: parent.width
          spacing: 14
          Repeater {
            model: [
              { name: "Процессор", key: "cpu" },
              { name: "Память", key: "mem" }
            ]
            Rectangle {
              id: gcard
              required property var modelData
              readonly property bool isCpu: modelData.key === "cpu"
              readonly property int pct: isCpu ? sb.cpu : sb.memPct
              readonly property var hist: isCpu ? sb.cpuHist : sb.memHist
              readonly property color col: isCpu ? sb.level(sb.cpu, 60, 85) : sb.level(sb.memPct, 70, 90)
              width: (parent.width - 14) / 2
              height: 120
              radius: 12
              color: Qt.rgba(0.769, 0.655, 1.0, 0.07)

              Text {
                x: 12; y: 10
                text: gcard.modelData.name
                color: sb.cDim
                font.family: sb.textFont; font.pixelSize: 11
              }
              Text {
                x: 12; y: 26
                text: gcard.pct + "%"
                color: gcard.col
                font.family: sb.textFont; font.pixelSize: 24; font.bold: true
                Behavior on color { ColorAnimation { duration: 300 } }
              }
              Text {
                anchors.right: parent.right; anchors.rightMargin: 12; y: 14
                text: gcard.isCpu ? sb.loadAvg
                      : sb.memUsed.toFixed(1) + " / " + sb.memTotal.toFixed(1) + " ГБ"
                color: sb.cDim
                font.family: sb.textFont; font.pixelSize: 10
              }
              Canvas {
                id: graph
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: 10
                height: 50
                property var data: gcard.hist
                property color lineColor: gcard.col
                onDataChanged: requestPaint()
                onLineColorChanged: requestPaint()
                onPaint: {
                  const ctx = getContext("2d");
                  ctx.reset();
                  const n = 60, w = width, h = height, d = data || [];
                  if (d.length < 2) return;
                  const step = w / (n - 1), off = (n - d.length) * step;
                  ctx.beginPath();
                  for (let i = 0; i < d.length; i++) {
                    const x = off + i * step, y = h - (h * d[i] / 100);
                    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
                  }
                  const c = lineColor;
                  ctx.strokeStyle = c.toString();
                  ctx.lineWidth = 2;
                  ctx.stroke();
                  ctx.lineTo(off + (d.length - 1) * step, h);
                  ctx.lineTo(off, h);
                  ctx.closePath();
                  ctx.fillStyle = "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ",0.15)";
                  ctx.fill();
                }
              }
            }
          }
        }

        // топ процессов
        Column {
          width: parent.width
          spacing: 3
          Row {
            width: parent.width
            Text { width: parent.width - 140; text: "Процесс"; color: sb.cDim; font.family: sb.textFont; font.pixelSize: 10 }
            Text { width: 70; horizontalAlignment: Text.AlignRight; text: "CPU"; color: sb.cDim; font.family: sb.textFont; font.pixelSize: 10 }
            Text { width: 70; horizontalAlignment: Text.AlignRight; text: "RAM"; color: sb.cDim; font.family: sb.textFont; font.pixelSize: 10 }
          }
          Repeater {
            model: sb.procs.slice(0, 5)
            Row {
              required property var modelData
              width: parent.width
              Text { width: parent.width - 140; text: modelData.name; elide: Text.ElideRight; color: sb.cText; font.family: sb.textFont; font.pixelSize: 11 }
              Text { width: 70; horizontalAlignment: Text.AlignRight; text: modelData.cpu + "%"; color: sb.cLilac; font.family: sb.textFont; font.pixelSize: 11 }
              Text { width: 70; horizontalAlignment: Text.AlignRight; text: modelData.mem + "%"; color: sb.cPink; font.family: sb.textFont; font.pixelSize: 11 }
            }
          }
        }
      }

      // кнопка btop
      Rectangle {
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 14
        width: btopText.implicitWidth + 20
        height: 24
        radius: 8
        color: btopArea.containsMouse ? Qt.rgba(0.706, 0.557, 0.98, 0.35) : Qt.rgba(0.706, 0.557, 0.98, 0.18)
        Behavior on color { ColorAnimation { duration: 160 } }
        Text {
          id: btopText
          anchors.centerIn: parent
          text: "Открыть btop"
          color: sb.cText
          font.family: sb.textFont; font.pixelSize: 11
        }
        MouseArea {
          id: btopArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { sb.monOpen = false; sb.run(["kitty", "--class", "btop-float", "-e", "btop"]); }
        }
      }
    }
  }
}
