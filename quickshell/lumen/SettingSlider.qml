import QtQuick

/// One number of the settings, as a track you can drag or nudge.
///
/// Written by hand rather than pulled from QtQuick.Controls: a Control would
/// come with its own style, and this has to look like the rest of the picker —
/// the palette, the pill shapes and the same easing as everything else.
Item {
    id: slider

    required property string label
    /// The group and key inside Settings, e.g. `"shape"` / `"windowRadius"`.
    property string group: ""
    property string key: ""
    /// A pair of functions to use instead of `group`/`key`, for the values that
    /// are not stored as plain numbers — the channels of a pinned colour.
    property var read: null
    property var write: null

    required property real from
    required property real to
    /// Rounding of the value. 1 for counts, 0.5 or 0.05 for the finer knobs.
    property real step: 1
    /// Appended to the number in the readout, e.g. `"px"` or `"ms"`.
    property string suffix: ""
    property bool selected: false

    readonly property real value: slider.current()

    /// The value as stored, rather than as bound. A binding settles a frame
    /// after the write, so nudging off `value` would drop every step that
    /// arrives before it has caught up.
    function current(): real {
        return slider.read ? slider.read() : Settings[slider.group][slider.key];
    }
    readonly property real fraction: Math.max(0, Math.min(1, (slider.value - slider.from) / (slider.to - slider.from)))

    /// Nudges the value by `steps` steps — the panel passes ten of them when
    /// Shift is held.
    function nudge(steps: real) {
        slider.set(slider.current() + steps * slider.step);
    }

    function set(raw: real) {
        const clamped = Math.max(slider.from, Math.min(slider.to, raw));
        // Rounding on the step keeps 0.30000000000000004 out of the JSON.
        const stepped = Math.round(clamped / slider.step) * slider.step;
        const rounded = Math.round(stepped * 1000) / 1000;

        if (slider.write)
            slider.write(rounded);
        else
            Settings[slider.group][slider.key] = rounded;
    }

    implicitHeight: 44

    Text {
        id: name

        x: 0
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.42
        elide: Text.ElideRight
        text: slider.label
        color: Colors.foreground
        opacity: slider.selected ? 1 : 0.75
        font.family: Style.textFont
        font.pixelSize: Style.textSize
    }

    Item {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        x: name.width + 12
        width: parent.width - x - readout.width - 12
        height: parent.height

        Rectangle {
            id: groove

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: height / 2
            color: Colors.foreground
            opacity: 0.18
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, groove.width * slider.fraction)
            height: 6
            radius: height / 2
            color: Colors.selected

            Behavior on width {
                NumberAnimation {
                    duration: Style.fadeDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        Rectangle {
            id: handle

            x: groove.width * slider.fraction - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: height / 2
            color: Colors.selected
            border.width: 3
            border.color: Colors.background
            scale: slider.selected || drag.pressed ? Style.liftBy(10) : 1

            Behavior on x {
                NumberAnimation {
                    duration: Style.fadeDuration
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Style.fadeDuration
                    easing.type: Style.springEasing
                    easing.overshoot: Style.overshoot(1)
                }
            }
        }

        MouseArea {
            id: drag

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: event => slider.set(slider.from + (event.x / groove.width) * (slider.to - slider.from))
            onPositionChanged: event => {
                if (drag.pressed)
                    slider.set(slider.from + (event.x / groove.width) * (slider.to - slider.from));
            }
        }
    }

    Text {
        id: readout

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        width: 74
        // Integers read as integers; the fine knobs keep their decimals.
        text: (slider.step >= 1 ? slider.value.toFixed(0) : slider.value.toFixed(slider.step >= 0.1 ? 1 : 2)) + slider.suffix
        color: slider.selected ? Colors.selected : Colors.foreground
        opacity: slider.selected ? 1 : 0.75
        font.family: Style.textFont
        font.pixelSize: Style.textSize
    }
}
