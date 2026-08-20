import QtQuick

/// A row that does something instead of storing something.
///
/// The only rows in the panel that are not settings: they start a job and then
/// say how it went. Same shape as SettingToggle so the two sit together without
/// the labels jumping around.
Item {
    id: action

    required property string label
    /// What the button says when it is idle.
    required property string verb
    property string busyVerb: "Working…"
    property bool busy: false
    property bool ready: true
    /// Run when the row is triggered — by Enter, by h/l, or by a click.
    property var run: null

    /// Set on a row whose job is not casually undone: the first press arms it,
    /// the second one runs it, and walking away disarms it.
    property bool confirms: false
    property bool armed: false

    property bool selected: false

    onSelectedChanged: {
        if (!action.selected)
            action.armed = false;
    }

    function flip() {
        if (!action.ready || action.busy)
            return;
        if (action.confirms && !action.armed) {
            action.armed = true;
            return;
        }
        action.armed = false;
        if (action.run)
            action.run();
    }

    implicitHeight: 44

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - button.width - 16
        elide: Text.ElideRight
        text: action.label
        color: Colors.foreground
        opacity: action.selected ? 1 : 0.75
        font.family: Style.textFont
        font.pixelSize: Style.textSize
    }

    Rectangle {
        id: button

        readonly property bool filled: action.armed || action.busy

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: caption.implicitWidth + 26
        height: 26
        radius: height / 2
        color: button.filled ? Colors.selected : "transparent"
        border.width: 3
        border.color: action.armed ? Colors.urgent : Colors.selected
        opacity: action.ready ? 1 : 0.4

        Behavior on color {
            ColorAnimation {
                duration: Style.fadeDuration
            }
        }

        Text {
            id: caption

            anchors.centerIn: parent
            text: action.busy ? action.busyVerb : (action.armed ? "Press again" : action.verb)
            color: button.filled ? Colors.background : Colors.foreground
            font.family: Style.textFont
            font.pixelSize: Style.textSize * 0.8
        }

        MouseArea {
            anchors.fill: parent
            enabled: action.ready && !action.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: action.flip()
        }
    }
}
