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
Singleton {
    id: root

    readonly property var modes: adapter.modes
    readonly property var shape: adapter.shape
    readonly property var layout: adapter.layout
    readonly property var animation: adapter.animation
    readonly property var colors: adapter.colors

    /// A colour left on this keeps following the palette in `colors.palette`.
    readonly property string auto: "auto"

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
            }

            /// `"auto"` follows the wallpaper, anything else is a fixed colour.
            property JsonObject colors: JsonObject {
                /// Which generator's palette the `auto` colours read. All three
                /// are rewritten on every wallpaper change, so this picks the
                /// look rather than whether the colours follow along: `pywal`
                /// for the classic sixteen the rofi themes drew, `matugen` for
                /// Material You, `noctalia` for the shell's own.
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
            }
        }
    }

    /// Every default, and the reason they live in this file rather than in
    /// Style: the panel's reset has to be able to read them back.
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
            ringWidth: 9
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
            thumbPadding: 10,
            thumbAspect: 1.963,
            thumbZoom: 340,
            headerHeight: 282.8,
            backdropZoom: 1,
            backdropPosition: 0,
            backdropBlur: 0,
            backdropDim: 0,
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
            lift: 1.012
        },
        colors: {
            blur: false,
            palette: "pywal",
            background: "auto",
            foreground: "auto",
            border: "auto",
            selection: "auto",
            thumbBorder: "auto",
            opacity: 1
        }
    })

    /// Puts one whole group back to the rofi measurements.
    function reset(group: string) {
        root.resetKeys(group, Object.keys(root.defaults[group]));
    }

    /// Puts back only the named keys of a group.
    ///
    /// The panel resets a tab rather than a group, and since the split a tab is
    /// only ever part of one: the mode menu's Shape tab and the picker's are
    /// both the `shape` group, and neither may reset the other window's knobs.
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
    function snapshot(): var {
        const out = {};
        for (const group in root.defaults) {
            out[group] = {};
            for (const key in root.defaults[group]) {
                out[group][key] = adapter[group][key];
            }
        }
        return out;
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
