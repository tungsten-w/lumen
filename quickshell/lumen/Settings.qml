pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// Everything the settings panel can change, stored as JSON.
///
/// The defaults below are not arbitrary: they are the measurements taken off the
/// original rofi windows, so an absent or empty settings file gives back exactly
/// the picker `wallpaper.rasi` and `wallpaperchoise.rasi` drew. Style.qml turns
/// them into the numbers the windows actually use.
///
/// The file is written back on every change — the panel has no save button — and
/// it is watched, so editing it by hand restyles an open picker as you save.
///
/// A knob both windows draw is stored twice, the mode menu's copy under the same
/// name with a `menu` prefix: `shape.border` is the picker's outline and
/// `shape.menuBorder` the menu's. That is the whole of the split — `scoped`
/// below turns a name into the one the running window owns, and everything that
/// reads a shared knob goes through it, so rounding the menu's corners can no
/// longer square the picker's. Keys only one window draws stay unprefixed.
Singleton {
    id: root

    readonly property var modes: adapter.modes
    readonly property var shape: adapter.shape
    readonly property var layout: adapter.layout
    readonly property var animation: adapter.animation
    readonly property var colors: adapter.colors
    readonly property var folders: adapter.folders

    /// A colour left on this keeps following the palette in `colors.palette`.
    readonly property string auto: "auto"

    /// Which of the two windows this process is drawing.
    ///
    /// `lumen` runs `qs` once per prompt, so the mode menu and the picker never
    /// share a process: the window is a property of the run rather than of a
    /// component, and `value` below can resolve it on its own instead of the
    /// forty-odd bindings that read a shared knob each having to be handed a
    /// scope. Read exactly the way shell.qml reads it, so the two cannot
    /// disagree — `settings` is the picker with its panel already out, which
    /// makes anything that is not `menu` the picker's.
    ///
    /// It lives here rather than in a singleton of its own because `Scope` is
    /// already a Quickshell type: a `Scope.qml` beside this one loads without
    /// complaint and then quietly resolves to theirs, which reads as an empty
    /// property and hands the mode menu the picker's half of everything.
    readonly property bool menuWindow: (Quickshell.env("LUMEN_MODE") ?? "menu") === "menu"

    /// True between a change and the write that carries it to disk.
    property bool pending: false

    function save() {
        if (!root.pending)
            return;
        root.pending = false;
        file.writeAdapter();
        echo.restart(); // the file change this causes is ours, and is ignored
    }

    /// Called before the window quits, since a change made in the last frame
    /// would otherwise never reach the file.
    function flush() {
        root.save();
    }

    Timer {
        id: echo
        interval: 300
    }

    FileView {
        id: file

        path: Quickshell.env("LUMEN_SETTINGS") ?? `${Quickshell.env("HOME")}/.config/lumen/settings.json`
        watchChanges: true
        printErrors: false // no file yet just means "all defaults"
        atomicWrites: true

        // Writing from inside onAdapterUpdated looks obvious and is a trap: the
        // write makes the adapter read itself back, and every change made later
        // in the same tick is dropped. Resetting a group — nine properties in a
        // row — only kept the first one. Deferring to the end of the tick fixes
        // that, and collapses a whole slider drag into a single write.
        onAdapterUpdated: {
            root.pending = true;
            Qt.callLater(root.save);
        }

        // A hand edit reloads the file live. Our own writes come back through
        // the same signal, so they are skipped: reloading them would restore
        // whatever was on disk over a value the panel has moved since.
        onFileChanged: {
            if (!root.pending && !echo.running)
                file.reload();
        }

        // A file written before the two windows had a knob each is carried
        // over to the split rather than half reset — see `adopt`.
        onLoaded: root.adopt()

        // First run: write the defaults out, so the file is there to be read,
        // edited by hand, or copied between machines even before the panel has
        // been touched.
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.pending = true;
                root.save();
            }
        }

        JsonAdapter {
            id: adapter

            /// Which of the four entries the mode menu offers. The way into the
            /// settings is not one of them: it is always there, or switching the
            /// last entry off would leave a menu with no way back.
            property JsonObject modes: JsonObject {
                property bool dark: true
                property bool light: true
                property bool time: true
                property bool season: true
            }

            /// Folders of your own, each an entry in the mode menu beside the
            /// four built-in ones:
            ///
            ///     { "name": "anime", "path": "/home/you/Pictures/anime",
            ///       "icon": "f1fc", "on": true }
            ///
            /// `icon` is a Nerd Font codepoint in hex, and `on` is the switch —
            /// a folder can be put away without being forgotten, the same way
            /// the four built-in entries can.
            ///
            /// A list rather than a group, and deliberately outside `defaults`:
            /// these are paths on *your* machine, not a look. A preset that
            /// carried them would rewrite a stranger's menu with folders that
            /// do not exist on their disk, and resetting a tab would throw away
            /// a collection rather than a colour. See `snapshot`.
            property var folders: []

            /// Corners and outlines.
            property JsonObject shape: JsonObject {
                property real windowRadius: 20 // window { border-radius: 20px; }
                property real border: 3 // window { border: 3px; }
                property real headerRadius: 10 // inputbar { border-radius: 10px; }
                property real entryRadius: 3 // entry { border-radius: 1%; }
                property real thumbRadius: 25 // element-icon { border-radius: 25px; }
                property real thumbBorder: 3 // element-icon { border: 3px; }
                /// Menu only: how far the selected pill sits inside its cell, and
                /// the ring of background drawn inside the pill.
                property real pillInset: 6.75
                property real ringInset: 10.5
                property real ringWidth: 9 // element-text { border: 9px; }
                /// The menu's half of the two outlines both windows have.
                property real menuWindowRadius: 20
                property real menuBorder: 3
            }

            /// Sizes and counts.
            property JsonObject layout: JsonObject {
                property real pickerWidth: 998
                property real pickerHeight: 844
                property real menuWidth: 700
                property real menuHeight: 160
                property real padding: 15 // window { padding: 15px; }
                property int columns: 3 // listview { columns: 3; }
                property int menuColumns: 2
                property real spacing: 10 // listview { spacing: 10px; }
                property real rowSpacing: 10.5
                /// Whether the grid opens in a fresh random order each time —
                /// still only the wallpapers of whichever folder was opened,
                /// dark, light, or one of your own, just not always led with
                /// the same handful.
                property bool shuffle: false
                property real thumbPadding: 10 // element { padding: 10px; }
                /// Width over height of the visible part of a thumbnail. Lower is
                /// taller: 1.78 shows a 16:9 wallpaper whole, the rofi default of
                /// 1.96 crops it slightly.
                property real thumbAspect: 1.963
                /// rofi fits the image in a box this wide before the element clips
                /// it, which is what zooms the visible crop in.
                property real thumbZoom: 340 // element-icon { size: 340px; }
                property real headerHeight: 282.8
                /// The wallpaper drawn in the header, and behind the mode menu.
                /// rasi scaled it to the width of the window and pinned it to the
                /// top, which is what 1 and 0 give back.
                property real backdropZoom: 1
                property real backdropPosition: 0
                /// Frosted-glass version of the same image: 0 is the photograph
                /// rofi drew, 1 is as soft as it goes. The dim goes with it —
                /// a blurred wallpaper is often too bright to read a field on.
                property real backdropBlur: 0
                property real backdropDim: 0
                /// Whether a GIF wallpaper is shown moving — in the backdrop and,
                /// for the picker, in the grid's selected thumbnail — or left on
                /// its first frame the way every other format always was. On by
                /// default, since that is what shipped first; this is the way
                /// back for whoever finds it distracting, or would rather not
                /// spend a decode on a movie nobody but them asked to see.
                property bool animateGifs: true
                /// The menu's half of the backdrop: it fills the whole card
                /// there and only the header here, so the framing that suits one
                /// rarely suits the other.
                property real menuBackdropZoom: 1
                property real menuBackdropPosition: 0
                property real menuBackdropBlur: 0
                property real menuBackdropDim: 0
                property bool menuAnimateGifs: true
                property real entryWidth: 288
                property real entryHeight: 46.5
                property real textSize: 16 // font: "Comfortaa 12"
                property real iconSize: 60 // font: "comfortaa 45"
            }

            /// Milliseconds, mostly. rofi drew all of this instantly.
            property JsonObject animation: JsonObject {
                property bool enabled: true
                /// Divides every duration: 2 is twice as fast, 0.5 half as fast.
                property real speed: 1
                property int enter: 220 // window opening
                property int exit: 140 // window closing
                property int move: 200 // selection travelling
                property int fade: 160 // hover, thumbnails arriving
                property int scroll: 240 // grid and menu scrolling
                property int stagger: 18 // delay between two thumbnails appearing
                /// Scales how far the springy animations overshoot. 0 removes the
                /// bounce without touching the durations.
                property real bounce: 1
                /// How much the selected wallpaper grows. 1 is flat.
                property real lift: 1.012
                /// The menu's half. Everything above is drawn by both windows —
                /// only the thumbnail stagger is the picker's alone, since the
                /// menu has no grid to stagger.
                property bool menuEnabled: true
                property real menuSpeed: 1
                property int menuEnter: 220
                property int menuExit: 140
                property int menuMove: 200
                property int menuFade: 160
                property int menuScroll: 240
                property real menuBounce: 1
                property real menuLift: 1.012
            }

            /// `"auto"` follows the wallpaper, anything else is a fixed colour.
            property JsonObject colors: JsonObject {
                /// Which generator's palette the `auto` colours read. `pywal`
                /// and `wallust` provide classic colors, `matugen` provides
                /// Material You, and `noctalia` provides the shell's own.
                property string palette: "pywal"
                property string background: "auto"
                property string foreground: "auto"
                property string border: "auto" // @urgent-background
                property string selection: "auto" // @selected-normal-background
                property string thumbBorder: "auto" // @border-color
                /// Opacity of the window background. rofi's was opaque.
                property real opacity: 1
                /// Asks the compositor to blur what is behind the windows, which
                /// only shows through once the opacity above is below 1.
                property bool blur: false
                /// The menu's half. `thumbBorder` has no twin: it is the line
                /// round a thumbnail, and the menu draws none.
                property string menuPalette: "pywal"
                property string menuBackground: "auto"
                property string menuForeground: "auto"
                property string menuBorder: "auto"
                property string menuSelection: "auto"
                property real menuOpacity: 1
                property bool menuBlur: false
            }
        }
    }

    /// Every default, and the reason they live in this file rather than in
    /// Style: the panel's reset has to be able to read them back.
    ///
    /// `folders` is not here on purpose — see the property itself. Everything
    /// that walks this object (reset, snapshot, applyValues, satisfies) is about
    /// values a preset can carry between machines, and a folder path is not one.
    readonly property var defaults: ({
        modes: {
            dark: true,
            light: true,
            time: true,
            season: true
        },
        shape: {
            windowRadius: 20,
            border: 3,
            headerRadius: 10,
            entryRadius: 3,
            thumbRadius: 25,
            thumbBorder: 3,
            pillInset: 6.75,
            ringInset: 10.5,
            ringWidth: 9,
            menuWindowRadius: 20,
            menuBorder: 3
        },
        layout: {
            pickerWidth: 998,
            pickerHeight: 844,
            menuWidth: 700,
            menuHeight: 160,
            padding: 15,
            columns: 3,
            menuColumns: 2,
            spacing: 10,
            rowSpacing: 10.5,
            shuffle: false,
            thumbPadding: 10,
            thumbAspect: 1.963,
            thumbZoom: 340,
            headerHeight: 282.8,
            backdropZoom: 1,
            backdropPosition: 0,
            backdropBlur: 0,
            backdropDim: 0,
            animateGifs: true,
            menuBackdropZoom: 1,
            menuAnimateGifs: true,
            menuBackdropPosition: 0,
            menuBackdropBlur: 0,
            menuBackdropDim: 0,
            entryWidth: 288,
            entryHeight: 46.5,
            textSize: 16,
            iconSize: 60
        },
        animation: {
            enabled: true,
            speed: 1,
            enter: 220,
            exit: 140,
            move: 200,
            fade: 160,
            scroll: 240,
            stagger: 18,
            bounce: 1,
            lift: 1.012,
            menuEnabled: true,
            menuSpeed: 1,
            menuEnter: 220,
            menuExit: 140,
            menuMove: 200,
            menuFade: 160,
            menuScroll: 240,
            menuBounce: 1,
            menuLift: 1.012
        },
        colors: {
            blur: false,
            palette: "pywal",
            background: "auto",
            foreground: "auto",
            border: "auto",
            selection: "auto",
            thumbBorder: "auto",
            opacity: 1,
            menuPalette: "pywal",
            menuBackground: "auto",
            menuForeground: "auto",
            menuBorder: "auto",
            menuSelection: "auto",
            menuOpacity: 1,
            menuBlur: false
        }
    })

    /// The knobs this version split in two, under the name the mode menu's half
    /// went under.
    ///
    /// Written out rather than found by looking for a `menu` prefix, because
    /// `layout.menuColumns` carries one and was never a half of anything — the
    /// menu has had its own column count all along, and seeding it from the
    /// picker's grid would put four columns in a menu of four entries.
    readonly property var adopted: ({
        shape: ["menuWindowRadius", "menuBorder"],
        layout: ["menuBackdropZoom", "menuBackdropPosition", "menuBackdropBlur", "menuBackdropDim"],
        animation: ["menuEnabled", "menuSpeed", "menuEnter", "menuExit", "menuMove", "menuFade", "menuScroll", "menuBounce", "menuLift"],
        colors: ["menuPalette", "menuBackground", "menuForeground", "menuBorder", "menuSelection", "menuOpacity", "menuBlur"]
    })

    /// Carries a settings file written before the split over to it.
    ///
    /// Until now the two windows shared one knob, so what is in the file is as
    /// much what the mode menu has been drawn with as the picker. Left alone, an
    /// upgrade would hand the menu the rofi defaults and quietly undo however
    /// long was spent on it: a 60px corner and no border would come back as a
    /// 20px corner and a 3px one. So a half the file has never heard of starts
    /// as a copy of the knob it used to be, and only a file that already knows
    /// about both keeps them apart.
    ///
    /// The write this causes puts every key in, so it is a one-time thing rather
    /// than something that runs on every load.
    function adopt() {
        let stored;
        try {
            stored = JSON.parse(file.text());
        } catch (error) {
            return; // no file yet, or one we cannot read: the defaults stand
        }
        if (!stored || typeof stored !== "object")
            return;
        for (const group in root.adopted) {
            const incoming = stored[group];
            if (!incoming || typeof incoming !== "object")
                continue;
            for (const key of root.adopted[group]) {
                const was = key.charAt(4).toLowerCase() + key.slice(5);
                if (!(key in incoming) && was in incoming)
                    adapter[group][key] = incoming[was];
            }
        }
    }

    /// Replaces the folder list.
    ///
    /// `folders` above is a read-only view of the adapter, the way every group
    /// is. A group needs no setter because its *properties* are written one at a
    /// time; a list is replaced whole, so it needs this.
    function setFolders(list: var) {
        // Not `Array.isArray`: that is false for anything handed back by the
        // adapter itself, so testing it that way would quietly wipe the list.
        adapter.folders = (list && list.length !== undefined) ? list : [];
    }

    /// A folder's `icon` — a Nerd Font codepoint in hex — as a character.
    ///
    /// Blank or unparseable falls back to a plain folder rather than to the
    /// empty box a bad codepoint draws. The mode menu and the settings panel
    /// both read the field, so it is spelt out once here.
    function glyph(hex: string): string {
        const point = parseInt(hex, 16);
        return isFinite(point) && point > 0 ? String.fromCodePoint(point) : String.fromCodePoint(0xf07b);
    }

    /// Whether that codepoint is one the font could draw at all.
    function drawable(hex: string): bool {
        const point = parseInt(hex, 16);
        return isFinite(point) && point > 0;
    }

    /// The name a shared knob goes under for one of the two windows.
    ///
    /// The mode menu's copy of a knob both windows draw is the same key with a
    /// `menu` prefix. A key with no such twin in the defaults is drawn by one
    /// window only and is returned untouched, which is what makes this safe to
    /// run over every row the panel builds and every value the singletons read
    /// — nothing has to keep a list of which keys are shared, because the twin
    /// existing *is* the list.
    function scoped(group: string, key: string, menu: bool): string {
        if (!menu)
            return key;
        const twin = "menu" + key.charAt(0).toUpperCase() + key.slice(1);
        const known = root.defaults[group];
        return (known && twin in known) ? twin : key;
    }

    /// What a knob is worth in the window this process is drawing.
    ///
    /// Style and Colors hold what both windows are drawn with and are built
    /// once per run, so they resolve the scope themselves rather than being
    /// handed it — see `menuWindow`. Reading through the subscript keeps the
    /// bindings live: Qt captures the property behind it just as it would a
    /// named one.
    function value(group: string, key: string): var {
        return adapter[group][root.scoped(group, key, root.menuWindow)];
    }

    /// Puts one whole group back to the rofi measurements.
    function reset(group: string) {
        root.resetKeys(group, Object.keys(root.defaults[group]));
    }

    /// Puts back only the named keys of a group.
    ///
    /// The panel resets a tab rather than a group, and since the split a tab is
    /// only ever part of one: the mode menu's Shape tab and the picker's are
    /// both the `shape` group, and neither may reset the other window's knobs.
    /// The keys it hands over are already scoped, so a tab puts back its own
    /// window's half and leaves the twin where it was.
    function resetKeys(group: string, keys: var) {
        const values = root.defaults[group];
        if (!values)
            return;
        for (const key of keys) {
            if (key in values)
                adapter[group][key] = values[key];
        }
    }

    function resetAll() {
        for (const group in root.defaults) {
            root.reset(group);
        }
    }

    /// The whole configuration as a plain object, which is what a preset saves.
    ///
    /// Given a `shape` — a preset as it is on disk — only the groups and keys
    /// that preset already holds come back, carrying what they are worth now.
    /// That is what makes the panel's *Update* refresh a preset rather than
    /// replace it: a file holding nothing but `colors` is still a colours-only
    /// preset afterwards, which is the whole point of having one. Keys the file
    /// carries that are not ours are dropped on the way, the same way applying
    /// one skips them.
    function snapshot(shape: var): var {
        const out = {};
        for (const group in root.defaults) {
            const held = shape ? shape[group] : null;
            if (shape && (!held || typeof held !== "object"))
                continue;
            out[group] = {};
            for (const key in root.defaults[group]) {
                if (shape && !(key in held))
                    continue;
                out[group][key] = adapter[group][key];
            }
        }
        return out;
    }

    /// Whether the configuration on screen already holds everything `values`
    /// does — so that applying it would change nothing.
    ///
    /// This is what lets a preset row say *this is what you have*. It is a
    /// comparison rather than a name written down when a preset was applied,
    /// because a name would still be there after the first slider you moved,
    /// which is exactly when you most want to be told you have left it.
    ///
    /// Judged on the subset a file carries, the same rule `applyValues` writes
    /// by: a preset holding nothing but `colors` is satisfied whenever the
    /// colours agree, whatever the layout is doing. A file with nothing we
    /// recognise in it satisfies nothing.
    function satisfies(values: var): bool {
        if (!values || typeof values !== "object")
            return false;
        let seen = 0;
        for (const group in values) {
            const known = root.defaults[group];
            const incoming = values[group];
            if (!known || !incoming || typeof incoming !== "object")
                continue;
            for (const key in incoming) {
                if (!(key in known))
                    continue;
                seen++;
                const mine = adapter[group][key];
                const theirs = incoming[key];
                // Sliders step in quarters and hundredths, and a value that has
                // been through JSON and back can land a hair off exact.
                const equal = (typeof mine === "number" && typeof theirs === "number") ? Math.abs(mine - theirs) < 1e-6 : mine === theirs;
                if (!equal)
                    return false;
            }
        }
        return seen > 0;
    }

    /// Writes back whatever a preset carries, and leaves everything else where
    /// it was: a file holding nothing but `colors` restyles the palette without
    /// touching the layout, which is what makes a colours-only preset worth
    /// passing around.
    ///
    /// Groups and keys that are not ours are skipped rather than trusted. These
    /// files are hand-edited and copied between machines, and one typo should
    /// cost you that line rather than the whole preset.
    function applyValues(values: var) {
        if (!values || typeof values !== "object")
            return;
        for (const group in values) {
            const known = root.defaults[group];
            const incoming = values[group];
            if (!known || !incoming || typeof incoming !== "object")
                continue;
            for (const key in incoming) {
                if (key in known)
                    adapter[group][key] = incoming[key];
            }
        }
    }
}
