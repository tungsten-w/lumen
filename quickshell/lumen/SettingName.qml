import QtQuick

/// The name of a preset, while it is being typed.
///
/// Not a TextInput. The panel already owns the keyboard — the picker hands it
/// every key — and a focused field inside it would have to win that back and
/// give it up again cleanly. So the panel collects the letters itself and this
/// row only draws them, which is a caret and a string rather than a focus
/// fight.
Item {
    id: row

    required property string draft
    property bool selected: true

    implicitHeight: 44

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.42
        elide: Text.ElideRight
        text: "Name"
        color: Colors.foreground
        font.family: Style.textFont
        font.pixelSize: Style.textSize
    }

    Rectangle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(parent.width * 0.56, 260)
        height: 30
        radius: Style.picker.entryRadius + 4
        color: "transparent"
        border.width: 3
        border.color: Colors.selected

        Text {
            id: typed

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 20
            elide: Text.ElideLeft
            text: row.draft
            color: Colors.foreground
            font.family: Style.textFont
            font.pixelSize: Style.textSize * 0.9
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: row.draft === ""
            text: "Enter to save, Esc to drop it"
            color: Colors.foreground
            opacity: 0.4
            font.family: Style.textFont
            font.pixelSize: Style.textSize * 0.9
        }

        /// Sits after the last letter, and blinks the way the picker's does.
        Rectangle {
            x: Math.min(10 + typed.implicitWidth + 2, parent.width - 6)
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: parent.height * 0.55
            color: Colors.foreground

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: true

                NumberAnimation {
                    to: 0
                    duration: 480
                }
                NumberAnimation {
                    to: 1
                    duration: 480
                }
            }
        }
    }
}
