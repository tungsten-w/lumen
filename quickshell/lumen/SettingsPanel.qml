pragma ComponentBehavior: Bound

import QtQuick

/// The settings panel, opened next to the picker with Ctrl+, — by typing
/// `settings` into its search field — and by `lumen --settings` in a terminal.
///
/// Nothing here is a preview: the rows write straight into Settings, Style
/// recomputes, and the picker beside it redraws on the same frame. There is no
/// save button because there is nothing to save — Settings writes the file back
/// on every change.
///
/// The rows are a list of descriptors rather than hand-placed widgets, so that
/// keyboard navigation is a single index, so that a tab is just a different
/// list, and so that pinning a colour can grow three rows under it without any
/// of it being special-cased.
///
/// One panel is built per window rather than one for both. A single list holding
/// the two was the shorter code and the worse panel: opening the settings from
/// the mode menu put thumbnail zoom and grid columns in front of you, none of
/// which the menu draws, and the live preview beside the panel could not show
/// what half the rows did. `scope` is what each window asks for, and the rows,
/// the tabs, the title and the reset all follow from it.
Item {
    id: panel

    /// Emitted when the panel asks to be closed.
    signal closed

    /// Which window this panel belongs to: `"menu"` or `"picker"`. The knobs the
    /// two windows share — the window shape, the animations, the palette — are
    /// in both, because they are what that window draws too.
    required property string scope

    readonly property bool menuScope: panel.scope === "menu"

    /// Room kept on the right of the rows for the scrollbar. The rows anchor
    /// their control to their own right edge, so without it the handle would sit
    /// on top of every toggle in the tab.
    readonly property real scrollGutter: 20

    /// Everything is split across these, because forty-odd rows in one scroll is
    /// a wall. Each tab is short enough to see nearly whole.
    readonly property var tabs: panel.menuScope ? [
        {
            key: "modes",
            label: "Entries"
        },
        {
            key: "shape",
            label: "Shape"
        },
        {
            key: "animation",
            label: "Motion"
        },
        {
            key: "layout",
            label: "Layout"
        },
        {
            key: "colors",
            label: "Color"
        },
        {
            key: "presets",
            label: "Presets"
        }
    ] : [
        {
            key: "shape",
            label: "Shape"
        },
        {
            key: "tags",
            label: "Tags"
        },
        {
            key: "animation",
            label: "Motion"
        },
        {
            key: "layout",
            label: "Layout"
        },
        {
            key: "colors",
            label: "Color"
        },
        {
            key: "presets",
            label: "Presets"
        }
    ]

    property int tab: 0
    property int currentIndex: 0

    readonly property var colorKeys: [
        {
            key: "background",
            label: "Background"
        },
        {
            key: "foreground",
            label: "Text"
        },
        {
            key: "border",
            label: "Border"
        },
        {
            key: "selection",
            label: "Selection"
        },
        {
            key: "thumbBorder",
            label: "Thumbnail border"
        }
    ]

    // ── Rows ───────────────────────────────────────────────────────────

    /// The rows of the current tab. Assigned rather than bound: as a binding it
    /// would re-run — and rebuild every delegate — on each nudge of any value it
    /// happens to read.
    property var rows: []

    /// One letter per colour, `a` for auto and `p` for pinned. A string so that
    /// it only reports a change when the shape of the list actually changes.
    readonly property string colorState: panel.colorKeys.map(colour => Settings.colors[colour.key] === Settings.auto ? "a" : "p").join("")

    /// Whether wallreco is there. The Tags tab offers to install it or to run
    /// it, which are not the same rows — evaluated lazily, so the mode menu's
    /// panel never brings the singleton to life.
    readonly property string tagState: panel.menuScope ? "" : Wallreco.presence

    /// Set while a preset is being named. The panel owns the keyboard, so the
    /// keys that would walk the list build this string instead.
    property bool naming: false
    property string draft: ""

    /// The saved presets, as a string so the list is only rebuilt when the set
    /// of them actually changes.
    readonly property string presetState: Presets.names.join("\u0000")

    onColorStateChanged: panel.rows = panel.buildRows()
    onTagStateChanged: panel.rows = panel.buildRows()
    onPresetStateChanged: panel.rows = panel.buildRows()
    onNamingChanged: panel.rows = panel.buildRows()
    onTabChanged: {
        panel.rows = panel.buildRows();
        panel.currentIndex = -1;
        panel.step(1); // land on the first row that is not a heading
        flick.contentY = 0;
    }

    Component.onCompleted: {
        panel.rows = panel.buildRows();
        panel.step(1);
    }

    function buildRows(): var {
        const rows = [];
        // Every key this tab put on screen, which is exactly what its Reset is
        // allowed to touch — the same group is split across the two panels.
        const touched = [];
        const group = label => rows.push({
            kind: "header",
            label: label
        });
        const slider = (group, key, label, from, to, step, suffix) => {
            touched.push(key);
            rows.push({
                kind: "slider",
                group: group,
                key: key,
                label: label,
                from: from,
                to: to,
                step: step ?? 1,
                suffix: suffix ?? ""
            });
        };
        const toggle = (group, key, label) => {
            touched.push(key);
            rows.push({
                kind: "toggle",
                group: group,
                key: key,
                label: label
            });
        };
        const choice = (group, key, label, options) => {
            touched.push(key);
            rows.push({
                kind: "choice",
                group: group,
                key: key,
                label: label,
                options: options
            });
        };

        switch (panel.tabs[panel.tab].key) {
        case "modes":
            group("Entries of the mode menu");
            toggle("modes", "dark", "Dark");
            toggle("modes", "light", "Light");
            toggle("modes", "time", "Time of day");
            toggle("modes", "season", "Season");
            break;

        case "shape":
            group("Corners");
            slider("shape", "windowRadius", "Window", 0, 60, 0.5, " px");
            if (!panel.menuScope) {
                slider("shape", "headerRadius", "Header", 0, 60, 0.5, " px");
                slider("shape", "thumbRadius", "Thumbnails", 0, 80, 0.5, " px");
                slider("shape", "entryRadius", "Search field", 0, 24, 0.5, " px");
            }

            group("Borders");
            slider("shape", "border", "Window", 0, 12, 0.5, " px");
            if (!panel.menuScope)
                slider("shape", "thumbBorder", "Thumbnails", 0, 12, 0.5, " px");

            if (panel.menuScope) {
                group("Selected entry");
                slider("shape", "pillInset", "Pill inset", 0, 30, 0.25, " px");
                slider("shape", "ringWidth", "Ring width", 0, 20, 0.5, " px");
                slider("shape", "ringInset", "Ring inset", 0, 30, 0.5, " px");
            }
            break;

        case "animation":
            group("Overall");
            toggle("animation", "enabled", "Animations");
            slider("animation", "speed", "Speed", 0.25, 4, 0.05, "×");
            slider("animation", "bounce", "Bounce", 0, 3, 0.05, "×");
            slider("animation", "lift", "Selection lift", 1, 1.12, 0.002, "×");

            group("Durations");
            slider("animation", "enter", "Opening", 0, 800, 10, " ms");
            slider("animation", "exit", "Closing", 0, 800, 10, " ms");
            slider("animation", "move", "Selection", 0, 800, 10, " ms");
            slider("animation", "fade", "Fades and hover", 0, 800, 10, " ms");
            slider("animation", "scroll", "Scrolling", 0, 800, 10, " ms");
            // The delay between two thumbnails arriving. There is no grid in
            // the mode menu, so there is nothing for it to stagger.
            if (!panel.menuScope)
                slider("animation", "stagger", "Thumbnail stagger", 0, 80, 1, " ms");
            break;

        case "layout":
            if (panel.menuScope) {
                group("Menu window");
                slider("layout", "menuWidth", "Width", 300, 1600, 2, " px");
                slider("layout", "menuHeight", "Height", 80, 600, 2, " px");
                slider("layout", "menuColumns", "Columns", 1, 4, 1);
                slider("layout", "iconSize", "Icon size", 20, 140, 1, " px");
            } else {
                group("Grid");
                slider("layout", "columns", "Columns", 1, 8, 1);
                slider("layout", "spacing", "Column spacing", 0, 40, 0.5, " px");
                slider("layout", "rowSpacing", "Row spacing", 0, 40, 0.5, " px");

                group("Thumbnails");
                slider("layout", "thumbAspect", "Aspect", 1, 3, 0.01, "");
                slider("layout", "thumbZoom", "Zoom", 100, 700, 5, " px");
                slider("layout", "thumbPadding", "Padding", 0, 40, 0.5, " px");
            }

            // The same image in both: a strip across the picker's header, and
            // the whole card behind the mode menu.
            group("Wallpaper backdrop");
            slider("layout", "backdropZoom", "Zoom", 0.5, 3, 0.01, "×");
            slider("layout", "backdropPosition", "Framing", 0, 1, 0.01, "");
            slider("layout", "backdropBlur", "Blur", 0, 1, 0.01, "");
            slider("layout", "backdropDim", "Dim", 0, 1, 0.01, "");

            if (!panel.menuScope) {
                group("Picker window");
                slider("layout", "pickerWidth", "Width", 400, 1800, 2, " px");
                slider("layout", "pickerHeight", "Height", 300, 1400, 2, " px");
                slider("layout", "padding", "Padding", 0, 60, 0.5, " px");
                slider("layout", "headerHeight", "Header height", 60, 500, 2, " px");

                group("Search field");
                slider("layout", "entryWidth", "Width", 100, 700, 2, " px");
                slider("layout", "entryHeight", "Height", 24, 100, 0.5, " px");
                slider("layout", "textSize", "Text size", 8, 40, 1, " px");
            }
            break;

        case "presets":
            group("Presets");
            rows.push({
                kind: "preset",
                key: "",
                label: "Default"
            });
            for (const name of Presets.names) {
                rows.push({
                    kind: "preset",
                    key: name,
                    label: name
                });
            }
            if (panel.naming) {
                rows.push({
                    kind: "name"
                });
            } else {
                rows.push({
                    kind: "action",
                    key: "save",
                    label: "Save this configuration",
                    verb: "Name it"
                });
            }
            rows.push({
                kind: "note",
                key: "presets"
            });
            break;

        case "tags":
            group("wallreco");
            if (Wallreco.presence === "no") {
                rows.push({
                    kind: "action",
                    key: "install",
                    label: "Not installed",
                    verb: "Install"
                });
            } else {
                rows.push({
                    kind: "action",
                    key: "tag",
                    label: "Tag what has no tags yet",
                    verb: "Run"
                });
                rows.push({
                    kind: "action",
                    key: "retag",
                    label: "Recompute every tag",
                    verb: "Run",
                    confirms: true
                });
            }
            rows.push({
                kind: "note"
            });
            break;

        case "colors":
            group("Window");
            slider("colors", "opacity", "Background opacity", 0.2, 1, 0.01, "");
            toggle("colors", "blur", "Blur behind the window");

            group("Palette");
            // Which generator the five colours below are read from. All three
            // are rewritten on every wallpaper change; this only picks the one
            // the picker listens to.
            choice("colors", "palette", "Source", [
                {
                    value: "pywal",
                    label: "pywal"
                },
                {
                    value: "matugen",
                    label: "matugen"
                },
                {
                    value: "noctalia",
                    label: "noctalia"
                }
            ]);
            for (const colour of panel.colorKeys) {
                touched.push(colour.key);
                rows.push({
                    kind: "colour",
                    key: colour.key,
                    label: colour.label
                });
                // A pinned colour gets its three channels right underneath, as
                // rows of the same list — nothing about them is a special case.
                if (Settings.colors[colour.key] !== Settings.auto) {
                    const channels = [
                        {
                            channel: "h",
                            label: "Hue",
                            to: 360
                        },
                        {
                            channel: "s",
                            label: "Saturation",
                            to: 100
                        },
                        {
                            channel: "l",
                            label: "Lightness",
                            to: 100
                        }
                    ];
                    for (const channel of channels) {
                        rows.push({
                            kind: "channel",
                            key: colour.key,
                            channel: channel.channel,
                            label: "   " + channel.label,
                            from: 0,
                            to: channel.to,
                            step: 1,
                            suffix: ""
                        });
                    }
                }
            }
            break;
        }

        // The Tags tab has nothing to put back: its rows are jobs, not values.
        if (["tags", "presets"].includes(panel.tabs[panel.tab].key))
            return rows;

        rows.push({
            kind: "header",
            label: ""
        });
        rows.push({
            kind: "reset",
            group: panel.tabs[panel.tab].key,
            keys: touched,
            label: "Reset"
        });
        return rows;
    }

    // ── Colour channels ────────────────────────────────────────────────

    function channelValue(key: string, channel: string): real {
        const colour = Qt.color(Settings.colors[key]);
        if (channel === "h")
            return Math.max(0, colour.hslHue) * 360;
        if (channel === "s")
            return colour.hslSaturation * 100;
        return colour.hslLightness * 100;
    }

    function setChannel(key: string, channel: string, value: real) {
        const colour = Qt.color(Settings.colors[key]);
        const hue = channel === "h" ? value / 360 : Math.max(0, colour.hslHue);
        const saturation = channel === "s" ? value / 100 : colour.hslSaturation;
        const lightness = channel === "l" ? value / 100 : colour.hslLightness;
        Settings.colors[key] = Qt.hsla(hue, saturation, lightness, 1).toString();
    }

    // ── Keys ───────────────────────────────────────────────────────────
    //
    // The picker's vim keys, over a list instead of a grid: j/k walk the rows,
    // h/l change the value under the cursor, Shift makes the steps ten times
    // bigger. Tab — or 1 to 4 — moves between the four tabs. Headings are
    // skipped, so every stop is something you can act on.

    function step(direction: int) {
        let index = panel.currentIndex + direction;
        while (index >= 0 && index < panel.rows.length && panel.rows[index].kind === "header") {
            index += direction;
        }
        if (index >= 0 && index < panel.rows.length) {
            panel.currentIndex = index;
            panel.reveal();
        }
    }

    function selectTab(index: int) {
        panel.tab = (index + panel.tabs.length) % panel.tabs.length;
    }

    /// Opens on a named tab, for whoever asked for the panel to know where they
    /// wanted to land — the mode menu's own entry opens it on "Menu".
    function openAt(key: string) {
        const index = panel.tabs.findIndex(tab => tab.key === key);
        if (index >= 0)
            panel.selectTab(index);
    }

    /// Acts on the selected row: sliders move by `amount` steps, and anything
    /// that has no value to slide — a toggle, a colour — flips instead.
    function adjust(amount: real) {
        const item = panel.currentWidget();
        if (!item)
            return;
        if (item.nudge)
            item.nudge(amount);
        else if (item.flip)
            item.flip();
    }

    function currentWidget(): Item {
        const line = repeater.itemAt(panel.currentIndex);
        return line ? line.widget : null;
    }

    /// Puts back everything the current tab has on screen, and nothing else.
    function resetTab() {
        const row = panel.rows.find(line => line.kind === "reset");
        if (row)
            Settings.resetKeys(row.group, row.keys);
    }

    function trigger() {
        const row = panel.rows[panel.currentIndex];
        if (row.kind === "reset") {
            Settings.resetKeys(row.group, row.keys);
            return;
        }
        const item = panel.currentWidget();
        if (item && item.flip)
            item.flip();
    }

    /// The panel has no focused text field. The picker hands it every key, and
    /// a field that took focus would have to win it back and give it up again
    /// cleanly — so while a preset is being named, the keys that would walk the
    /// list build the name instead. Nothing leaks through, which is why this
    /// reports every key as handled.
    function typeName(event): bool {
        switch (event.key) {
        case Qt.Key_Escape:
            panel.naming = false;
            panel.draft = "";
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            const name = panel.draft;
            panel.naming = false;
            panel.draft = "";
            Presets.save(name);
            break;
        case Qt.Key_Backspace:
            panel.draft = panel.draft.slice(0, -1);
            break;
        default:
            // Printable characters only: the arrows and the function keys all
            // arrive with an empty or a control `text`.
            if (event.text && event.text.charCodeAt(0) >= 0x20)
                panel.draft += event.text;
        }
        return true;
    }

    function handleKey(event): bool {
        if (panel.naming)
            return panel.typeName(event);

        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const big = shift ? 10 : 1;

        // 1 to 4 jump straight to a tab.
        if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + panel.tabs.length) {
            panel.selectTab(event.key - Qt.Key_1);
            return true;
        }

        switch (event.key) {
        case Qt.Key_Tab:
            panel.selectTab(panel.tab + 1);
            return true;
        case Qt.Key_Backtab:
            panel.selectTab(panel.tab - 1);
            return true;
        case Qt.Key_J:
        case Qt.Key_Down:
            panel.step(1);
            return true;
        case Qt.Key_K:
        case Qt.Key_Up:
            panel.step(-1);
            return true;
        case Qt.Key_H:
        case Qt.Key_Left:
            panel.adjust(-big);
            return true;
        case Qt.Key_L:
        case Qt.Key_Right:
            panel.adjust(big);
            return true;
        case Qt.Key_PageDown:
            panel.step(5);
            return true;
        case Qt.Key_PageUp:
            panel.step(-5);
            return true;
        case Qt.Key_G:
            // `G` to the last row, `g` to the first, landing past any heading.
            panel.currentIndex = shift ? panel.rows.length : -1;
            panel.step(shift ? -1 : 1);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            panel.trigger();
            return true;
        case Qt.Key_R:
            // Puts back the tab you are in, rather than everything — and only
            // the knobs it shows, not the other panel's half of the group.
            panel.resetTab();
            return true;
        case Qt.Key_X:
        case Qt.Key_Delete: {
            // Rows that can throw something away say so; the rest ignore it.
            const item = panel.currentWidget();
            if (item && item.remove) {
                item.remove();
                return true;
            }
            return false;
        }
        case Qt.Key_Escape:
        case Qt.Key_Q:
            panel.closed();
            return true;
        }
        return false;
    }

    /// Scrolls the selected row into view.
    function reveal() {
        const item = repeater.itemAt(panel.currentIndex);
        if (!item)
            return;
        if (item.y < flick.contentY)
            flick.contentY = item.y;
        else if (item.y + item.height > flick.contentY + flick.height)
            flick.contentY = item.y + item.height - flick.height;
    }

    // ── Look ───────────────────────────────────────────────────────────
    // The same card as the picker, so the two read as one window split in two.

    Rectangle {
        anchors.fill: parent
        radius: Style.picker.radius
        color: Colors.background
        border.width: Style.picker.border
        border.color: Colors.urgent

        Text {
            id: title

            x: Style.picker.headerX + 6
            y: Style.picker.headerY
            text: panel.menuScope ? "Menu settings" : "Picker settings"
            color: Colors.foreground
            font.family: Style.textFont
            font.pixelSize: Style.textSize * 1.6
        }

        /// The keys, in the order you reach for them.
        Row {
            anchors.right: parent.right
            anchors.rightMargin: Style.picker.headerX + 6
            y: title.y + title.height - height - 2
            spacing: 7
            opacity: 0.5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "tab  ·  j k  ·  h l  ·"
                color: Colors.foreground
                font.family: Style.textFont
                font.pixelSize: Style.textSize * 0.85
            }

            SvgIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "enter"
                size: Style.textSize * 1.15
            }
        }

        /// The tabs. One pill slides between them, the same way the selection
        /// pill slides across the mode menu.
        Item {
            id: tabBar

            x: Style.picker.headerX + 6
            y: title.y + title.height + 12
            width: parent.width - x * 2
            height: 34

            Rectangle {
                id: tabIndicator

                readonly property Item target: tabRow.children[panel.tab] ?? null

                x: tabIndicator.target ? tabIndicator.target.x : 0
                width: tabIndicator.target ? tabIndicator.target.width : 0
                height: parent.height
                radius: height / 2
                color: Colors.selected

                Behavior on x {
                    NumberAnimation {
                        duration: Style.moveDuration
                        easing.type: Style.springEasing
                        easing.overshoot: Style.overshoot(0.05)
                    }
                }
                Behavior on width {
                    NumberAnimation {
                        duration: Style.moveDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Row {
                id: tabRow

                spacing: 4

                /// Every tab gets the same slice of the bar rather than its own
                /// width. Four tabs fitted at their natural size; six do not —
                /// the menu's ran 111px past the edge of the panel and the last
                /// name fell off it. An equal share is the one rule that holds
                /// whatever the tab count and whatever the text size is set to,
                /// and it keeps the sliding indicator a constant width.
                readonly property real slot: Math.max(24, (tabBar.width - tabRow.spacing * (panel.tabs.length - 1)) / Math.max(1, panel.tabs.length))

                Repeater {
                    model: panel.tabs

                    delegate: Item {
                        id: tabItem

                        required property int index
                        required property var modelData
                        readonly property bool current: panel.tab === tabItem.index

                        width: tabRow.slot
                        height: tabBar.height

                        Text {
                            id: label

                            anchors.centerIn: parent
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                            // Turning the text size right up makes six names too
                            // wide for their slots. Shrinking them to fit reads
                            // better than cutting them down to `Entr…`; the
                            // elide is only what happens past the floor.
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 9
                            elide: Text.ElideRight
                            text: tabItem.modelData.label
                            color: tabItem.current ? Colors.background : Colors.foreground
                            opacity: tabItem.current ? 1 : 0.7
                            font.family: Style.textFont
                            // A touch under the rows', so six names sit in the
                            // bar with room to breathe rather than filling it.
                            font.pixelSize: Style.textSize * 0.92

                            Behavior on color {
                                ColorAnimation {
                                    duration: Style.fadeDuration
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.selectTab(tabItem.index)
                        }
                    }
                }
            }
        }

        Flickable {
            id: flick

            x: tabBar.x
            y: tabBar.y + tabBar.height + 10
            width: tabBar.width - panel.scrollGutter
            height: parent.height - y - Style.picker.headerX
            clip: true
            interactive: false // the wheel is handled below, like the grid's
            contentHeight: column.height

            Behavior on contentY {
                // Off while the handle is being dragged: an eased contentY makes
                // the handle lag behind the cursor that is carrying it.
                enabled: !scroller.dragging

                NumberAnimation {
                    duration: Style.scrollDuration
                    easing.type: Easing.OutCubic
                }
            }

            WheelHandler {
                onWheel: event => {
                    flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY - event.angleDelta.y));
                    event.accepted = true;
                }
            }

            Column {
                id: column

                width: flick.width

                Repeater {
                    id: repeater

                    model: panel.rows

                    delegate: Item {
                        id: line

                        required property int index
                        required property var modelData
                        readonly property bool current: panel.currentIndex === line.index
                        /// What the panel's keys act on. Empty for headings.
                        readonly property Item widget: loader.item

                        width: column.width
                        height: loader.item ? loader.item.implicitHeight : 0

                        /// Marks the row under the cursor, and doubles as the
                        /// click target: pointing at a row selects it.
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -8
                            anchors.rightMargin: -8
                            radius: Style.picker.entryRadius + 5
                            color: Colors.selected
                            opacity: line.current ? 0.16 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Style.fadeDuration
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            hoverEnabled: true
                            onEntered: {
                                if (line.modelData.kind !== "header")
                                    panel.currentIndex = line.index;
                            }
                        }

                        Loader {
                            id: loader

                            width: parent.width
                            sourceComponent: {
                                switch (line.modelData.kind) {
                                case "slider":
                                    return sliderRow;
                                case "toggle":
                                    return toggleRow;
                                case "choice":
                                    return choiceRow;
                                case "colour":
                                    return colourRow;
                                case "channel":
                                    return channelRow;
                                case "action":
                                    return actionRow;
                                case "preset":
                                    return presetRow;
                                case "name":
                                    return nameRow;
                                case "note":
                                    return noteRow;
                                case "reset":
                                    return resetRow;
                                default:
                                    return headerRow;
                                }
                            }
                        }

                        Component {
                            id: sliderRow

                            SettingSlider {
                                width: loader.width
                                label: line.modelData.label
                                group: line.modelData.group
                                key: line.modelData.key
                                from: line.modelData.from
                                to: line.modelData.to
                                step: line.modelData.step
                                suffix: line.modelData.suffix
                                selected: line.current
                            }
                        }

                        Component {
                            id: channelRow

                            SettingSlider {
                                width: loader.width
                                label: line.modelData.label
                                from: line.modelData.from
                                to: line.modelData.to
                                step: line.modelData.step
                                selected: line.current
                                read: () => panel.channelValue(line.modelData.key, line.modelData.channel)
                                write: value => panel.setChannel(line.modelData.key, line.modelData.channel, value)
                            }
                        }

                        Component {
                            id: toggleRow

                            SettingToggle {
                                width: loader.width
                                label: line.modelData.label
                                group: line.modelData.group
                                key: line.modelData.key
                                selected: line.current
                            }
                        }

                        Component {
                            id: choiceRow

                            SettingChoice {
                                width: loader.width
                                label: line.modelData.label
                                group: line.modelData.group
                                key: line.modelData.key
                                options: line.modelData.options
                                selected: line.current
                            }
                        }

                        Component {
                            id: colourRow

                            SettingColor {
                                width: loader.width
                                label: line.modelData.label
                                key: line.modelData.key
                                selected: line.current
                            }
                        }

                        Component {
                            id: actionRow

                            SettingAction {
                                width: loader.width
                                label: line.modelData.label
                                verb: line.modelData.verb
                                confirms: line.modelData.confirms ?? false
                                selected: line.current

                                /// The Presets tab has an action row too, and it
                                /// must not wake the tagger up to ask it whether
                                /// it is busy — `&&` and `?:` keep the singleton
                                /// out of the mode menu's panel entirely.
                                readonly property bool tagger: line.modelData.key !== "save"

                                // Only the row that started a job says so; the
                                // others just go untouchable until it is done.
                                busy: tagger && Wallreco.job === line.modelData.key
                                busyVerb: line.modelData.key === "install" ? "Building…" : "Tagging…"
                                ready: !tagger || (!Wallreco.busy && (line.modelData.key === "install" || Wallreco.installed))
                                run: () => {
                                    switch (line.modelData.key) {
                                    case "save":
                                        panel.draft = "";
                                        panel.naming = true;
                                        break;
                                    case "install":
                                        Wallreco.install();
                                        break;
                                    case "retag":
                                        Wallreco.retag();
                                        break;
                                    default:
                                        Wallreco.tagMissing();
                                    }
                                }
                            }
                        }

                        Component {
                            id: presetRow

                            SettingPreset {
                                width: loader.width
                                name: line.modelData.label
                                selected: line.current
                                // "Default" is the measurements, not a file.
                                removable: line.modelData.key !== ""
                                busy: Presets.pending === line.modelData.key && line.modelData.key !== ""
                                apply: () => {
                                    if (line.modelData.key === "")
                                        Presets.applyDefault();
                                    else
                                        Presets.apply(line.modelData.key);
                                }
                                erase: () => Presets.remove(line.modelData.key)
                            }
                        }

                        Component {
                            id: nameRow

                            SettingName {
                                width: loader.width
                                draft: panel.draft
                            }
                        }

                        Component {
                            id: noteRow

                            Item {
                                implicitHeight: note.implicitHeight + 22

                                Text {
                                    id: note

                                    y: 18
                                    width: loader.width
                                    wrapMode: Text.WordWrap
                                    text: {
                                        if (line.modelData.key === "presets") {
                                            if (Presets.status)
                                                return Presets.status;
                                            return "A preset is one JSON file in ~/.config/lumen/presets, shaped exactly like settings.json — readable, hand-editable, and worth sending to someone. Applying writes back only what the file holds, so a preset carrying nothing but colors leaves your layout alone. `x` on a row deletes it.";
                                        }
                                        if (Wallreco.status)
                                            return Wallreco.status;
                                        if (Wallreco.presence === "looking")
                                            return "Looking for wallreco…";
                                        if (Wallreco.presence === "no")
                                            return "wallreco tags your wallpapers by renaming them — sunset.png becomes sunset-#orange-#warm-#sky.png — so the search field above can find them by keyword. Installing it clones the repository and builds it, which needs git and cargo and takes a few minutes.";
                                        return "Tags live in the filenames, which is what the search field reads. Recomputing renames every wallpaper in ~/Pictures/Wallpapers: the thumbnails rebuild themselves afterwards, and `wallreco --undo` in a terminal puts the old names back.";
                                    }
                                    color: Colors.foreground
                                    opacity: 0.55
                                    font.family: Style.textFont
                                    font.pixelSize: Style.textSize * 0.85
                                }
                            }
                        }

                        Component {
                            id: resetRow

                            Item {
                                implicitHeight: 44

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: line.modelData.label
                                    color: line.current ? Colors.urgent : Colors.foreground
                                    opacity: line.current ? 1 : 0.6
                                    font.family: Style.textFont
                                    font.pixelSize: Style.textSize
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Settings.resetKeys(line.modelData.group, line.modelData.keys)
                                }
                            }
                        }

                        Component {
                            id: headerRow

                            Item {
                                implicitHeight: line.modelData.label === "" ? 18 : 38

                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 6
                                    text: line.modelData.label
                                    color: Colors.selected
                                    font.family: Style.textFont
                                    font.pixelSize: Style.textSize * 0.85
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 1.5
                                }
                            }
                        }
                    }
                }
            }
        }

        /// Says how much of the tab is out of sight, and scrolls it. Sits in the
        /// gutter the rows leave for it, flush with their right edge.
        ScrollBar {
            id: scroller

            flickable: flick
            x: flick.x + flick.width + 8
            y: flick.y
            height: flick.height
        }
    }
}
