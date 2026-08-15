import QtQuick
import Quickshell
import Quickshell.Wayland

/// The bit both windows have in common: a fullscreen, transparent layer-shell
/// surface with a centered card on it.
///
/// rofi is a normal window the compositor centers; a Quickshell config draws on
/// a layer surface instead, so the card is centered by hand. The surface is
/// anchored to all four edges but keeps the default exclusion handling, so it
/// centers inside whatever the bar leaves free — exactly where rofi appeared.
PanelWindow {
    id: win

    required property real cardWidth
    required property real cardHeight
    /// Suffix of the layer-shell namespace, so window rules can tell the two apart.
    required property string windowName

    /// Anything declared inside the window lands on the card.
    default property alias content: card.data

    /// Keys that reached the card, either because nothing else was focused or
    /// because the focused item ignored them. `Keys` only attaches to items, so
    /// the card forwards them here.
    signal keyPressed(var event)

    /// What holds the keyboard once the window is up. A declarative `focus: true`
    /// is not enough for anything nested inside the card: the card claims the
    /// focus of the window when it completes, which is after its children have
    /// asked for it. Whoever is named here is given the focus afterwards.
    property Item initialFocus: null

    Component.onCompleted: (win.initialFocus ?? card).forceActiveFocus()

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: `lumen-${win.windowName}`
    // Same as rofi's keyboard grab: every keystroke belongs to the picker while
    // it is open, so typing in the search field cannot leak to the window below.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    /// Clicking outside the card cancels, the way clicking off rofi does.
    MouseArea {
        anchors.fill: parent
        onClicked: Result.cancel()
    }

    Item {
        id: card

        anchors.centerIn: parent
        width: win.cardWidth
        height: win.cardHeight
        focus: true

        Keys.onPressed: event => win.keyPressed(event)

        // Swallows the clicks that land on the card but not on anything in it,
        // so they do not reach the cancelling MouseArea underneath. Declared
        // first, which leaves it below everything the window puts on the card.
        MouseArea {
            anchors.fill: parent
        }

        // ── Entrance and exit ──────────────────────────────────────────
        // rofi appears in one frame. This is the one place the Quickshell
        // version deliberately differs before anything is even drawn: the card
        // springs up, and folds back once a wallpaper has been picked.
        opacity: 0
        scale: 0.94
        transformOrigin: Item.Center

        NumberAnimation on opacity {
            id: fadeIn
            to: 1
            duration: Style.enterDuration
            easing.type: Easing.OutCubic
        }

        NumberAnimation on scale {
            id: riseIn
            to: 1
            duration: Style.enterDuration
            easing.type: Easing.OutBack
            easing.overshoot: 1.1
        }

        ParallelAnimation {
            id: closeAnimation

            NumberAnimation {
                target: card
                property: "opacity"
                to: 0
                duration: Style.exitDuration
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: card
                property: "scale"
                to: 0.96
                duration: Style.exitDuration
                easing.type: Easing.InCubic
            }
        }

        Connections {
            target: Result
            function onClosing() {
                // Stop the entrance in case a choice was made mid-flight.
                fadeIn.stop();
                riseIn.stop();
                closeAnimation.start();
            }
        }
    }
}
