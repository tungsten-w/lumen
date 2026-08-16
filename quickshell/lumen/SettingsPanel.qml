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
Item {
    id: panel

    /// Emitted when the panel asks to be closed.
    signal closed

    /// Everything is split across these, because forty-odd rows in one scroll is
    /// a wall. Each tab is short enough to see nearly whole.
    readonly property var tabs: [
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

    onColorStateChanged: panel.rows = panel.buildRows()
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
        const group = label => rows.push({
            kind: "header",
            label: label
        });
        const slider = (group, key, label, from, to, step, suffix) => rows.push({
            kind: "slider",
            group: group,
            key: key,
            label: label,
            from: from,
            to: to,
            step: step ?? 1,
            suffix: suffix ?? ""
        });
        const toggle = (group, key, label) => rows.push({
            kind: "toggle",
            group: group,
            key: key,
            label: label
        });

        switch (panel.tabs[panel.tab].key) {
        case "shape":
            group("Corners");
            slider("shape", "windowRadius", "Windows", 0, 60, 0.5, " px");
            slider("shape", "headerRadius", "Header", 0, 60, 0.5, " px");
            slider("shape", "thumbRadius", "Thumbnails", 0, 80, 0.5, " px");
            slider("shape", "entryRadius", "Search field", 0, 24, 0.5, " px");

            group("Borders");
            slider("shape", "border", "Windows", 0, 12, 0.5, " px");
            slider("shape", "thumbBorder", "Thumbnails", 0, 12, 0.5, " px");

            group("Mode menu");
            slider("shape", "pillInset", "Pill inset", 0, 30, 0.25, " px");
            slider("shape", "ringWidth", "Ring width", 0, 20, 0.5, " px");
            slider("shape", "ringInset", "Ring inset", 0, 30, 0.5, " px");
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
            slider("animation", "stagger", "Thumbnail stagger", 0, 80, 1, " ms");
            break;

        case "layout":
            group("Grid");
            slider("layout", "columns", "Columns", 1, 8, 1);
            slider("layout", "spacing", "Column spacing", 0, 40, 0.5, " px");
            slider("layout", "rowSpacing", "Row spacing", 0, 40, 0.5, " px");

            group("Thumbnails");
            slider("layout", "thumbAspect", "Aspect", 1, 3, 0.01, "");
            slider("layout", "thumbZoom", "Zoom", 100, 700, 5, " px");
            slider("layout", "thumbPadding", "Padding", 0, 40, 0.5, " px");

            group("Wallpaper backdrop");
            slider("layout", "backdropZoom", "Zoom", 0.5, 3, 0.01, "×");
            slider("layout", "backdropPosition", "Framing", 0, 1, 0.01, "");
            slider("layout", "backdropBlur", "Blur", 0, 1, 0.01, "");
            slider("layout", "backdropDim", "Dim", 0, 1, 0.01, "");

            group("Picker window");
            slider("layout", "pickerWidth", "Width", 400, 1800, 2, " px");
            slider("layout", "pickerHeight", "Height", 300, 1400, 2, " px");
            slider("layout", "padding", "Padding", 0, 60, 0.5, " px");
            slider("layout", "headerHeight", "Header height", 60, 500, 2, " px");

            group("Search field");
            slider("layout", "entryWidth", "Width", 100, 700, 2, " px");
            slider("layout", "entryHeight", "Height", 24, 100, 0.5, " px");
            slider("layout", "textSize", "Text size", 8, 40, 1, " px");

            group("Mode menu");
            slider("layout", "menuWidth", "Width", 300, 1600, 2, " px");
            slider("layout", "menuHeight", "Height", 80, 600, 2, " px");
            slider("layout", "menuColumns", "Columns", 1, 4, 1);
            slider("layout", "iconSize", "Icon size", 20, 140, 1, " px");
            break;

        case "colors":
            group("Window");
            slider("colors", "opacity", "Background opacity", 0.2, 1, 0.01, "");

            group("Palette");
            for (const colour of panel.colorKeys) {
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

        rows.push({
            kind: "header",
            label: ""
        });
        rows.push({
            kind: "reset",
            group: panel.tabs[panel.tab].key,
            label: `Reset ${panel.tabs[panel.tab].label.toLowerCase()} to the rofi defaults`
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

    function trigger() {
        const row = panel.rows[panel.currentIndex];
        if (row.kind === "reset") {
            Settings.reset(row.group);
            return;
        }
        const item = panel.currentWidget();
        if (item && item.flip)
            item.flip();
    }

    function handleKey(event): bool {
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
            // Puts back the tab you are in, rather than everything.
            Settings.reset(panel.tabs[panel.tab].key);
            return true;
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
            text: "Settings"
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

                Repeater {
                    model: panel.tabs

                    delegate: Item {
                        id: tabItem

                        required property int index
                        required property var modelData
                        readonly property bool current: panel.tab === tabItem.index

                        width: label.implicitWidth + 30
                        height: tabBar.height

                        Text {
                            id: label

                            anchors.centerIn: parent
                            text: tabItem.modelData.label
                            color: tabItem.current ? Colors.background : Colors.foreground
                            opacity: tabItem.current ? 1 : 0.7
                            font.family: Style.textFont
                            font.pixelSize: Style.textSize

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
            width: tabBar.width
            height: parent.height - y - Style.picker.headerX
            clip: true
            interactive: false // the wheel is handled below, like the grid's
            contentHeight: column.height

            Behavior on contentY {
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
                                case "colour":
                                    return colourRow;
                                case "channel":
                                    return channelRow;
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
                            id: colourRow

                            SettingColor {
                                width: loader.width
                                label: line.modelData.label
                                key: line.modelData.key
                                selected: line.current
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
                                    onClicked: Settings.reset(line.modelData.group)
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
    }
}
