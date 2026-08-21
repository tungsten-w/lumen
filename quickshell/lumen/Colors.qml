pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// Colors of the shell, read from the palette file a generator wrote.
///
/// Three of them run on every wallpaper change, and each leaves a rasi file
/// behind:
///
///     ~/.cache/wal/colors-rofi-dark.rasi   <- pywal, in rofi's own vocabulary
///     ~/.config/rofi/colors.rasi           <- matugen, Material You
///     ~/.config/rofi/noctalia.rasi         <- noctalia
///
/// The first two are what `wallpaper.rasi` and `wallpaperchoise.rasi` `@import`,
/// so parsing the files themselves rather than keeping a copy of the palette
/// means the Quickshell picker recolors itself on every wallpaper change for
/// free, and can never drift away from the rofi version. Which of the three is
/// read is a setting — `palettes` below is what each one is worth.
///
/// Any colour can be pinned to a fixed value in the settings panel; whatever is
/// left on `auto` keeps following the wallpaper.
///
/// The two windows are coloured separately — the menu can follow matugen while
/// the picker follows pywal, and either can be pinned without touching the
/// other. Which half is read is not a property of this file: it is the window
/// the process was started for, which is what `Settings.value` resolves for it.
Singleton {
    id: root

    // Where the default light wallpaper landed. Used until a file is parsed, if
    // the chosen one is missing, and for any slot it has nothing for — switching
    // source must not leave the previous one's colour sitting there.
    readonly property color fallbackBackground: "#f5f5f5"
    readonly property color fallbackForeground: "#3d3d3d"
    readonly property color fallbackUrgent: "#d16c95"
    readonly property color fallbackSelected: "#37adaa"
    readonly property color fallbackBorderColor: "#f5f5f5"

    // What the file said.
    property color autoBackground: root.fallbackBackground
    property color autoForeground: root.fallbackForeground
    property color autoUrgent: root.fallbackUrgent
    property color autoSelected: root.fallbackSelected
    property color autoBorderColor: root.fallbackBorderColor

    /// The five colours the picker needs, under the name each generator gives
    /// them. Only pywal speaks rofi's vocabulary — the other two write their own
    /// — so a slot is matched by what it *means* rather than by what it is
    /// called, and a palette missing one of them falls back rather than
    /// borrowing from a generator that is not the one you asked for.
    ///
    /// `thumbBorder` is the background everywhere: pywal aliases `border-color`
    /// to `@background`, which is what makes the line between two thumbnails
    /// read as a gap rather than as a frame. Pin it in the panel for a visible
    /// one.
    readonly property var palettes: ({
            pywal: {
                background: "background",
                foreground: "foreground",
                urgent: "urgent-background",
                selected: "selected-normal-background",
                thumbBorder: "border-color"
            },
            matugen: {
                background: "background",
                foreground: "foreground",
                // `urgent` is there too, but it is Material You's error red
                // rather than anything taken from the wallpaper: as the window
                // border it would be a red rectangle whatever is on screen.
                urgent: "border-color",
                selected: "accent",
                thumbBorder: "background"
            },
            noctalia: {
                background: "bg",
                foreground: "fg",
                urgent: "border",
                selected: "accent",
                thumbBorder: "bg"
            }
        })

    /// The palette being read. A settings file naming one we do not know — hand
    /// written, or left behind by a later version — falls back to pywal, which
    /// is what the picker has drawn since it was a rofi theme.
    readonly property string activePalette: root.palettes[Settings.value("colors", "palette")] ? Settings.value("colors", "palette") : "pywal"

    onActivePaletteChanged: root.reload()

    /// Returns the pinned colour if there is one, and the palette's otherwise.
    function pick(override: string, fallback: color): color {
        return (!override || override === Settings.auto) ? fallback : override;
    }

    /// Window background. Its opacity is a setting of its own, because rofi's
    /// was opaque and there is no palette entry for "see through".
    readonly property color background: Qt.alpha(root.pick(Settings.value("colors", "background"), root.autoBackground), Math.max(0, Math.min(1, Settings.value("colors", "opacity"))))
    readonly property color foreground: root.pick(Settings.value("colors", "foreground"), root.autoForeground)
    /// Border of the window, of the header and of the search field.
    readonly property color urgent: root.pick(Settings.value("colors", "border"), root.autoUrgent)
    /// Background of the selected element.
    readonly property color selected: root.pick(Settings.value("colors", "selection"), root.autoSelected)
    /// Border drawn around a thumbnail — a thin gap, unless it is pinned. The
    /// one colour with no menu half, since the menu draws no thumbnails.
    readonly property color borderColor: root.pick(Settings.colors.thumbBorder, root.autoBorderColor)

    /// The palette as read, ignoring the overrides — the panel shows these under
    /// each colour that is still on `auto`.
    function autoValue(name: string): color {
        switch (name) {
        case "background":
            return root.autoBackground;
        case "foreground":
            return root.autoForeground;
        case "border":
            return root.autoUrgent;
        case "selection":
            return root.autoSelected;
        case "thumbBorder":
            return root.autoBorderColor;
        }
        return root.autoForeground;
    }

    // All three are preloaded rather than only the one in use: switching source
    // in the panel then recolors the picker on the same frame, with no read.
    FileView {
        id: walColors
        path: `${Quickshell.env("HOME")}/.cache/wal/colors-rofi-dark.rasi`
        preload: true
        blockLoading: true // read once at startup, so a blocking read is fine
        printErrors: false // a missing file just means "keep the fallbacks"
    }

    FileView {
        id: matugenColors
        path: `${Quickshell.env("HOME")}/.config/rofi/colors.rasi`
        preload: true
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: noctaliaColors
        path: `${Quickshell.env("HOME")}/.config/rofi/noctalia.rasi`
        preload: true
        blockLoading: true
        printErrors: false
    }

    function paletteSource(name: string): string {
        switch (name) {
        case "matugen":
            return matugenColors.text();
        case "noctalia":
            return noctaliaColors.text();
        default:
            return walColors.text();
        }
    }

    /// Pulls `name: value;` pairs out of the global `* { ... }` block of a rasi
    /// file. Widget blocks (`#window { ... }`, `element { ... }`, …) are skipped:
    /// only the global block defines the palette. It matters more than it looks
    /// for noctalia, whose file is a whole theme rather than a list of colours.
    function parseRasi(source: string): var {
        const declarations = {};
        if (!source)
            return declarations;

        const globalBlock = /\*\s*\{([^}]*)\}/.exec(source);
        if (!globalBlock)
            return declarations;

        const declaration = /([A-Za-z-]+)\s*:\s*([^;]+);/g;
        let match;
        while ((match = declaration.exec(globalBlock[1])) !== null) {
            declarations[match[1]] = match[2].trim();
        }
        return declarations;
    }

    /// Resolves rasi's `@name` references (`normal-background: @background;`).
    /// Chains are short, but a bounded loop keeps a cyclic file from hanging us.
    function resolve(declarations: var, name: string): string {
        let value = declarations[name];
        for (let hop = 0; hop < 8 && value && value.charAt(0) === "@"; hop++) {
            value = declarations[value.slice(1)];
        }
        return (value && value.charAt(0) === "#") ? value : "";
    }

    function reload() {
        const declarations = root.parseRasi(root.paletteSource(root.activePalette));
        const keys = root.palettes[root.activePalette];

        const apply = (name, target, fallback) => {
            root[target] = root.resolve(declarations, name) || fallback;
        };

        apply(keys.background, "autoBackground", root.fallbackBackground);
        apply(keys.foreground, "autoForeground", root.fallbackForeground);
        apply(keys.urgent, "autoUrgent", root.fallbackUrgent);
        apply(keys.selected, "autoSelected", root.fallbackSelected);
        apply(keys.thumbBorder, "autoBorderColor", root.fallbackBorderColor);
    }

    Component.onCompleted: root.reload()
}
