pragma ComponentBehavior: Bound

import QtQuick

/// One setting picked from a short list, as a row of pills.
///
/// Not a dropdown on purpose: three options fit on a row, and a menu would hide
/// two of them behind a click. Shares the row shape of SettingToggle and
/// SettingSlider so a group can mix the three without the labels jumping around.
Item {
    id: choice

    required property string label
    /// The group and key inside Settings, e.g. `"colors"` / `"palette"`.
    required property string group
    required property string key
    /// `{ value, label }` pairs, in the order they are drawn.
    required property var options
    property bool selected: false

    readonly property string value: Settings[choice.group][choice.key]
    /// Where the stored value sits in the list. A value that is not in it —
    /// a hand-edited settings file — reads as the first, so h and l still work.
    readonly property int index: Math.max(0, choice.options.findIndex(option => option.value === choice.value))

    /// Walks the list by `steps`, wrapping. The panel passes ten of them when
    /// Shift is held, which on a list this short is still just a step.
    function nudge(steps: real) {
        const count = choice.options.length;
        const next = (choice.index + Math.round(steps)) % count;
        choice.set(choice.options[(next + count) % count].value);
    }

    /// Enter, and h/l through the panel: the next one along.
    function flip() {
        choice.nudge(1);
    }

    function set(value: string) {
        Settings[choice.group][choice.key] = value;
    }

    implicitHeight: 44

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.42
        elide: Text.ElideRight
        text: choice.label
        color: Colors.foreground
        opacity: choice.selected ? 1 : 0.75
        font.family: Style.textFont
        font.pixelSize: Style.textSize
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
            model: choice.options

            Rectangle {
                id: pill

                required property var modelData

                readonly property bool on: pill.modelData.value === choice.value

                implicitWidth: name.implicitWidth + 22
                implicitHeight: 26
                radius: height / 2
                color: pill.on ? Colors.selected : "transparent"
                border.width: 3
                border.color: pill.on ? Colors.selected : Colors.foreground
                opacity: pill.on ? 1 : 0.5

                Behavior on color {
                    ColorAnimation {
                        duration: Style.fadeDuration
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.fadeDuration
                    }
                }

                Text {
                    id: name

                    anchors.centerIn: parent
                    text: pill.modelData.label
                    color: pill.on ? Colors.background : Colors.foreground
                    font.family: Style.textFont
                    font.pixelSize: Style.textSize * 0.8
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: choice.set(pill.modelData.value)
                }
            }
        }
    }
}
