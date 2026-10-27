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

    /// Set when `lumen` opened this grid on a folder of your own.
    ///
    /// Those folders are neither dark nor light — the same directory can hold
    /// both — so unlike `dark/` and `light/` there is nothing to infer. The mode
    /// is asked for once you have chosen, and the answer carries it in front of
    /// the path.
    property bool askMode: false

    /// The wallpaper waiting on a dark-or-light answer, or empty.
    property string pendingPick: ""
    /// Which of the two the cursor is on while the question is up.
    property bool pendingDark: true

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
    /// The colours the search field understood, as `ColorSearch.parse` reads
    /// them. The grid is ranked by these rather than filtered.
    property var colorTerms: []
    /// The colour words already turned into chips. A colour word stays text
    /// while it is being typed — "red" may yet become "redwood" — and becomes
    /// a chip once a space ends it, so the field never says it twice.
    property var colorTokens: []

    /// Turns every finished colour word of the field into a chip. Only runs on
    /// a trailing space, which is what finishes a word; it rewrites the field
    /// only when it found one, so its own rewrite does not loop.
    function tokenize(text: string): bool {
        if (!/\s$/.test(text))
            return false;
        const words = text.trim().split(/\s+/).filter(word => word.length > 0);
        const found = [];
        const kept = [];
        for (const word of words) {
            const colour = ColorSearch.parse(word.toLowerCase());
            if (colour && !win.colorTokens.some(token => token.word === colour.word))
                found.push(colour);
            else if (!colour)
                kept.push(word);
        }
        if (kept.length === words.length)
            return false;
        win.colorTokens = win.colorTokens.concat(found);
        search.text = kept.length > 0 ? kept.join(" ") + " " : "";
        return true;
    }

    /// Backspace at the very start of the field takes back the last chip.
    function untokenize(): bool {
        if (win.colorTokens.length === 0 || search.cursorPosition > 0 || search.selectedText.length > 0)
            return false;
        win.colorTokens = win.colorTokens.slice(0, -1);
        win.filter(search.text);
        return true;
    }
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
            const found = parsed.items ?? [];
            for (const wallpaper of found)
                wallpaper.palette = ColorSearch.prepare(wallpaper.colors);
            // Reordered, never mixed: this is still only whatever folder
            // `lumen` scanned to build the file — dark, light, one of your
            // own — just not always led with the same handful of thumbnails.
            win.wallpapers = Settings.layout.shuffle ? win.shuffled(found) : found;
            win.matches = win.wallpapers;
        }
    }

    /// Fisher–Yates, copying rather than mutating: `found` above is what the
    /// file just handed back, and shuffling it in place would make a second
    /// read of `items.text()` — a live reload while the picker is open —
    /// look like it had rewritten its own order.
    function shuffled(list: var): var {
        const out = list.slice();
        for (let i = out.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [out[i], out[j]] = [out[j], out[i]];
        }
        return out;
    }

    /// Typed into the search field instead of a wallpaper name, this opens the
    /// settings — the same panel Ctrl+, and `lumen --settings` open.
    ///
    /// It is safe to spend the word: no wallpaper here is called anything like
    /// it, and a search that did match one would still be one keystroke away
    /// from being something else.
    readonly property var commands: ["settings"]

    /// Whether `query` is one of them, spelt out in full. Only then does the
    /// hint over the grid show up, so a search that merely starts with an `s`
    /// is left to look like the search it is.
    function isCommand(query: string): bool {
        return win.commands.includes(query.trim().toLowerCase());
    }

    /// Runs `query` if it is one of them, and says whether it did. Enter is what
    /// runs it — the hint shows the key — never the typing alone.
    function runCommand(query: string): bool {
        if (!win.isCommand(query))
            return false;

        // Clearing the field re-enters filter(), which is harmless: it no
        // longer runs commands.
        search.text = "";
        win.asideOpen = true;
        return true;
    }

    /// rofi's default matcher: every whitespace-separated term has to appear
    /// somewhere in the entry, case-insensitively.
    ///
    /// Except colour words. Those never filter anything out; they reorder what
    /// the other terms kept, best match first, by the palette `lumen` read off
    /// each thumbnail — so a wallpaper nobody tagged `#blue` still comes up for
    /// "blue". A name that does carry the word gets a nudge on top.
    function filter(query: string) {
        // The rewrite re-enters here with the chip already made.
        if (win.tokenize(query))
            return;

        const terms = query.toLowerCase().split(/\s+/).filter(term => term.length > 0);
        const colours = win.colorTokens.slice();
        const words = [];
        for (const term of terms) {
            const colour = ColorSearch.parse(term);
            if (colour)
                colours.push(colour);
            else
                words.push(term);
        }
        win.colorTerms = colours;

        const kept = words.length === 0 ? win.wallpapers : win.wallpapers.filter(wallpaper => {
            const name = wallpaper.name.toLowerCase();
            return words.every(term => name.includes(term));
        });

        if (colours.length === 0) {
            win.matches = kept;
        } else {
            // Several colours multiply: "blue pink" wants both, not either.
            const ranked = kept.map((wallpaper, index) => {
                const name = wallpaper.name.toLowerCase();
                let score = 1;
                for (const colour of colours)
                    score *= ColorSearch.fit(wallpaper.palette, colour.target) + (name.includes(colour.word) ? 0.3 : 0);
                return { wallpaper: wallpaper, score: score, index: index };
            });
            // The index breaks ties, so equal scores keep the folder's order.
            ranked.sort((a, b) => b.score - a.score || a.index - b.index);
            win.matches = ranked.map(entry => entry.wallpaper);
        }
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
        if (!wallpaper)
            return;
        if (win.askMode) {
            win.pendingPick = wallpaper.path;
            win.pendingDark = true;
            return;
        }
        Result.accept(wallpaper.path);
    }

    /// Answers with the mode in front of the path, which is what `lumen` splits
    /// on. Only the first colon is the separator, so a wallpaper named with one
    /// still arrives whole.
    function answerMode(dark: bool) {
        const path = win.pendingPick;
        win.pendingPick = "";
        Result.accept((dark ? "dark:" : "light:") + path);
    }

    /// The question owns the keyboard while it is up, and swallows everything —
    /// a letter that leaked through would land in the search field behind it.
    function modeKey(event): bool {
        switch (event.key) {
        case Qt.Key_H:
        case Qt.Key_Left:
            win.pendingDark = true;
            return true;
        case Qt.Key_L:
        case Qt.Key_Right:
            win.pendingDark = false;
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            win.answerMode(win.pendingDark);
            return true;
        case Qt.Key_Escape:
        case Qt.Key_Q:
            win.pendingPick = ""; // back to the grid, nothing chosen
            return true;
        }
        return true;
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
            if (!win.runCommand(search.text))
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
        // A question is modal: it is answered before anything else happens.
        if (win.pendingPick !== "")
            return win.modeKey(event);

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

        if (event.key === Qt.Key_Backspace)
            return win.untokenize();

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
                scale: search.text.length > 0 || win.colorTokens.length > 0 ? 1.02 : 1
                Behavior on scale {
                    NumberAnimation {
                        duration: Style.fadeDuration
                        easing.type: Easing.OutCubic
                    }
                }

                /// Says the query was read as colours: one swatch per colour
                /// word, so "blue" is plainly a colour and not a filename.
                Row {
                    id: colourChip

                    anchors.left: parent.left
                    anchors.leftMargin: Style.picker.entryPadding
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    visible: win.colorTokens.length > 0

                    Repeater {
                        model: win.colorTokens

                        Rectangle {
                            required property var modelData

                            height: Style.textSize * 1.5
                            width: chipRow.implicitWidth + height * 0.7
                            radius: height / 2
                            color: Qt.alpha(Colors.foreground, 0.08)
                            border.width: 1
                            border.color: Qt.alpha(Colors.foreground, 0.2)

                            Row {
                                id: chipRow

                                anchors.centerIn: parent
                                spacing: 5

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Style.textSize * 0.8
                                    height: width
                                    radius: width / 2
                                    color: modelData.swatch
                                    border.width: 1
                                    border.color: Qt.alpha(Colors.foreground, 0.35)
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.word
                                    color: Colors.foreground
                                    font.family: Style.textFont
                                    font.pixelSize: Style.textSize * 0.8
                                }
                            }
                        }
                    }
                }

                TextInput {
                    id: search

                    anchors.fill: parent
                    anchors.leftMargin: Style.picker.entryPadding + (colourChip.visible ? colourChip.width + 8 : 0)
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
                        opacity: search.text.length === 0 && win.colorTokens.length === 0 ? 0.55 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeDuration
                            }
                        }
                    }
                }
            }
        }

        /// What the grid area says once a command is spelt out in the search
        /// field. Without it, `settings` looks like a search that matches
        /// nothing, and nothing says Enter is what opens the panel.
        Item {
            x: Style.picker.gridX
            y: Style.picker.gridY + 24
            width: Style.picker.columns * Style.picker.columnPitch
            height: Style.textSize * 2
            opacity: win.isCommand(search.text) ? 1 : 0

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

        /// The grid's wheel and trackpad scrolling. A sibling laid over it
        /// rather than a handler inside it: the GridView is not interactive
        /// and hands its children to its moving content item, neither of which
        /// a wheel can be trusted to get through. It holds nothing but the
        /// handler, so clicks and hovers still reach the thumbnails below.
        Item {
            x: grid.x
            y: grid.y
            z: 1
            width: grid.width
            height: grid.height

            WheelHandler {
                // The dark-or-light question sits over the grid; it is modal.
                enabled: win.pendingPick === ""
                onWheel: event => {
                    // A trackpad reports pixels and scrolls 1:1; a wheel
                    // reports notches (120 each), which glide.
                    if (event.pixelDelta.y !== 0)
                        grid.scrollTo(grid.headedTo - event.pixelDelta.y, false);
                    else
                        grid.scrollTo(grid.headedTo - event.angleDelta.y);
                    event.accepted = true;
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
                enabled: grid.gliding

                NumberAnimation {
                    id: glide
                    duration: Style.scrollDuration
                    easing.type: Easing.OutCubic
                }
            }

            readonly property int visibleRows: Math.max(1, Math.floor(height / cellHeight))
            readonly property real maxContentY: Math.max(0, contentHeight - height)

            /// Where the grid is headed, which mid-glide is not where it is.
            /// Steps add to this rather than to `contentY`: each one restarts
            /// the glide, and stacking them on the half-way position lost most
            /// of every wheel notch — and nearly all of a trackpad swipe.
            property real targetY: 0
            /// Off for a trackpad, whose own stream of small steps is already
            /// smooth and only lags behind an animation chasing it.
            property bool gliding: true

            readonly property real headedTo: glide.running ? grid.targetY : grid.contentY

            function scrollTo(y: real, animated = true) {
                grid.targetY = Math.max(0, Math.min(grid.maxContentY, y));
                grid.gliding = animated;
                contentY = grid.targetY;
            }

            /// Scrolls just far enough to bring `index` fully into view.
            function reveal(index: int) {
                const top = Math.floor(index / Style.picker.columns) * grid.cellHeight;
                const bottom = top + Style.picker.elementHeight;
                if (top < grid.headedTo)
                    grid.scrollTo(top);
                else if (bottom > grid.headedTo + grid.height)
                    grid.scrollTo(bottom - grid.height);
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
                /// Whether the wallpaper *behind* this thumbnail is a GIF
                /// `lumen` is willing to play — asked of the real path, never
                /// the cached `.thumb`, which `magick […\[0\]…]` always renders
                /// down to a flat PNG, and off outright when Layout → Wallpaper
                /// backdrop's switch is.
                readonly property bool isGif: Style.isAnimatableGif(element.modelData.path)

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
                        id: poster

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
                        // as it arrives, and it yields once `motion` below has
                        // taken over — same crossfade as the backdrop's.
                        opacity: status === Image.Ready && (!element.current || !element.isGif || motion.status !== Image.Ready) ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeDuration
                            }
                        }
                    }

                    /// The same thumbnail, playing — but only for the one
                    /// element that is both selected and a GIF. Every other
                    /// cell keeps `source` empty, which is what stops a folder
                    /// of fifty GIFs from decoding fifty movies at once: the
                    /// cached, static `.thumb` above is what a grid full of
                    /// them is drawn from, same as it always was.
                    AnimatedImage {
                        id: motion

                        anchors.centerIn: parent
                        width: Style.picker.iconBox
                        height: Style.picker.iconBox
                        fillMode: Image.PreserveAspectFit

                        source: element.current && element.isGif ? Style.fileUrl(element.modelData.path) : ""
                        asynchronous: true
                        cache: false
                        sourceSize.width: Math.ceil(Style.picker.iconBox * Screen.devicePixelRatio)

                        // `AnimatedImage.playing` defaults to true, but binding
                        // `sourceSize` to a size computed from its own layout —
                        // exactly what this does — makes it redecode once that
                        // settles, and the redecode comes back paused. See
                        // WallpaperBackdrop for how this was actually found.
                        onStatusChanged: if (status === Image.Ready)
                            playing = true

                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeDuration
                            }
                        }
                    }

                    /// The palette a colour search ranks by, along the bottom
                    /// edge, each colour as wide as its share of the image.
                    /// Only there while a colour is being searched for.
                    Row {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 8
                        opacity: win.colorTerms.length > 0 ? 0.95 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeDuration
                            }
                        }

                        Repeater {
                            model: element.modelData.colors ?? []

                            Rectangle {
                                required property var modelData

                                width: thumbnail.width * modelData.weight
                                height: parent.height
                                color: modelData.hex
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

        /// Dark or light, for a wallpaper out of a folder of your own.
        ///
        /// Declared last so it paints over the grid, and it covers the whole
        /// card rather than floating in a corner: it holds the keyboard, and a
        /// modal question that does not look modal is one you answer by
        /// accident.
        Rectangle {
            id: question

            anchors.fill: parent
            radius: Style.picker.radius
            color: Qt.alpha(Colors.background, 0.94)
            visible: opacity > 0
            opacity: win.pendingPick !== "" ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeDuration
                }
            }

            // Nothing behind it is clickable while it is up.
            MouseArea {
                anchors.fill: parent
                onClicked: win.pendingPick = ""
            }

            Column {
                anchors.centerIn: parent
                spacing: 22

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Dark or light?"
                    color: Colors.foreground
                    font.family: Style.textFont
                    font.pixelSize: Style.textSize * 1.6
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 18

                    Repeater {
                        model: [
                            {
                                label: "Dark",
                                glyph: String.fromCodePoint(0xf4ee),
                                dark: true
                            },
                            {
                                label: "Light",
                                glyph: String.fromCodePoint(0xf522),
                                dark: false
                            }
                        ]

                        delegate: Rectangle {
                            id: choice

                            required property var modelData
                            readonly property bool current: win.pendingDark === choice.modelData.dark

                            width: 150
                            height: 110
                            radius: Style.picker.entryRadius + 10
                            color: choice.current ? Colors.selected : "transparent"
                            border.width: 3
                            border.color: choice.current ? Colors.selected : Colors.foreground
                            opacity: choice.current ? 1 : 0.5
                            scale: choice.current ? Style.lift : 1

                            Behavior on color {
                                ColorAnimation {
                                    duration: Style.fadeDuration
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Style.moveDuration
                                    easing.type: Style.springEasing
                                    easing.overshoot: Style.overshoot(0.1)
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: choice.modelData.glyph
                                    color: choice.current ? Colors.background : Colors.foreground
                                    font.family: Style.iconFont
                                    font.pixelSize: Style.textSize * 2.2
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: choice.modelData.label
                                    color: choice.current ? Colors.background : Colors.foreground
                                    font.family: Style.textFont
                                    font.pixelSize: Style.textSize
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.answerMode(choice.modelData.dark)
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "h l  ·  enter  ·  esc to go back"
                    color: Colors.foreground
                    opacity: 0.5
                    font.family: Style.textFont
                    font.pixelSize: Style.textSize * 0.85
                }
            }
        }
    }
}
