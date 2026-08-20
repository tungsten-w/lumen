import QtQuick

/// The scrollbar of a Flickable, drawn by hand like every other widget here.
///
/// rofi kept 24px free on the right of its grid for one and then never drew it.
/// That is fine on a list you can see whole, and misleading on one you cannot:
/// nothing in the settings panel said there were more rows under the last one,
/// so a tab looked like it ended wherever the card did.
///
/// It fades out entirely when the content fits, so a short tab looks exactly as
/// it did before there was a bar at all.
Item {
    id: bar

    required property Flickable flickable

    /// How far the flickable can travel, i.e. how much of it is out of sight.
    readonly property real range: Math.max(0, bar.flickable.contentHeight - bar.flickable.height)
    readonly property bool needed: bar.range > 0.5

    /// The handle is as tall a share of the track as the visible rows are of all
    /// of them — the usual scrollbar bargain — but never so short it cannot be
    /// grabbed, on a tab long enough for that to happen.
    readonly property real minimumHandle: 28
    readonly property real handleHeight: {
        if (!bar.needed || bar.flickable.contentHeight <= 0)
            return bar.height;
        const share = bar.flickable.height / bar.flickable.contentHeight;
        return Math.max(bar.minimumHandle, Math.min(bar.height, bar.height * share));
    }
    readonly property real travel: Math.max(0, bar.height - bar.handleHeight)
    readonly property real handleY: bar.range > 0 ? bar.travel * Math.max(0, Math.min(1, bar.flickable.contentY / bar.range)) : 0

    /// True while the handle is being dragged. The panel switches its scrolling
    /// animation off for the duration: an eased contentY makes the handle lag
    /// behind the cursor that is supposed to be carrying it.
    readonly property bool dragging: mouse.pressed

    /// Wide enough to be worth aiming at; the ribbon drawn inside is thinner.
    implicitWidth: 12

    opacity: bar.needed ? 1 : 0
    visible: bar.opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: Style.fadeDuration
        }
    }

    /// Puts the top of the handle at `top`, in track coordinates.
    function scrollTo(top: real) {
        if (bar.travel <= 0)
            return;
        bar.flickable.contentY = Math.max(0, Math.min(1, top / bar.travel)) * bar.range;
    }

    // Track.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 4
        height: parent.height
        radius: width / 2
        color: Colors.foreground
        opacity: 0.13
    }

    Rectangle {
        id: handle

        readonly property bool lit: mouse.containsMouse || bar.dragging

        anchors.horizontalCenter: parent.horizontalCenter
        y: bar.handleY
        width: handle.lit ? 8 : 4
        height: bar.handleHeight
        radius: width / 2
        color: handle.lit ? Colors.selected : Colors.foreground
        opacity: handle.lit ? 1 : 0.45

        Behavior on width {
            NumberAnimation {
                duration: Style.fadeDuration
            }
        }
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
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: bar.needed
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // The rows underneath select themselves on hover; without this, dragging
        // the handle across them would drag the selection along with it.
        preventStealing: true

        /// Where inside the handle it was grabbed, so the point under the cursor
        /// stays under it. Pressing the track instead centres the handle on the
        /// cursor and carries on from there.
        property real grabbed: 0

        onPressed: event => {
            const inside = event.y >= bar.handleY && event.y <= bar.handleY + bar.handleHeight;
            mouse.grabbed = inside ? event.y - bar.handleY : bar.handleHeight / 2;
            bar.scrollTo(event.y - mouse.grabbed);
        }

        onPositionChanged: event => {
            if (mouse.pressed)
                bar.scrollTo(event.y - mouse.grabbed);
        }
    }
}
