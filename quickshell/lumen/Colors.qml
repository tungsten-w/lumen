pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// Colors of the shell, read from the exact same files the rofi themes read.
///
/// `wallpaper.rasi` and `wallpaperchoise.rasi` both start with:
///
///     @import "~/.config/rofi/colors.rasi"          <- written by matugen
///     @import "~/.cache/wal/colors-rofi-dark.rasi"  <- written by pywal
///
/// Parsing those two files instead of keeping a copy of the palette means the
/// Quickshell picker recolors itself on every wallpaper change for free, and can
/// never drift away from the rofi version.
/// Any of them can be pinned to a fixed colour in the settings panel; whatever
/// is left on `auto` keeps following the wallpaper.
Singleton {
    id: root

    // What the two files said. Until they are parsed — and if either one is
    // missing — these are the values pywal and matugen produced for the default
    // light palette.
    property color autoBackground: "#f5f5f5"
    property color autoForeground: "#3d3d3d"
    property color autoUrgent: "#d16c95"
    property color autoSelected: "#37adaa"
    property color autoBorderColor: "#f5f5f5"

    /// Returns the pinned colour if there is one, and the palette's otherwise.
    function pick(override: string, fallback: color): color {
        return (!override || override === Settings.auto) ? fallback : override;
    }

    /// Window background. Its opacity is a setting of its own, because rofi's
    /// was opaque and there is no palette entry for "see through".
    readonly property color background: Qt.alpha(root.pick(Settings.colors.background, root.autoBackground), Math.max(0, Math.min(1, Settings.colors.opacity)))
    readonly property color foreground: root.pick(Settings.colors.foreground, root.autoForeground)
    /// Border of the window, of the header and of the search field: `@urgent-background`.
    readonly property color urgent: root.pick(Settings.colors.border, root.autoUrgent)
    /// Background of the selected element: `@selected-normal-background`.
    readonly property color selected: root.pick(Settings.colors.selection, root.autoSelected)
    /// Border drawn around a thumbnail: `@border-color`, which pywal aliases to
    /// `@background`, so it reads as a thin gap rather than as a visible frame.
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

    /// Palette written by matugen. Loaded first, so pywal wins on shared keys —
    /// the same precedence the two `@import` lines give inside rofi.
    FileView {
        id: matugenColors
        path: `${Quickshell.env("HOME")}/.config/rofi/colors.rasi`
        preload: true
        blockLoading: true // parsed once at startup, so a blocking read is fine
        printErrors: false // a missing file just means "keep the fallbacks"
    }

    FileView {
        id: walColors
        path: `${Quickshell.env("HOME")}/.cache/wal/colors-rofi-dark.rasi`
        preload: true
        blockLoading: true
        printErrors: false
    }

    /// Pulls `name: value;` pairs out of the global `* { ... }` block of a rasi
    /// file. Widget blocks (`#window { ... }`, `#element { ... }`, …) are skipped:
    /// only the global block defines the palette both themes refer to.
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
        const declarations = root.parseRasi(matugenColors.text());
        const walDeclarations = root.parseRasi(walColors.text());
        for (const name in walDeclarations) {
            declarations[name] = walDeclarations[name];
        }

        const apply = (name, target) => {
            const value = root.resolve(declarations, name);
            if (value)
                root[target] = value;
        };

        apply("background", "autoBackground");
        apply("foreground", "autoForeground");
        apply("urgent-background", "autoUrgent");
        apply("selected-normal-background", "autoSelected");
        apply("border-color", "autoBorderColor");
    }

    Component.onCompleted: root.reload()
}
