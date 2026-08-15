pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets

/// The four-way mode chooser — the Quickshell twin of `wallpaperchoise.rasi`.
///
/// Two entries are visible at a time and the other two live on a second row, the
/// same way rofi lays out four items in a two-column list that is one row tall.
/// Moving down scrolls that row into view; here it slides instead of jumping.
OverlayWindow {
    id: win

    cardWidth: Style.menu.width
    cardHeight: Style.menu.height
    windowName: "menu"

    /// The strings written to the result file are what `lumen` matches on.
    /// The glyphs are the Nerd Font codepoints the rofi menu was fed.
    readonly property var entries: [
        {
            id: "dark",
            glyph: String.fromCodePoint(0xf4ee)
        },
        {
            id: "light",
            glyph: String.fromCodePoint(0xf522)
        },
        {
            id: "time",
            glyph: String.fromCodePoint(0xf1803)
        },
        {
            id: "season",
            glyph: String.fromCodePoint(0xf1a79)
        }
    ]

    property int currentIndex: 0
    readonly property int currentColumn: currentIndex % Style.menu.columns
    readonly property int currentRow: Math.floor(currentIndex / Style.menu.columns)
    readonly property int rowCount: Math.ceil(entries.length / Style.menu.columns)

    function move(columns: int, rows: int) {
        const column = Math.max(0, Math.min(Style.menu.columns - 1, win.currentColumn + columns));
        const row = Math.max(0, Math.min(win.rowCount - 1, win.currentRow + rows));
        const index = row * Style.menu.columns + column;
        if (index < win.entries.length)
            win.currentIndex = index;
    }

    function activate() {
        Result.accept(win.entries[win.currentIndex].id);
    }

    // Nothing is typed here, so the vim keys need no mode: `hjkl` move, `q`
    // quits. The picker that comes next spells them the same way.
    onKeyPressed: event => {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            Result.cancel();
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            win.move(-1, 0);
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            win.move(1, 0);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            win.move(0, -1);
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            win.move(0, 1);
            break;
        case Qt.Key_Tab:
            win.currentIndex = (win.currentIndex + 1) % win.entries.length;
            break;
        case Qt.Key_Backtab:
            win.currentIndex = (win.currentIndex + win.entries.length - 1) % win.entries.length;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            win.activate();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    /// `window { background-image: url(…, width); border: 3px; border-radius: 20px; }`
    ClippingRectangle {
        anchors.fill: parent
        radius: Style.menu.radius
        color: Colors.background
        border.width: Style.menu.border
        border.color: Colors.urgent
        contentUnderBorder: true // the wallpaper runs to the very edge, as in rasi

        WallpaperBackdrop {}

        /// The white bar: the element backgrounds, which butt against each other
        /// and read as a single capsule. It also clips the second row while it
        /// slides in.
        ClippingRectangle {
            x: Style.menu.inset
            y: Style.menu.inset
            width: Style.menu.barWidth
            height: Style.menu.barHeight
            radius: height / 2
            color: Colors.background

            Item {
                id: rows

                width: parent.width
                height: Style.menu.cellHeight * win.rowCount
                // Keeps the selected row in view; rofi scrolls here too, in one step.
                y: -win.currentRow * Style.menu.cellHeight

                Behavior on y {
                    NumberAnimation {
                        duration: Style.scrollDuration
                        easing.type: Easing.OutCubic
                    }
                }

                /// Selected element. One pill for the whole menu rather than one
                /// per entry, so that it slides from entry to entry.
                Rectangle {
                    id: pill

                    x: win.currentColumn * Style.menu.cellWidth + Style.menu.pillInset
                    y: win.currentRow * Style.menu.cellHeight + Style.menu.pillInset
                    width: Style.menu.cellWidth - Style.menu.pillInset * 2
                    height: Style.menu.cellHeight - Style.menu.pillInset * 2
                    radius: height / 2
                    color: Colors.selected

                    Behavior on x {
                        NumberAnimation {
                            duration: Style.moveDuration
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.05
                        }
                    }
                    Behavior on y {
                        NumberAnimation {
                            duration: Style.scrollDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    /// `element-text { border: 9px; border-radius: 50px; }` — a ring
                    /// of window background inside the pill. It is drawn on every
                    /// element in rofi, but white on white is invisible, so only
                    /// the selected one ever shows.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Style.menu.ringInset
                        radius: height / 2
                        color: "transparent"
                        border.width: Style.menu.ringWidth
                        border.color: Colors.background
                    }
                }

                Repeater {
                    model: win.entries

                    delegate: Item {
                        id: cell

                        required property int index
                        required property var modelData
                        readonly property bool current: win.currentIndex === cell.index

                        x: (cell.index % Style.menu.columns) * Style.menu.cellWidth
                        y: Math.floor(cell.index / Style.menu.columns) * Style.menu.cellHeight
                        width: Style.menu.cellWidth
                        height: Style.menu.cellHeight

                        Text {
                            id: glyph

                            anchors.centerIn: parent
                            text: cell.modelData.glyph
                            color: Colors.foreground
                            font.family: Style.iconFont
                            font.pixelSize: Style.iconSize

                            // A nudge as the selection lands on the entry, and a
                            // smaller one while the pointer is over it.
                            scale: cell.current ? 1.08 : (hover.hovered ? 1.04 : 1)

                            Behavior on scale {
                                NumberAnimation {
                                    duration: Style.fadeDuration
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 2
                                }
                            }
                        }

                        HoverHandler {
                            id: hover
                            cursorShape: Qt.PointingHandCursor // element { cursor: pointer; }
                            onHoveredChanged: {
                                if (hovered)
                                    win.currentIndex = cell.index;
                            }
                        }

                        TapHandler {
                            onTapped: {
                                win.currentIndex = cell.index;
                                win.activate();
                            }
                        }
                    }
                }
            }
        }
    }
}
