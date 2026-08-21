pragma Singleton

import QtQml
import Quickshell

/// The numbers the windows are drawn with.
///
/// Nothing is stored here: every value is either read from Settings — which the
/// panel edits and which defaults to the rofi measurements — or derived from
/// them. The derivations are what keep the picker coherent when a setting moves:
/// ask for four columns and the thumbnails resize themselves, make the window
/// narrower and the grid follows.
///
/// The measurements themselves are not re-derived from the rasi source, because
/// rofi's box model rounds its own way. They were taken off a screenshot of the
/// real thing at scale 1, and are quoted in Settings.qml next to each default.
Singleton {
    id: root

    // ── Fonts ──────────────────────────────────────────────────────────
    /// `font: "Comfortaa 12"` — the search field.
    readonly property string textFont: "Comfortaa"
    readonly property int textSize: Settings.layout.textSize
    /// The four menu glyphs are Nerd Font codepoints. rofi lets fontconfig find
    /// them; naming the font outright is what makes Qt pick the same glyphs.
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    /// `font: "comfortaa 45"` — the menu glyphs.
    readonly property int iconSize: Settings.layout.iconSize

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

    /// The wallpaper drawn behind the mode menu and across the picker's header.
    /// Four knobs each rather than four between them: the same image fills a
    /// whole card in one window and a strip in the other, so a framing that
    /// suits the menu rarely suits the picker.
    readonly property QtObject backdrop: QtObject {
        /// 1 is rasi's `url(…, width)`: exactly as wide as the window it fills.
        readonly property real zoom: Math.max(0.2, Settings.value("layout", "backdropZoom"))
        /// Which band of the image shows once it is taller than the strip it is
        /// drawn in. 0 is the top, which is where rofi left it.
        readonly property real position: Math.max(0, Math.min(1, Settings.value("layout", "backdropPosition")))
        /// Frosted glass. 0 leaves the image exactly as rofi drew it, and skips
        /// the render pass entirely.
        readonly property real blur: Math.max(0, Math.min(1, Settings.value("layout", "backdropBlur")))
        readonly property real dim: Math.max(0, Math.min(1, Settings.value("layout", "backdropDim")))
    }

    // ── Mode menu (wallpaperchoise.rasi) ───────────────────────────────
    readonly property QtObject menu: QtObject {
        readonly property real width: Settings.layout.menuWidth
        readonly property real height: Settings.layout.menuHeight
        readonly property real radius: Settings.shape.menuWindowRadius
        readonly property real border: Settings.shape.menuBorder

        /// The white capsule behind the entries: the backgrounds of the elements,
        /// which merge into one rounded bar because they sit edge to edge. rofi
        /// left one pixel more on the sides than above, hence the two insets.
        readonly property real insetX: 21
        readonly property real insetY: 20
        readonly property real barWidth: width - insetX * 2
        readonly property real barHeight: height - insetY * 2

        /// Two columns per row (`listview { columns: 2; }`), two rows for the
        /// four entries, and only one row fits — hence the scrolling.
        readonly property int columns: Math.max(1, Settings.layout.menuColumns)
        readonly property real cellWidth: barWidth / columns
        readonly property real cellHeight: barHeight

        /// Selected element: a pill inset inside its cell, with a ring of window
        /// background inside it (`element-text { border: 9px; }`).
        readonly property real pillInset: Settings.shape.pillInset
        readonly property real ringInset: Settings.shape.ringInset
        readonly property real ringWidth: Settings.shape.ringWidth
    }

    // ── Wallpaper picker (wallpaper.rasi) ──────────────────────────────
    readonly property QtObject picker: QtObject {
        readonly property real width: Settings.layout.pickerWidth
        readonly property real height: Settings.layout.pickerHeight
        readonly property real radius: Settings.shape.windowRadius
        readonly property real border: Settings.shape.border

        /// Header — `inputbar`, filled with the current wallpaper.
        readonly property real headerX: border + Settings.layout.padding
        readonly property real headerY: headerX
        readonly property real headerWidth: width - headerX * 2
        /// Capped so a short window cannot end up with a header taller than
        /// itself: the setting wins until there is no room left for it, and the
        /// grid takes whatever is under it.
        readonly property real headerHeight: Math.min(Settings.layout.headerHeight, Math.max(40, height - headerY * 2 - 4.5))
        readonly property real headerRadius: Settings.shape.headerRadius

        /// Search field. rofi's `padding: 100px 60px` put it 63 across and 103.5
        /// down; that is kept while the header is tall enough for it, and it
        /// centres itself once the header is shorter than that.
        readonly property real entryX: 60 + border
        /// …and never above the top of the header, which is where centring a
        /// field taller than the header would put it.
        readonly property real entryY: Math.max(0, Math.min(103.5, (headerHeight - entryHeight) / 2))
        readonly property real entryWidth: Settings.layout.entryWidth
        readonly property real entryHeight: Settings.layout.entryHeight
        readonly property real entryRadius: Settings.shape.entryRadius
        readonly property real entryPadding: 15 // entry { padding: 11px 15px; }
        readonly property string placeholder: " Wallpapers"
        /// Text cursor: a bar while typing, a vim block once Esc hands the keys
        /// to the grid.
        readonly property real caretWidth: 2
        readonly property real blockWidth: 11

        /// Thumbnail grid — `listview`, sitting 3px inside the window padding
        /// because the listview has a border of its own, and 4.5px under the
        /// header.
        readonly property real gridX: headerX + 3
        readonly property real gridY: headerY + headerHeight + 4.5
        readonly property real gridHeight: Math.max(0, height - gridY - border - Settings.layout.padding)

        readonly property int columns: Math.max(1, Settings.layout.columns)
        readonly property real spacing: Settings.layout.spacing
        readonly property real rowSpacing: Settings.layout.rowSpacing
        /// Width rofi kept free on the right for a scrollbar it never drew.
        readonly property real gutter: 24

        /// Never zero or negative: enough columns, at enough spacing, in a
        /// narrow enough window, asks for more room than there is. The grid
        /// overflows and is clipped instead of collapsing.
        readonly property real elementWidth: Math.max(8, (headerWidth - gutter - (columns - 1) * spacing) / columns)
        /// Padding plus a thumbnail of the requested shape.
        readonly property real elementHeight: (elementWidth - elementPadding * 2) / Math.max(0.2, Settings.layout.thumbAspect) + elementPadding * 2
        readonly property real elementRadius: Settings.shape.thumbRadius
        readonly property real elementPadding: Settings.layout.thumbPadding
        readonly property real columnPitch: elementWidth + spacing
        readonly property real rowPitch: elementHeight + rowSpacing

        /// Thumbnail — `element-icon { size: 340px; }`. rofi fits the image
        /// inside that box and lets the element clip it, so the visible crop is
        /// zoomed in rather than fitted to the element's shape.
        readonly property real iconBox: Settings.layout.thumbZoom
        readonly property real iconBorder: Settings.shape.thumbBorder
        readonly property real iconRadius: Settings.shape.thumbRadius
    }

    // ── Animation ──────────────────────────────────────────────────────
    // rofi drew all of this instantly. Turning `animation.enabled` off gives
    // that back exactly, since every duration below collapses to zero.
    //
    // Every one of these is stored twice — see Settings — so a menu you want to
    // snap open and a picker you want to glide can be asked for at once. Only
    // the stagger is single, because only the picker has a grid.
    readonly property real speed: Settings.value("animation", "enabled") ? Math.max(0.05, Settings.value("animation", "speed")) : 0

    function duration(base: int): int {
        if (root.speed === 0)
            return 0;
        // A duration is read straight into animations, and one that came out as
        // NaN — an empty settings file, a key edited to nonsense by hand — makes
        // Qt complain on every frame rather than fall back.
        const value = Math.round(base / root.speed);
        return isFinite(value) && value > 0 ? value : 0;
    }

    /// Window entrance, and the matching exit that runs before we hand the
    /// selection back to `lumen`.
    readonly property int enterDuration: root.duration(Settings.value("animation", "enter"))
    readonly property int exitDuration: root.duration(Settings.value("animation", "exit"))
    /// Selection travelling from one element to the next.
    readonly property int moveDuration: root.duration(Settings.value("animation", "move"))
    /// Hover feedback and thumbnail fade-in.
    readonly property int fadeDuration: root.duration(Settings.value("animation", "fade"))
    /// Scrolling, whether from the keyboard or the wheel.
    readonly property int scrollDuration: root.duration(Settings.value("animation", "scroll"))
    /// Per-item delay of the grid's staggered entrance, capped so that a long
    /// wallpaper directory does not take a second to appear.
    readonly property int stagger: root.duration(Settings.animation.stagger)
    readonly property int staggerCap: root.stagger * 15

    /// How far a springy animation overshoots. `extra` is that animation's share
    /// of the bounce, so one setting scales them all.
    function overshoot(extra: real): real {
        return 1 + extra * Math.max(0, Settings.value("animation", "bounce"));
    }

    /// The easing those animations use. `Easing.OutBack` still overshoots by a
    /// few percent at the smallest overshoot it accepts, so a bounce of zero
    /// has to change the curve rather than the number to actually be flat.
    readonly property int springEasing: Settings.value("animation", "bounce") > 0 ? Easing.OutBack : Easing.OutCubic

    /// Scale of the selected wallpaper. One setting drives every lift in the
    /// windows: `factor` is how many times more a given one grows, so setting
    /// the lift to 1 pins them all flat.
    function liftBy(factor: real): real {
        return 1 + (Settings.value("animation", "lift") - 1) * factor;
    }

    readonly property real lift: root.liftBy(1)
}
