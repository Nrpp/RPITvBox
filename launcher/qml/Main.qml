import QtQuick
import QtQuick.Window

Window {
    id: win
    width: 1920
    height: 1080
    visible: true
    visibility: windowed ? Window.Windowed : Window.FullScreen
    color: "#0b0e14"
    title: "RPi TV Box"

    // Escala para que se vea igual en 720p, 1080p o 4K.
    readonly property real s: Math.min(width / 1920, height / 1080)

    property int row: 0            // 0 = apps, 1 = ajustes
    property int appIndex: 0
    property int settingIndex: 0
    property int availabilityTick: 0  // fuerza recalcular "instalada" al volver

    readonly property var settingsModel: [
        { id: "refresh",  name: "Actualizar", glyph: "↻", color: "#3a4a63" },
        { id: "info",     name: "Información", glyph: "i",    color: "#3a4a63" },
        { id: "reboot",   name: "Reiniciar",  glyph: "⟳", color: "#5a4a2a" },
        { id: "shutdown", name: "Apagar",     glyph: "⏻", color: "#6a2a2a" }
    ]

    readonly property var focusedApp: appsModel.length > 0 ? appsModel[appIndex] : null

    function bringToFront() {
        availabilityTick++
        win.visibility = windowed ? Window.Windowed : Window.FullScreen
        win.raise()
        win.requestActivate()
        keyHandler.forceActiveFocus()
    }

    function toast(msg) {
        toastText.text = msg
        toastBox.opacity = 1
        toastTimer.restart()
    }

    // Mandos HDMI-CEC: el kernel envía KEY_OK (352) y KEY_EXIT (174), que en
    // Wayland pueden llegar sin tecla Qt asignada. Se reconocen por código (evdev + 8).
    function isSelect(event) {
        return event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Select || event.key === Qt.Key_Space
            || event.nativeScanCode === 352 + 8
    }
    function isBack(event) {
        return event.key === Qt.Key_Escape || event.key === Qt.Key_Back
            || event.key === Qt.Key_Backspace || event.key === Qt.Key_Exit
            || event.nativeScanCode === 174 + 8
    }

    function activate() {
        if (launcher.runningApp !== "")
            return
        if (row === 0 && focusedApp) {
            launcher.launch(focusedApp.id)
        } else if (row === 1) {
            var id = settingsModel[settingIndex].id
            if (id === "refresh") { availabilityTick++; toast("Lista de apps actualizada") }
            else if (id === "info") toast(system.hostname() + "  ·  IP " + system.ipAddress())
            else confirm.ask(id)
        }
    }

    Connections {
        target: launcher
        function onMessage(msg) { win.toast(msg) }
    }

    // ---------- fondo ----------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: focusedApp && row === 0 ? Qt.darker(focusedApp.color, 3.2) : "#141a26" }
            GradientStop { position: 0.65; color: "#0b0e14" }
        }
    }

    Item {
        id: content
        anchors.fill: parent

        // ---------- barra superior ----------
        Text {
            x: 80 * s; y: 50 * s
            text: "RPi<b>TV</b>"
            color: "white"
            font.pixelSize: 44 * s
            textFormat: Text.RichText
        }
        Text {
            id: clock
            anchors.right: parent.right
            anchors.rightMargin: 80 * s
            y: 54 * s
            color: "#d0d6e0"
            font.pixelSize: 40 * s
            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: clock.text = Qt.formatTime(new Date(), "HH:mm")
            }
        }

        // ---------- cabecera de la app enfocada ----------
        Column {
            x: 80 * s; y: 200 * s
            spacing: 12 * s
            Text {
                text: row === 0 && focusedApp ? focusedApp.name : settingsModel[settingIndex].name
                color: "white"
                font.pixelSize: 84 * s
                font.bold: true
            }
            Text {
                width: win.width - 160 * s
                wrapMode: Text.WordWrap
                color: "#aab3c2"
                font.pixelSize: 30 * s
                text: {
                    availabilityTick
                    if (row !== 0 || !focusedApp) return "Ajustes del sistema"
                    if (!launcher.available(focusedApp.id))
                        return "No instalada. " + focusedApp.install_hint
                    return focusedApp.hint || "Pulsa OK para abrir"
                }
            }
        }

        // ---------- fila de apps ----------
        Text {
            x: 80 * s; y: 480 * s
            text: "Tus apps"
            color: row === 0 ? "white" : "#7c8698"
            font.pixelSize: 34 * s
            font.bold: true
        }
        ListView {
            id: appsRow
            x: 80 * s; y: 545 * s
            width: win.width - 80 * s
            height: 240 * s
            orientation: ListView.Horizontal
            spacing: 40 * s
            model: appsModel
            currentIndex: appIndex
            interactive: false
            clip: false
            highlightMoveDuration: 200
            preferredHighlightBegin: 20 * s
            preferredHighlightEnd: width - 360 * s
            highlightRangeMode: ListView.ApplyRange
            delegate: Tile {
                y: 20 * s
                tileWidth: 300 * s
                tileHeight: 170 * s
                title: modelData.name
                tint: modelData.color
                focused: row === 0 && index === appIndex
                installed: { availabilityTick; return launcher.available(modelData.id) }
            }
        }

        // ---------- fila de ajustes ----------
        Text {
            x: 80 * s; y: 800 * s
            text: "Ajustes"
            color: row === 1 ? "white" : "#7c8698"
            font.pixelSize: 34 * s
            font.bold: true
        }
        Row {
            x: 80 * s; y: 865 * s
            spacing: 40 * s
            Repeater {
                model: settingsModel
                delegate: Tile {
                    tileWidth: 220 * s
                    tileHeight: 120 * s
                    title: modelData.name
                    glyph: modelData.glyph
                    tint: modelData.color
                    focused: row === 1 && index === settingIndex
                }
            }
        }
    }

    // ---------- teclado / mando ----------
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
            if (confirm.visible) { confirm.handleKey(event); return }
            if (launcher.runningApp !== "") { event.accepted = true; return }
            if (isSelect(event)) { activate(); event.accepted = true; return }
            switch (event.key) {
            case Qt.Key_Left:
                if (row === 0) appIndex = Math.max(0, appIndex - 1)
                else settingIndex = Math.max(0, settingIndex - 1)
                break
            case Qt.Key_Right:
                if (row === 0) appIndex = Math.min(appsModel.length - 1, appIndex + 1)
                else settingIndex = Math.min(settingsModel.length - 1, settingIndex + 1)
                break
            case Qt.Key_Up:   row = 0; break
            case Qt.Key_Down: row = 1; break
            case Qt.Key_HomePage:
            case Qt.Key_Home:
                row = 0; appIndex = 0; break
            default:
                return
            }
            event.accepted = true
        }
    }

    // ---------- pantalla "abriendo app" ----------
    Rectangle {
        anchors.fill: parent
        visible: launcher.runningApp !== ""
        color: "#e60b0e14"
        Column {
            anchors.centerIn: parent
            spacing: 24 * s
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Abriendo " + (focusedApp ? focusedApp.name : "") + "…"
                color: "white"
                font.pixelSize: 64 * s
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Mantén pulsado Atrás 2 s (o el botón Inicio de un mando Bluetooth) para volver al menú"
                color: "#aab3c2"
                font.pixelSize: 30 * s
            }
        }
    }

    // ---------- confirmación reiniciar/apagar ----------
    Rectangle {
        id: confirm
        property string action: ""
        property int choice: 1  // 0 = sí, 1 = no (por defecto "No")
        anchors.fill: parent
        visible: action !== ""
        color: "#cc000000"
        function ask(a) { action = a; choice = 1 }
        function handleKey(event) {
            event.accepted = true
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) choice = 1 - choice
            else if (win.isBack(event)) action = ""
            else if (win.isSelect(event)) {
                if (choice === 0) { if (action === "reboot") system.reboot(); else system.shutdown() }
                action = ""
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: 40 * s
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: confirm.action === "reboot" ? "¿Reiniciar la RPi?" : "¿Apagar la RPi?"
                color: "white"; font.pixelSize: 56 * s; font.bold: true
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 40 * s
                Repeater {
                    model: ["Sí", "No"]
                    Rectangle {
                        width: 220 * s; height: 90 * s; radius: 16
                        color: confirm.choice === index ? "white" : "#333a48"
                        Text {
                            anchors.centerIn: parent; text: modelData
                            color: confirm.choice === index ? "#0b0e14" : "white"
                            font.pixelSize: 36 * s; font.bold: true
                        }
                    }
                }
            }
        }
    }

    // ---------- aviso flotante ----------
    Rectangle {
        id: toastBox
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 130 * s
        width: Math.min(win.width - 160 * s, toastText.implicitWidth + 60 * s)
        height: toastText.implicitHeight + 36 * s
        radius: 14
        color: "#2a3242"
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        Text {
            id: toastText
            anchors.centerIn: parent
            width: parent.width - 60 * s
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "white"
            font.pixelSize: 28 * s
        }
        Timer { id: toastTimer; interval: 4500; onTriggered: toastBox.opacity = 0 }
    }
}
