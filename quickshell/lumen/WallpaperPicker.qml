pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/// The thumbnail grid — the Quickshell twin of `wallpaper.rasi`.
///
/// `lumen` writes the wallpaper list to a JSON file and passes its path in
/// `$LUMEN_ITEMS`; the selected wallpaper's absolute path goes back through
/// Result. That replaces the `name\0icon\x1f/path/thumb.png` lines it used to
/// pipe into rofi's dmenu.
OverlayWindow {
    id: win

    cardWidth: Style.picker.width
    cardHeight: Style.picker.height
    windowName: "picker"
    // The window opens ready to be typed into.
    initialFocus: search

    /// Opened with Ctrl+, and by `lumen --settings`. It is a panel of this
    /// window rather than a window of its own, so it shares the keyboard and
    /// every change it makes is drawn on the grid next to it immediately.
    asideWidth: 470

    /// True when the picker is only there to show what the settings do; Enter
    /// and clicks pick nothing, so `lumen --settings` cannot change a wallpaper
    /// by accident. Set by shell.qml for the settings mode.
    property bool preview: false

    aside: SettingsPanel {
        id: settings

        scope: "picker"

        anchors.fill: parent
        // Closing the panel normally hands the keyboard back to the grid. In
        // preview mode there is no grid to hand it back to — nothing can be
        // picked there — so the window goes with it.
        onClosed: {
            if (win.preview)
                Result.cancel();
            else
                win.asideOpen = false;
        }
    }

    /// Every wallpaper in the directory: `{ name, path, thumb }`.
    property var wallpapers: []
    /// The ones the search field currently keeps.
    property var matches: []
    property int currentIndex: 0

    /// True only while the grid is first filling in. Thumbnails that show up
    /// later — because they were scrolled to, or because the search changed —
    /// fade in straight away instead of queueing behind the stagger.
    property bool staggering: true

    Timer {
        running: true
        interval: Style.staggerCap + Style.enterDuration
        onTriggered: win.staggering = false
    }

    FileView {
        id: items
        path: Quickshell.env("LUMEN_ITEMS") ?? ""
        preload: true
        blockLoading: true // the grid has nothing to show until this is read
        printErrors: false

        onLoaded: {
            const parsed = JSON.parse(items.text());
            win.wallpapers = parsed.items ?? [];
            win.matches = win.wallpapers;
        }
    }

    /// Typed into the search field instead of a wallpaper name, this opens the
    /// settings — the same panel Ctrl+, and `lumen --settings` open.
    ///
    /// It is safe to spend the word: no wallpaper here is called anything like
    /// it, and a search that did match one would still be one keystroke away
    /// from being something else.
    readonly property var commands: ["settings"]

    /// Runs `query` if it is one of them, and says whether it did. Anything a
    /// command starts with counts as being on the way to it, which is what the
    /// hint over the grid reacts to.
    function isCommandPrefix(query: string): bool {
        const typed = query.trim().toLowerCase();
        return typed.length > 0 && win.commands.some(command => command.startsWith(typed));
    }

    function runCommand(query: string): bool {
        if (!win.commands.includes(query.trim().toLowerCase()))
            return false;

        // Clearing the field re-enters filter(), which is harmless: an empty
        // query is no longer a command.
        search.text = "";
        win.asideOpen = true;
        return true;
    }

    /// rofi's default matcher: every whitespace-separated term has to appear
    /// somewhere in the entry, case-insensitively.
    function filter(query: string) {
        if (win.runCommand(query))
            return;

        const terms = query.toLowerCase().split(/\s+/).filter(term => term.length > 0);
        win.matches = terms.length === 0 ? win.wallpapers : win.wallpapers.filter(wallpaper => {
            const name = wallpaper.name.toLowerCase();
            return terms.every(term => name.includes(term));
        });
        win.currentIndex = 0;
        grid.scrollTo(0);
    }

    function move(columns: int, rows: int) {
        win.select(win.currentIndex + columns + rows * Style.picker.columns);
    }

    /// Selects `index` if it exists, and scrolls just far enough to show it.
    function select(index: int) {
        if (index >= 0 && index < win.matches.length)
            win.currentIndex = index;
        grid.reveal(win.currentIndex);
    }

    function activate() {
        if (win.preview)
            return;
        const wallpaper = win.matches[win.currentIndex];
        if (wallpaper)
            Result.accept(wallpaper.path);
    }

    /// Ctrl+, — the shortcut editors use, and the one key that always means the
    /// same thing whichever half of the window has the cursor.
    function isSettingsKey(event): bool {
        return event.key === Qt.Key_Comma && (event.modifiers & Qt.ControlModifier) !== 0;
    }

    // ── Keys ───────────────────────────────────────────────────────────
    //
    // A grid you search by typing cannot also take `hjkl` as movement: half the
    // wallpapers here start with an h, a j, a k or an l. So the picker has vim's
    // two modes, and opens in insert — the name can be typed the moment the
    // window is up, which is the fast path.
    //
    //   insert   type to filter · Esc → normal
    //   normal   h j k l  move        gg / G   first / last
    //            Ctrl+d / Ctrl+u  half a screen
    //            i or /   back to the search field
    //            q or Esc close
    //
    // Arrow keys, Enter, Home/End/PageUp/PageDown and rofi's own Ctrl+j /
    // Ctrl+k work from either mode, so nothing forces you into normal mode.

    /// True while the search field takes the keystrokes.
    property bool inserting: true

    /// The bindings that mean the same thing in both modes. Returns whether the
    /// key was used up.
    function sharedKey(event): bool {
        const control = (event.modifiers & Qt.ControlModifier) !== 0;
        const half = Math.max(1, Math.floor(grid.visibleRows / 2));

        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            win.activate();
            return true;
        case Qt.Key_Left:
            win.move(-1, 0);
            return true;
        case Qt.Key_Right:
            win.move(1, 0);
            return true;
        case Qt.Key_Up:
            win.move(0, -1);
            return true;
        case Qt.Key_Down:
            win.move(0, 1);
            return true;
        case Qt.Key_PageUp:
            win.move(0, -grid.visibleRows);
            return true;
        case Qt.Key_PageDown:
            win.move(0, grid.visibleRows);
            return true;
        case Qt.Key_Home:
            win.select(0);
            return true;
        case Qt.Key_End:
            win.select(win.matches.length - 1);
            return true;
        // The same keys as normal mode, held with Control: they reach the grid
        // from inside the search field, which is where rofi's Ctrl+j / Ctrl+k
        // already put row movement.
        case Qt.Key_H:
            if (control) {
                win.move(-1, 0);
                return true;
            }
            break;
        case Qt.Key_L:
            if (control) {
                win.move(1, 0);
                return true;
            }
            break;
        case Qt.Key_J:
            if (control) {
                win.move(0, 1);
                return true;
            }
            break;
        case Qt.Key_K:
            if (control) {
                win.move(0, -1);
                return true;
            }
            break;
        case Qt.Key_D:
            if (control) {
                win.move(0, half);
                return true;
            }
            break;
        case Qt.Key_U:
            if (control) {
                win.move(0, -half);
                return true;
            }
            break;
        }
        return false;
    }

    /// Where a keystroke goes. Kept as a function rather than inline in the
    /// handler so that it is one thing to read — and so it can be exercised
    /// without a keyboard.
    ///
    /// Returns whether the key was used up; anything else falls through to the
    /// search field as text.
    function routeKey(event): bool {
        if (win.isSettingsKey(event)) {
            win.asideOpen = !win.asideOpen;
            return true;
        }

        // While the panel is out it owns the keyboard, so that h and l adjust
        // the setting under the cursor instead of walking the grid. Esc gives
        // the keyboard back. Whatever it does not use is swallowed all the same:
        // a letter typed over a slider must not land in the search field behind.
        if (win.asideOpen) {
            settings.handleKey(event);
            return true;
        }

        if (win.sharedKey(event))
            return true;

        if (!win.inserting)
            return win.normalKey(event);

        // Esc leaves insert mode without dropping the query, so you can filter,
        // step out, and walk what is left. From normal mode a second Esc closes
        // the picker.
        if (event.key === Qt.Key_Escape) {
            win.inserting = false;
            return true;
        }

        return false;
    }

    /// Normal mode. Everything lands here, used or not: a stray letter must not
    /// reach the search field, exactly as it would not reach a vim buffer.
    function normalKey(event): bool {
        switch (event.key) {
        case Qt.Key_H:
            win.move(-1, 0);
            break;
        case Qt.Key_L:
            win.move(1, 0);
            break;
        case Qt.Key_J:
            win.move(0, 1);
            break;
        case Qt.Key_K:
            win.move(0, -1);
            break;
        case Qt.Key_G:
            // `G` for the last wallpaper, `g` for the first — and since a lone
            // `g` already jumps to the top, `gg` spells the same thing.
            win.select(event.modifiers & Qt.ShiftModifier ? win.matches.length - 1 : 0);
            break;
        case Qt.Key_Slash:
        case Qt.Key_I:
        case Qt.Key_A:
            win.inserting = true;
            break;
        case Qt.Key_Q:
        case Qt.Key_Escape:
            Result.cancel();
            break;
        }
        return true;
    }

    /// `window { background-color: @background; border: 3px; border-radius: 20px; }`
    Rectangle {
        anchors.fill: parent
        radius: Style.picker.radius
        color: Colors.background
        border.width: Style.picker.border
        border.color: Colors.urgent

        /// `inputbar` — the wallpaper on screen right now, with the search field
        /// floating over it.
        ClippingRectangle {
            x: Style.picker.headerX
            y: Style.picker.headerY
            width: Style.picker.headerWidth
            height: Style.picker.headerHeight
            radius: Style.picker.headerRadius
            color: Colors.background
            border.width: Style.picker.border
            border.color: Colors.urgent
            contentUnderBorder: true

            WallpaperBackdrop {}

            /// `entry` — the search field.
            Rectangle {
                id: entry

                x: Style.picker.entryX
                y: Style.picker.entryY
                width: Style.picker.entryWidth
                height: Style.picker.entryHeight
                radius: Style.picker.entryRadius
                color: Colors.background
                border.width: Style.picker.border
                // Pink while it is taking your keystrokes, the selection's own
                // teal once Esc has handed them to the grid. Together with the
                // block cursor below, that is the whole mode indicator.
                border.color: win.inserting ? Colors.urgent : Colors.selected

                Behavior on border.color {
                    ColorAnimation {
                        duration: Style.fadeDuration
                    }
                }

                // Widens a little while it holds a query, so it is obvious the
                // grid is filtered rather than short.
                scale: search.text.length > 0 ? 1.02 : 1
                Behavior on scale {
                    NumberAnimation {
                        duration: Style.fadeDuration
                        easing.type: Easing.OutCubic
                    }
                }

                TextInput {
                    id: search

                    anchors.fill: parent
                    anchors.leftMargin: Style.picker.entryPadding
                    anchors.rightMargin: Style.picker.entryPadding
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    focus: true

                    color: Colors.foreground
                    font.family: Style.textFont
                    font.pixelSize: Style.textSize
                    selectionColor: Colors.selected
                    selectedTextColor: Colors.foreground

                    onTextChanged: win.filter(text)

                    // A thin bar in insert mode, a vim block in normal mode.
                    // Drawn behind the character it sits on, so the letter stays
                    // readable through it.
                    cursorDelegate: Rectangle {
                        id: caret

                        /// Driven by the blink below, and only listened to in
                        /// insert mode — the block stays put so it reads as a
                        /// position rather than as something waiting for input.
                        property real blink: 1

                        width: win.inserting ? Style.picker.caretWidth : Style.picker.blockWidth
                        color: win.inserting ? Colors.foreground : Colors.selected
                        opacity: win.inserting ? caret.blink : 0.55

                        Behavior on width {
                            NumberAnimation {
                                duration: Style.fadeDuration
                                easing.type: Easing.OutCubic
                            }
                        }

                        // Qt blinks the built-in cursor for you; a delegate has
                        // to do its own.
                        SequentialAnimation on blink {
                            loops: Animation.Infinite
                            // Stops with everything else when animations are off.
                            running: win.inserting && Style.speed > 0

                            PauseAnimation {
                                duration: 600
                            }
                            NumberAnimation {
                                to: 0
                                duration: Style.fadeDuration
                            }
                            PauseAnimation {
                                duration: 300
                            }
                            NumberAnimation {
                                to: 1
                                duration: Style.fadeDuration
                            }
                        }
                    }

                    // Handled here rather than on the card, because a focused
                    // TextInput would otherwise eat the arrow keys to move its
                    // cursor. The field is a filter, not somewhere you edit
                    // prose, so the grid gets the arrows.
                    Keys.onPressed: event => event.accepted = win.routeKey(event)

                    /// `placeholder: " Wallpapers";`
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Style.picker.placeholder
                        color: Colors.foreground
                        font: search.font
                        opacity: search.text.length === 0 ? 0.55 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeDuration
                            }
                        }
                    }
                }
            }
        }

        /// What the grid area says while a command is being typed into the
        /// search field. Without it, typing `settings` looks like a search that
        /// matches nothing right up until it fires.
        Item {
            x: Style.picker.gridX
            y: Style.picker.gridY + 24
            width: Style.picker.columns * Style.picker.columnPitch
            height: Style.textSize * 2
            opacity: win.isCommandPrefix(search.text) ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeDuration
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 10

                SvgIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "enter"
                    color: Colors.selected
                    size: Style.textSize * 1.4
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "settings"
                    color: Colors.selected
                    font.family: Style.textFont
                    font.pixelSize: Style.textSize * 1.1
                }
            }
        }

        /// `listview { columns: 3; spacing: 10px; }`
        GridView {
            id: grid

            x: Style.picker.gridX
            y: Style.picker.gridY
            width: Style.picker.columns * Style.picker.columnPitch
            // Runs to the window padding and is cut mid-row there, exactly like
            // rofi's fixed-height listview.
            height: Style.picker.height - Style.picker.gridY - Style.picker.border - 15
            clip: true

            cellWidth: Style.picker.columnPitch
            cellHeight: Style.picker.rowPitch

            // contentY is animated through a Behavior, which only works if the
            // view is not also flicking itself; the wheel is handled below.
            interactive: false
            currentIndex: win.currentIndex

            model: ScriptModel {
                values: win.matches
                objectProp: "path" // lets the model diff by wallpaper, so filtering animates
            }

            Behavior on contentY {
                NumberAnimation {
                    duration: Style.scrollDuration
                    easing.type: Easing.OutCubic
                }
            }

            readonly property int visibleRows: Math.max(1, Math.floor(height / cellHeight))
            readonly property real maxContentY: Math.max(0, contentHeight - height)

            function scrollTo(y: real) {
                contentY = Math.max(0, Math.min(grid.maxContentY, y));
            }

            /// Scrolls just far enough to bring `index` fully into view.
            function reveal(index: int) {
                const top = Math.floor(index / Style.picker.columns) * grid.cellHeight;
                const bottom = top + Style.picker.elementHeight;
                if (top < grid.contentY)
                    grid.scrollTo(top);
                else if (bottom > grid.contentY + grid.height)
                    grid.scrollTo(bottom - grid.height);
            }

            WheelHandler {
                onWheel: event => {
                    grid.scrollTo(grid.contentY - event.angleDelta.y);
                    event.accepted = true;
                }
            }

            // Filtering rearranges the grid instead of redrawing it.
            displaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: Style.moveDuration
                    easing.type: Easing.OutCubic
                }
            }
            // Only opacity: a view transition assigns the property outright, and
            // animating scale here would tear down the delegate's own binding.
            remove: Transition {
                NumberAnimation {
                    property: "opacity"
                    to: 0
                    duration: Style.fadeDuration
                }
            }
            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Style.fadeDuration
                }
            }

            delegate: Item {
                id: element

                required property int index
                required property var modelData
                readonly property bool current: win.currentIndex === element.index

                width: Style.picker.elementWidth
                height: Style.picker.elementHeight

                // Lifts towards the pointer, and stays lifted while selected.
                // The whole element scales, thumbnail and selection frame
                // together, so the frame keeps the thickness rofi gives it.
                transformOrigin: Item.Center
                scale: element.current ? Style.lift : 1
                Behavior on scale {
                    NumberAnimation {
                        duration: Style.fadeDuration
                        easing.type: Easing.OutCubic
                    }
                }

                /// Selected element: `element.selected.normal` fills its whole box
                /// with `@selected-normal-background`, thumbnail padding included.
                Rectangle {
                    anchors.fill: parent
                    radius: Style.picker.elementRadius
                    color: Colors.selected
                    opacity: element.current ? 1 : 0
                    scale: element.current ? 1 : 0.96

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.fadeDuration
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.fadeDuration
                            easing.type: Style.springEasing
                            easing.overshoot: Style.overshoot(0.6)
                        }
                    }
                }

                /// `element-icon { size: 340px; border: 3px; border-radius: 25px; }`
                ClippingRectangle {
                    id: thumbnail

                    anchors.fill: parent
                    anchors.margins: Style.picker.elementPadding
                    radius: Style.picker.iconRadius
                    color: Colors.background
                    border.width: Style.picker.iconBorder
                    border.color: Colors.borderColor

                    Image {
                        // rofi fits the thumbnail inside a 340x340 icon box and
                        // the element clips it; the visible crop is therefore
                        // zoomed in rather than fitted to the element's shape.
                        anchors.centerIn: parent
                        width: Style.picker.iconBox
                        height: Style.picker.iconBox
                        fillMode: Image.PreserveAspectFit

                        source: Style.fileUrl(element.modelData.thumb)
                        asynchronous: true // 300 wallpapers must not stall the grid
                        cache: true
                        // Device pixels, not logical ones — see WallpaperBackdrop.
                        sourceSize.width: Math.ceil(Style.picker.iconBox * Screen.devicePixelRatio)
                        // Thumbnails decode one after another; each one fades in
                        // as it arrives instead of popping.
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeDuration
                            }
                        }
                    }
                }

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor // element { cursor: pointer; }
                    onHoveredChanged: {
                        if (hovered)
                            win.currentIndex = element.index;
                    }
                }

                TapHandler {
                    onTapped: {
                        win.currentIndex = element.index;
                        win.activate();
                    }
                }

                /// Staggered entrance, row by row, when the grid first appears.
                opacity: 0
                Component.onCompleted: entrance.start()

                SequentialAnimation {
                    id: entrance

                    PauseAnimation {
                        // Clamped: an animation is handed this straight, and a
                        // duration that came out negative — or NaN, from a
                        // half-written settings file — makes Qt complain on
                        // every delegate rather than fall back.
                        duration: Math.max(0, win.staggering ? Math.min(Style.staggerCap, element.index * Style.stagger) : 0)
                    }
                    NumberAnimation {
                        target: element
                        property: "opacity"
                        to: 1
                        duration: Style.enterDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
