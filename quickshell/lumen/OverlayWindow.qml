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

    /// A second card, to the right of the first one. It is where the settings
    /// panel goes: same window, so the panel and whatever it is restyling share
    /// one keyboard focus and one closing animation.
    property alias aside: aside.data
    property real asideWidth: 0
    property bool asideOpen: false
    /// As tall as the card it sits next to, but never so short that the panel
    /// has no room — the mode menu is only 160px high.
    property real asideHeight: Math.max(win.cardHeight, 640)

    /// The pair slides apart to make room rather than the panel covering the
    /// card, so nothing you are adjusting is ever hidden behind the sliders.
    readonly property real asideShift: win.asideOpen ? (win.asideWidth + 18) / 2 : 0

    /// Set once a choice has been made, so the panel leaves with the card.
    property bool closing: false

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

    /// Frosted windows: the compositor blurs what is behind them, following the
    /// cards rather than the surface — the surface covers the whole screen, and
    /// blurring all of it would frost the desktop rather than the picker.
    ///
    /// It only shows through once Color → Background opacity is under 1, and it
    /// needs a compositor that speaks `ext-background-effect`; where that is
    /// missing, asking for it is simply ignored.
    BackgroundEffect.blurRegion: Settings.value("colors", "blur") ? blurRegion : null

    Region {
        id: blurRegion

        item: card
        // The corner of whichever window this is, so the frosted patch cannot
        // end up rounder or squarer than the card it sits under.
        radius: Settings.value("shape", "windowRadius")

        Region {
            // Empty while the panel is folded away, or the blur would sit on
            // its own in the middle of the screen.
            item: win.asideOpen ? aside : null
            radius: Settings.value("shape", "windowRadius")
        }
    }

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
        anchors.horizontalCenterOffset: -win.asideShift
        width: win.cardWidth
        height: win.cardHeight
        focus: true

        Behavior on anchors.horizontalCenterOffset {
            NumberAnimation {
                duration: Style.moveDuration
                easing.type: Easing.OutCubic
            }
        }

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
            easing.type: Style.springEasing
            easing.overshoot: Style.overshoot(0.1)
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
                win.closing = true;
            }
        }
    }

    /// The settings panel. Mirrors the card: same height, same entrance, and it
    /// slides out from underneath it rather than appearing beside it.
    Item {
        id: aside

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: win.asideOpen ? win.cardWidth / 2 + 18 - win.asideShift + win.asideWidth / 2 : 0
        width: win.asideWidth
        height: win.asideHeight
        visible: opacity > 0
        opacity: win.asideOpen && !win.closing ? 1 : 0
        scale: win.asideOpen && !win.closing ? 1 : 0.94
        transformOrigin: Item.Center

        Behavior on anchors.horizontalCenterOffset {
            NumberAnimation {
                duration: Style.moveDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Style.moveDuration
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Style.moveDuration
                easing.type: Style.springEasing
                easing.overshoot: Style.overshoot(0.1)
            }
        }
    }
}
