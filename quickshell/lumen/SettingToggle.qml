import QtQuick

/// A boolean of the settings, as a pill that slides. Shares the row shape of
/// SettingSlider so a group can mix the two without the labels jumping around.
Item {
    id: toggle

    required property string label
    required property string group
    required property string key
    property bool selected: false

    readonly property bool value: Settings[toggle.group][toggle.key]

    function flip() {
        Settings[toggle.group][toggle.key] = !toggle.value;
    }

    implicitHeight: 44

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.42
        elide: Text.ElideRight
        text: toggle.label
        color: Colors.foreground
        opacity: toggle.selected ? 1 : 0.75
        font.family: Style.textFont
        font.pixelSize: Style.textSize
    }

    Rectangle {
        id: pill

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        height: 26
        radius: height / 2
        color: toggle.value ? Colors.selected : "transparent"
        border.width: 3
        border.color: toggle.value ? Colors.selected : Colors.foreground

        Behavior on color {
            ColorAnimation {
                duration: Style.fadeDuration
            }
        }

        Rectangle {
            y: (parent.height - height) / 2
            x: toggle.value ? parent.width - width - 5 : 5
            width: 16
            height: 16
            radius: height / 2
            color: toggle.value ? Colors.background : Colors.foreground

            Behavior on x {
                NumberAnimation {
                    duration: Style.moveDuration
                    easing.type: Style.springEasing
                    easing.overshoot: Style.overshoot(1)
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.flip()
        }
    }
}
