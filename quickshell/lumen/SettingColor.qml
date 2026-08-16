import QtQuick

/// One colour of the settings: either following the wallpaper, or pinned.
///
/// Pinning does not open a colour wheel — it freezes whatever pywal is showing
/// right now and adds three rows underneath to move it around, which is both
/// less code and a better starting point than a blank picker.
Item {
    id: row

    required property string label
    /// Key inside `Settings.colors`.
    required property string key
    property bool selected: false

    readonly property bool automatic: Settings.colors[row.key] === Settings.auto
    readonly property color shown: row.automatic ? Colors.autoValue(row.key) : Settings.colors[row.key]

    /// Pins the colour to what is on screen, or hands it back to the palette.
    function flip() {
        Settings.colors[row.key] = row.automatic ? Colors.autoValue(row.key).toString() : Settings.auto;
    }

    implicitHeight: 44

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.42
        elide: Text.ElideRight
        text: row.label
        color: Colors.foreground
        opacity: row.selected ? 1 : 0.75
        font.family: Style.textFont
        font.pixelSize: Style.textSize
    }

    Text {
        id: state

        anchors.right: swatch.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: row.automatic ? "auto" : row.shown.toString()
        color: row.automatic ? Colors.foreground : Colors.selected
        opacity: row.automatic ? 0.55 : 1
        font.family: Style.textFont
        font.pixelSize: Style.textSize
    }

    Rectangle {
        id: swatch

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        height: 26
        radius: Style.picker.entryRadius + 3
        color: row.shown
        border.width: 3
        border.color: row.automatic ? Colors.foreground : Colors.selected
        opacity: row.automatic ? 0.75 : 1

        Behavior on color {
            ColorAnimation {
                duration: Style.fadeDuration
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.flip()
        }
    }
}
