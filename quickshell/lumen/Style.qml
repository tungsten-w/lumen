pragma Singleton

import QtQml
import Quickshell

/// Every measurement of the rofi originals, in one place.
///
/// The numbers are not re-derived from the rasi source: rofi's box model does
/// its own rounding, so they were measured off a screenshot of the real thing
/// (`wallpaper.rasi` and `wallpaperchoise.rasi`, at scale 1) and are quoted here
/// in the same logical pixels. Where a value matches a rasi declaration exactly
/// the declaration is named next to it.
Singleton {
    id: root

    // ── Fonts ──────────────────────────────────────────────────────────
    /// `font: "Comfortaa 12"` — the search field.
    readonly property string textFont: "Comfortaa"
    readonly property int textSize: 16 // 12pt at 96dpi
    /// The four menu glyphs are Nerd Font codepoints. rofi lets fontconfig find
    /// them; naming the font outright is what makes Qt pick the same glyphs.
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    /// `font: "comfortaa 45"` — the menu glyphs.
    readonly property int iconSize: 60 // 45pt at 96dpi

    /// The wallpaper currently on screen. `lumen` copies it here on every
    /// change, and both rasi themes use it as `background-image`.
    readonly property url wallpaper: root.fileUrl("/tmp/current_wallpaper.png")

    /// Turns a filesystem path into a URL an Image can load.
    ///
    /// Wallpaper names in this collection carry their dominant colour after a
    /// `#` (`autumn-red-#red.gif`), and a bare path handed to `Image.source` is
    /// parsed as a URL — so everything from the `#` on would be dropped as a
    /// fragment and the thumbnail would silently fail to open. Escaping each
    /// segment also covers the names with spaces.
    function fileUrl(path: string): url {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    // ── Mode menu (wallpaperchoise.rasi) ───────────────────────────────
    readonly property QtObject menu: QtObject {
        readonly property real width: 700 // window { width: 700px; }
        readonly property real height: 160 // window { height: 160px; }
        readonly property real radius: 20 // window { border-radius: 20px; }
        readonly property real border: 3 // window { border: 3px; }

        /// The white capsule behind the entries: the backgrounds of the elements,
        /// which merge into one rounded bar because they sit edge to edge.
        readonly property real inset: 20.5
        readonly property real barWidth: 658
        readonly property real barHeight: 120

        /// Two columns per row (`listview { columns: 2; }`), two rows for the
        /// four entries, and only one row fits — hence the scrolling.
        readonly property int columns: 2
        readonly property real cellWidth: 329
        readonly property real cellHeight: 120

        /// Selected element: a pill inset inside its cell, with a 9px ring of
        /// window background inside it (`element-text { border: 9px; }`).
        readonly property real pillInset: 6.75
        readonly property real ringInset: 10.5
        readonly property real ringWidth: 9
    }

    // ── Wallpaper picker (wallpaper.rasi) ──────────────────────────────
    readonly property QtObject picker: QtObject {
        readonly property real width: 998 // window { width: 998px; }
        readonly property real height: 844 // window { height: 844px; }
        readonly property real radius: 20 // window { border-radius: 20px; }
        readonly property real border: 3 // window { border: 3px; }

        /// Header — `inputbar`, padded 100px top and bottom around the field and
        /// filled with the current wallpaper.
        readonly property real headerX: 18 // 3px border + 15px window padding
        readonly property real headerY: 18
        readonly property real headerWidth: 962
        readonly property real headerHeight: 282.8
        readonly property real headerRadius: 10 // inputbar { border-radius: 10px; }

        /// Search field, positioned inside the header.
        readonly property real entryX: 63
        readonly property real entryY: 103.5
        readonly property real entryWidth: 288 // entry { width: 300px; }
        readonly property real entryHeight: 46.5
        readonly property real entryRadius: 3 // entry { border-radius: 1%; }
        readonly property real entryPadding: 15 // entry { padding: 11px 15px; }
        readonly property string placeholder: " Wallpapers"
        /// Text cursor: a bar while typing, a vim block once Esc hands the keys
        /// to the grid.
        readonly property real caretWidth: 2
        readonly property real blockWidth: 11

        /// Thumbnail grid — `listview { columns: 3; spacing: 10px; }`, sitting
        /// 3px inside the window padding because the listview has its own border.
        readonly property real gridX: 21
        readonly property real gridY: 305.3
        readonly property int columns: 3
        readonly property real elementWidth: 306
        readonly property real elementHeight: 165.7
        readonly property real columnSpacing: 10
        readonly property real rowSpacing: 10.5
        readonly property real elementRadius: 25 // element { border-radius: 25px; }
        readonly property real elementPadding: 10 // element { padding: 10px; }

        /// Thumbnail — `element-icon { size: 340px; border: 3px; }`. rofi fits
        /// the image inside a 340x340 box and lets the element clip whatever
        /// sticks out, so the visible crop is zoomed in on the thumbnail.
        readonly property real iconBox: 340
        readonly property real iconBorder: 3
        readonly property real iconRadius: 25 // element-icon { border-radius: 25px; }
    }

    // ── Animation ──────────────────────────────────────────────────────
    // Everything below is new: rofi draws all of this instantly.
    /// Window entrance, and the matching exit that runs before we hand the
    /// selection back to `lumen`.
    readonly property int enterDuration: 220
    readonly property int exitDuration: 140
    /// Selection travelling from one element to the next.
    readonly property int moveDuration: 200
    /// Hover feedback and thumbnail fade-in.
    readonly property int fadeDuration: 160
    /// Scrolling, whether from the keyboard or the wheel.
    readonly property int scrollDuration: 240
    /// Per-item delay of the grid's staggered entrance, capped so that a long
    /// wallpaper directory does not take a second to appear.
    readonly property int stagger: 18
    readonly property int staggerCap: 260
}
