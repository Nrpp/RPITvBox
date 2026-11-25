import QtQuick

// Mosaico de app. Crece y se ilumina cuando tiene el foco del mando.
Item {
    id: tile
    property string title: ""
    property string glyph: title.length > 0 ? title.charAt(0) : "?"
    property color tint: "#444"
    property bool focused: false
    property bool installed: true
    property real tileWidth: 300
    property real tileHeight: 170

    width: tileWidth
    height: tileHeight
    z: focused ? 10 : 1

    Rectangle {
        id: glow
        anchors.centerIn: card
        width: card.width + 24
        height: card.height + 24
        radius: 26
        color: tile.tint
        opacity: tile.focused ? 0.35 : 0
        scale: card.scale
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 18
        scale: tile.focused ? 1.12 : 1.0
        border.width: tile.focused ? 4 : 0
        border.color: "white"
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(tile.tint, 1.25) }
            GradientStop { position: 1.0; color: Qt.darker(tile.tint, 1.6) }
        }
        opacity: tile.installed ? 1.0 : 0.45
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 18
            text: tile.glyph
            color: "#ffffff"
            opacity: 0.9
            font.pixelSize: tile.tileHeight * 0.36
            font.bold: true
        }
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 18
            text: tile.title
            color: "white"
            font.pixelSize: 28
            font.bold: true
        }
        Rectangle {
            visible: !tile.installed
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            radius: 8
            color: "#000000aa"
            width: badge.implicitWidth + 16
            height: badge.implicitHeight + 8
            Text {
                id: badge
                anchors.centerIn: parent
                text: "No instalada"
                color: "white"
                font.pixelSize: 16
            }
        }
    }
}
