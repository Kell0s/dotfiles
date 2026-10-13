// Kellos Calendar — открывается кликом по дате на панели
//   стрелки или колёсико — листать месяцы · клик по заголовку — вернуться к сегодня
//   клик по дню — заметка (однократно или каждый год) · в этот день придёт уведомление
//   наведение на отмеченный день — сколько дней осталось
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
  id: cal

  property int topMargin: 4
  property bool open: false

  readonly property color cMauve: "#b48efa"
  readonly property color cPink: "#f5a9e0"
  readonly property color cText: "#e0d4f5"
  readonly property color cDim: "#6b5a85"
  readonly property color cSurface: "#271a3d"
  readonly property string iconFont: "Font Awesome 6 Free"
  readonly property string textFont: "JetBrains Mono"
  readonly property int notifyHour: 8      // во сколько присылать уведомление

  readonly property var monthNames: ["January", "February", "March", "April", "May", "June",
                                     "July", "August", "September", "October", "November", "December"]
  readonly property var dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

  property var today: new Date()
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  property int slideDir: 0

  Timer {
    interval: 60000; repeat: true; running: true
    onTriggered: { cal.today = new Date(); cal.checkNotify(); }
  }

  IpcHandler {
    target: "calendar"
    function toggle(): void { cal.open = !cal.open; }
  }

  onOpenChanged: {
    if (open) {
      today = new Date();
      viewYear = today.getFullYear();
      viewMonth = today.getMonth();
      grace.restart();
    } else {
      editing = false;
      hoverText = "";
      hoverKey = "";
    }
  }

  // ================= ЗАМЕТКИ =================
  readonly property string dataDir: Quickshell.env("HOME") + "/.config/kellos"
  property var events: []

  FileView {
    id: store
    path: cal.dataDir + "/events.json"
    printErrors: false
    adapter: JsonAdapter {
      id: db
      property var events: []
    }
    onLoaded: { cal.events = db.events || []; cal.checkNotify(); }
    onLoadFailed: { Quickshell.execDetached(["mkdir", "-p", cal.dataDir]); cal.events = []; }
  }
  function persist(list) {
    cal.events = list;
    db.events = list;
    Quickshell.execDetached(["mkdir", "-p", cal.dataDir]);
    Qt.callLater(() => store.writeAdapter());
  }

  function ymd(y, m, d) { return y + "-" + (m + 1 < 10 ? "0" : "") + (m + 1) + "-" + (d < 10 ? "0" : "") + d; }
  function eventsOn(y, m, d) {
    return events.filter(e => e.m === m && e.d === d && (e.yearly || e.y === y));
  }
  function midnight(dt) { return new Date(dt.getFullYear(), dt.getMonth(), dt.getDate()); }
  function daysUntil(e, y) {
    const t = midnight(new Date());
    let target = new Date(e.yearly ? y : e.y, e.m, e.d);
    if (e.yearly) {
      target = new Date(t.getFullYear(), e.m, e.d);
      if (target < t) target = new Date(t.getFullYear() + 1, e.m, e.d);
    }
    return Math.round((target - t) / 86400000);
  }
  function plural(n, a, b, c) {
    n = Math.abs(n) % 100;
    const n1 = n % 10;
    if (n > 10 && n < 20) return c;
    if (n1 > 1 && n1 < 5) return b;
    if (n1 === 1) return a;
    return c;
  }
  function whenText(n) {
    if (n === 0) return "сегодня!";
    if (n === 1) return "завтра";
    if (n > 0) return "через " + n + " " + plural(n, "день", "дня", "дней");
    return Math.abs(n) + " " + plural(n, "день", "дня", "дней") + " назад";
  }

  // уведомления: в день события, начиная с notifyHour, один раз
  function checkNotify() {
    const now = new Date();
    if (now.getHours() < notifyHour || events.length === 0) return;
    const todayKey = ymd(now.getFullYear(), now.getMonth(), now.getDate());
    let changed = false;
    const list = events.map(e => Object.assign({}, e));
    for (const e of list) {
      const match = e.m === now.getMonth() && e.d === now.getDate() && (e.yearly || e.y === now.getFullYear());
      if (match && e.last !== todayKey) {
        Quickshell.execDetached(["notify-send", "-a", "Календарь", "-i", "x-office-calendar",
                                 "Сегодня: " + e.text, e.yearly ? "Ежегодное событие" : "Заметка в календаре"]);
        e.last = todayKey;
        changed = true;
      }
    }
    if (changed) persist(list);
  }

  // ================= РЕДАКТОР =================
  property bool editing: false
  property int editY: 0
  property int editM: 0
  property int editD: 0
  property bool editYearly: false
  property int editIndex: -1
  property string hoverText: ""
  property string hoverKey: ""

  function startEdit(y, m, d) {
    editY = y; editM = m; editD = d;
    const idx = events.findIndex(e => e.m === m && e.d === d && (e.yearly || e.y === y));
    editIndex = idx;
    editYearly = idx >= 0 ? !!events[idx].yearly : false;
    input.text = idx >= 0 ? events[idx].text : "";
    editing = true;
    hideT.stop();
    Qt.callLater(() => input.forceActiveFocus());
  }
  function saveEdit() {
    const text = input.text.trim();
    const list = events.slice();
    if (editIndex >= 0) list.splice(editIndex, 1);
    if (text !== "") list.push({ y: editY, m: editM, d: editD, text: text, yearly: editYearly, last: "" });
    persist(list);
    editing = false;
  }
  function deleteEdit() {
    if (editIndex >= 0) {
      const list = events.slice();
      list.splice(editIndex, 1);
      persist(list);
    }
    editing = false;
  }

  // ================= СЕТКА =================
  function shift(d) {
    slideDir = d;
    swap.restart();
  }
  function goToday() {
    const t = new Date();
    viewYear = t.getFullYear();
    viewMonth = t.getMonth();
  }
  function applyShift() {
    let m = viewMonth + slideDir, y = viewYear;
    if (m < 0) { m = 11; y--; }
    if (m > 11) { m = 0; y++; }
    viewMonth = m; viewYear = y;
  }

  // 42 клетки: с понедельника недели, в которой 1-е число
  readonly property var cells: {
    const first = new Date(viewYear, viewMonth, 1);
    const offset = (first.getDay() + 6) % 7;
    const start = new Date(viewYear, viewMonth, 1 - offset);
    const out = [];
    const evs = events;   // зависимость: пересчитать при изменении заметок
    for (let i = 0; i < 42; i++) {
      const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
      const list = eventsOn(d.getFullYear(), d.getMonth(), d.getDate());
      out.push({
        y: d.getFullYear(), m: d.getMonth(), day: d.getDate(),
        inMonth: d.getMonth() === viewMonth,
        isToday: d.toDateString() === today.toDateString(),
        weekend: i % 7 >= 5,
        marked: list.length > 0,
        label: list.map(e => e.text).join(", "),
        days: list.length > 0 ? daysUntil(list[0], d.getFullYear()) : 0
      });
    }
    return out;
  }

  Timer { id: hideT; interval: 700; onTriggered: if (!cal.editing) cal.open = false }
  Timer { id: grace; interval: 5000; onTriggered: if (!hover.hovered && !cal.editing) cal.open = false }

  PanelWindow {
    anchors.top: true
    margins.top: cal.topMargin + 30
    implicitWidth: 300
    implicitHeight: 470
    color: "transparent"
    visible: card.opacity > 0.01
    mask: Region { item: card }
    WlrLayershell.namespace: "kellos-calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: cal.editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      id: card
      width: parent.width
      height: cal.editing ? 466 : 322
      Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
      radius: 14
      clip: true
      color: Qt.rgba(0.086, 0.055, 0.141, 0.95)
      border.width: 1
      border.color: Qt.rgba(0.706, 0.557, 0.98, 0.35)
      transformOrigin: Item.Top
      opacity: cal.open ? 1 : 0
      scale: cal.open ? 1 : 0.92
      y: cal.open ? 0 : -8
      Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      Behavior on scale   { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
      Behavior on y       { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

      HoverHandler {
        id: hover
        onHoveredChanged: hovered ? hideT.stop() : hideT.restart()
      }
      WheelHandler {
        enabled: !cal.editing
        onWheel: (e) => cal.shift(e.angleDelta.y > 0 ? -1 : 1)
      }

      // ---------- заголовок ----------
      Item {
        x: 14; y: 12
        width: parent.width - 28
        height: 28

        Rectangle {
          width: 28; height: 28; radius: 8
          color: prevArea.containsMouse ? Qt.rgba(0.706, 0.557, 0.98, 0.2) : "transparent"
          Behavior on color { ColorAnimation { duration: 150 } }
          Text { anchors.centerIn: parent; text: ""; font.family: cal.iconFont; font.weight: Font.Black; font.pixelSize: 11; color: cal.cText }
          MouseArea { id: prevArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cal.shift(-1) }
        }
        Rectangle {
          anchors.right: parent.right
          width: 28; height: 28; radius: 8
          color: nextArea.containsMouse ? Qt.rgba(0.706, 0.557, 0.98, 0.2) : "transparent"
          Behavior on color { ColorAnimation { duration: 150 } }
          Text { anchors.centerIn: parent; text: ""; font.family: cal.iconFont; font.weight: Font.Black; font.pixelSize: 11; color: cal.cText }
          MouseArea { id: nextArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cal.shift(1) }
        }
        Text {
          anchors.centerIn: parent
          text: cal.monthNames[cal.viewMonth] + " " + cal.viewYear
          color: titleArea.containsMouse ? cal.cPink : cal.cText
          font.family: cal.textFont
          font.pixelSize: 14
          font.bold: true
          Behavior on color { ColorAnimation { duration: 150 } }
          MouseArea {
            id: titleArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              const t = new Date();
              if (t.getFullYear() !== cal.viewYear || t.getMonth() !== cal.viewMonth) {
                cal.slideDir = (t.getFullYear() * 12 + t.getMonth()) > (cal.viewYear * 12 + cal.viewMonth) ? 1 : -1;
                swapToday.restart();
              }
            }
          }
        }
      }

      // ---------- дни недели ----------
      Row {
        x: 14; y: 50
        Repeater {
          model: cal.dayNames
          Text {
            required property string modelData
            required property int index
            width: 38.857
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            color: index >= 5 ? cal.cPink : cal.cDim
            font.family: cal.textFont
            font.pixelSize: 11
          }
        }
      }

      // ---------- сетка ----------
      Item {
        x: 14; y: 72
        width: parent.width - 28
        height: 210
        clip: true

        Grid {
          id: grid
          columns: 7
          width: parent.width
          Repeater {
            model: cal.cells
            Item {
              id: dcell
              required property var modelData
              readonly property bool selected: cal.editing && modelData.y === cal.editY && modelData.m === cal.editM && modelData.day === cal.editD
              width: 38.857
              height: 35
              Rectangle {
                anchors.centerIn: parent
                width: 30; height: 30; radius: 15
                color: dcell.modelData.isToday ? cal.cMauve
                       : dcell.selected ? Qt.rgba(0.961, 0.663, 0.878, 0.35)
                       : dayArea.containsMouse ? Qt.rgba(0.706, 0.557, 0.98, 0.18) : "transparent"
                border.width: dcell.modelData.marked && !dcell.modelData.isToday ? 1 : 0
                border.color: cal.cPink
                Behavior on color { ColorAnimation { duration: 150 } }
              }
              Text {
                anchors.centerIn: parent
                text: dcell.modelData.day
                font.family: cal.textFont
                font.pixelSize: 12
                font.bold: dcell.modelData.isToday || dcell.modelData.marked
                color: dcell.modelData.isToday ? "#160e24"
                       : !dcell.modelData.inMonth ? Qt.rgba(0.42, 0.35, 0.52, 0.6)
                       : dcell.modelData.weekend ? cal.cPink : cal.cText
              }
              Rectangle {   // точка-метка
                visible: dcell.modelData.marked
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                width: 4; height: 4; radius: 2
                color: dcell.modelData.isToday ? cal.cText : cal.cPink
              }
              MouseArea {
                id: dayArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: cal.startEdit(dcell.modelData.y, dcell.modelData.m, dcell.modelData.day)
                // ключ клетки: уход с соседней клетки не стирает текст новой
                readonly property string key: dcell.modelData.y + "-" + dcell.modelData.m + "-" + dcell.modelData.day
                onContainsMouseChanged: {
                  if (containsMouse) {
                    cal.hoverKey = key;
                    cal.hoverText = dcell.modelData.marked
                      ? dcell.modelData.label + " · " + cal.whenText(dcell.modelData.days) : "";
                  } else if (cal.hoverKey === key) {
                    cal.hoverKey = "";
                    cal.hoverText = "";
                  }
                }
              }
            }
          }
        }
      }

      // ---------- строка подсказки ----------
      Text {
        id: infoLine
        x: 16; y: 290
        width: parent.width - 32
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        property string shown: ""
        text: shown
        color: cal.cPink
        font.family: cal.textFont
        font.pixelSize: 11
        opacity: cal.hoverText !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Connections {
          target: cal
          function onHoverTextChanged() { if (cal.hoverText !== "") infoLine.shown = cal.hoverText; }
        }
      }

      // ---------- редактор заметки ----------
      Item {
        x: 14; y: 318
        width: parent.width - 28
        height: 136
        opacity: cal.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(0.769, 0.655, 1.0, 0.2) }

        Text {
          y: 10
          text: cal.editD + " " + cal.monthNames[cal.editM] + " " + cal.editY
          color: cal.cText
          font.family: cal.textFont; font.pixelSize: 12; font.bold: true
        }

        Rectangle {
          y: 32
          width: parent.width
          height: 30
          radius: 8
          color: cal.cSurface
          border.width: 1
          border.color: input.activeFocus ? cal.cMauve : "transparent"
          Behavior on border.color { ColorAnimation { duration: 150 } }
          TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: cal.cText
            selectionColor: cal.cMauve
            font.family: cal.textFont
            font.pixelSize: 12
            clip: true
            onAccepted: cal.saveEdit()
            Keys.onEscapePressed: cal.editing = false
            Text {
              visible: input.text === "" && !input.activeFocus
              anchors.verticalCenter: parent.verticalCenter
              text: "подпись, например «Днюха Димы»"
              color: cal.cDim
              font: input.font
            }
          }
        }

        // однократно / каждый год
        Row {
          y: 72
          spacing: 6
          Repeater {
            model: [{ t: "Один раз", v: false }, { t: "Каждый год", v: true }]
            Rectangle {
              id: opt
              required property var modelData
              readonly property bool active: cal.editYearly === modelData.v
              width: optText.implicitWidth + 20
              height: 24
              radius: 8
              color: active ? Qt.rgba(0.706, 0.557, 0.98, 0.35) : (optArea.containsMouse ? Qt.rgba(0.706, 0.557, 0.98, 0.15) : "transparent")
              border.width: 1
              border.color: Qt.rgba(0.706, 0.557, 0.98, active ? 0.6 : 0.2)
              Behavior on color { ColorAnimation { duration: 150 } }
              Text { id: optText; anchors.centerIn: parent; text: opt.modelData.t; color: cal.cText; font.family: cal.textFont; font.pixelSize: 11 }
              MouseArea { id: optArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cal.editYearly = opt.modelData.v }
            }
          }
        }

        // кнопки
        Row {
          y: 106
          anchors.right: parent.right
          spacing: 6
          Repeater {
            model: cal.editIndex >= 0 ? ["delete", "cancel", "save"] : ["cancel", "save"]
            Rectangle {
              id: btn
              required property string modelData
              readonly property bool primary: modelData === "save"
              width: btnText.implicitWidth + 20
              height: 24
              radius: 8
              color: primary ? (btnArea.containsMouse ? "#c9adff" : cal.cMauve)
                     : (btnArea.containsMouse ? Qt.rgba(0.706, 0.557, 0.98, 0.2) : "transparent")
              Behavior on color { ColorAnimation { duration: 150 } }
              Text {
                id: btnText
                anchors.centerIn: parent
                text: btn.modelData === "save" ? "Сохранить" : btn.modelData === "delete" ? "Удалить" : "Отмена"
                color: btn.primary ? "#160e24" : btn.modelData === "delete" ? "#f38ba8" : cal.cText
                font.family: cal.textFont; font.pixelSize: 11; font.bold: btn.primary
              }
              MouseArea {
                id: btnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: btn.modelData === "save" ? cal.saveEdit() : btn.modelData === "delete" ? cal.deleteEdit() : (cal.editing = false)
              }
            }
          }
        }
      }

      // ---------- анимации перелистывания ----------
      SequentialAnimation {
        id: swap
        ParallelAnimation {
          NumberAnimation { target: grid; property: "opacity"; to: 0; duration: 120 }
          NumberAnimation { target: grid; property: "x"; to: -24 * cal.slideDir; duration: 120; easing.type: Easing.InCubic }
        }
        ScriptAction { script: cal.applyShift() }
        PropertyAction { target: grid; property: "x"; value: 24 * cal.slideDir }
        ParallelAnimation {
          NumberAnimation { target: grid; property: "opacity"; to: 1; duration: 200 }
          NumberAnimation { target: grid; property: "x"; to: 0; duration: 200; easing.type: Easing.OutCubic }
        }
      }
      SequentialAnimation {
        id: swapToday
        ParallelAnimation {
          NumberAnimation { target: grid; property: "opacity"; to: 0; duration: 120 }
          NumberAnimation { target: grid; property: "x"; to: -24 * cal.slideDir; duration: 120 }
        }
        ScriptAction { script: cal.goToday() }
        PropertyAction { target: grid; property: "x"; value: 24 * cal.slideDir }
        ParallelAnimation {
          NumberAnimation { target: grid; property: "opacity"; to: 1; duration: 200 }
          NumberAnimation { target: grid; property: "x"; to: 0; duration: 200; easing.type: Easing.OutCubic }
        }
      }
    }
  }
}
