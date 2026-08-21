import QtQuick

/// One saved configuration: its name, a button that puts it back, one that
/// writes what is on screen into it, and a cross that throws it away.
///
/// Deleting is armed by pressing twice, the same bargain the Tags tab makes for
/// a re-tag — it removes a file, and the panel has no undo. *Update* is not: it
/// is the button you reach for after every nudge of a slider, and a preset you
/// have to confirm twice to keep in step is one you stop keeping in step.
Item {
    id: preset

    required property string name
    /// Whether there is a file behind the row. `Default` is the rofi
    /// measurements rather than a preset on disk, so it can be neither written
    /// over nor deleted — both buttons key off this.
    property bool stored: true
    property bool busy: false
    property bool selected: false

    property var apply: null
    /// Writes the configuration on screen over this preset.
    property var revise: null
    property var erase: null

    property bool armed: false

    /// Walking away forgets that the cross was armed.
    onSelectedChanged: {
        if (!preset.selected)
            preset.armed = false;
    }

    /// Enter on the row, and a click on the button.
    function flip() {
        preset.armed = false;
        if (preset.apply)
            preset.apply();
    }

    /// `u` on the row, and a click on *Update*.
    ///
    /// Not called `update`: every Item has one of those already, so the panel's
    /// `item.overwrite ? …` — which is how it tells the rows that can do a thing
    /// from the rows that cannot — would have been true of every row on screen,
    /// and pressing `u` on a slider would have quietly asked it to repaint.
    function overwrite() {
        preset.armed = false;
        if (preset.stored && preset.revise)
            preset.revise();
    }

    /// `x` or Delete on the row, and a click on the cross.
    function remove() {
        if (!preset.stored)
            return;
        if (!preset.armed) {
            preset.armed = true;
            return;
        }
        preset.armed = false;
        if (preset.erase)
            preset.erase();
    }

    implicitHeight: 44

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - buttons.width - 16
        elide: Text.ElideRight
        text: preset.name
        color: Colors.foreground
        opacity: preset.selected ? 1 : 0.75
        font.family: Style.textFont
        font.pixelSize: Style.textSize
    }

    Row {
        id: buttons

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Rectangle {
            id: cross

            visible: preset.stored
            width: preset.armed ? erase.implicitWidth + 24 : 26
            height: 26
            radius: height / 2
            color: preset.armed ? Colors.urgent : "transparent"
            border.width: 3
            border.color: Colors.urgent
            opacity: preset.armed ? 1 : 0.45

            Behavior on width {
                NumberAnimation {
                    duration: Style.fadeDuration
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: Style.fadeDuration
                }
            }

            Text {
                id: erase

                anchors.centerIn: parent
                text: preset.armed ? "Press again" : "×"
                color: preset.armed ? Colors.background : Colors.urgent
                font.family: Style.textFont
                font.pixelSize: Style.textSize * (preset.armed ? 0.8 : 1)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: preset.remove()
            }
        }

        /// Takes the whole configuration as it stands and puts it in the file,
        /// so that a look you keep tuning stays one preset rather than becoming
        /// `rounded`, `rounded 2` and `rounded final`.
        Rectangle {
            visible: preset.stored
            width: revise.implicitWidth + 26
            height: 26
            radius: height / 2
            color: "transparent"
            border.width: 3
            border.color: Colors.foreground
            opacity: 0.55

            Text {
                id: revise

                anchors.centerIn: parent
                text: "Update"
                color: Colors.foreground
                font.family: Style.textFont
                font.pixelSize: Style.textSize * 0.8
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: preset.overwrite()
            }
        }

        Rectangle {
            width: verb.implicitWidth + 26
            height: 26
            radius: height / 2
            color: preset.busy ? Colors.selected : "transparent"
            border.width: 3
            border.color: Colors.selected

            Behavior on color {
                ColorAnimation {
                    duration: Style.fadeDuration
                }
            }

            Text {
                id: verb

                anchors.centerIn: parent
                text: preset.busy ? "Loading…" : "Apply"
                color: preset.busy ? Colors.background : Colors.foreground
                font.family: Style.textFont
                font.pixelSize: Style.textSize * 0.8
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: preset.flip()
            }
        }
    }
}
