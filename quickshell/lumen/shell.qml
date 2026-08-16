import Quickshell

/// Entry point of the Quickshell front-end for `lumen`.
///
/// `lumen` runs `qs -p <this file>` once per prompt and waits for it to exit,
/// the way it used to run `rofi -dmenu`. `$LUMEN_MODE` says which of the two
/// prompts to show:
///
///   menu      the four modes — dark, light, time of day, season
///   picker    the thumbnail grid for one wallpaper directory
///   settings  the same grid, with the settings panel already out and picking
///             disabled — this is what `lumen --settings` runs
///
/// See Result.qml for how the answer travels back.
ShellRoot {
    id: root

    readonly property string mode: Quickshell.env("LUMEN_MODE") ?? "menu"

    LazyLoader {
        active: root.mode === "menu"

        ModeMenu {}
    }

    LazyLoader {
        active: root.mode === "picker" || root.mode === "settings"

        WallpaperPicker {
            // In settings mode the grid is there to be looked at, not picked
            // from: it is the live preview of what the panel is changing.
            preview: root.mode === "settings"
            asideOpen: root.mode === "settings"
        }
    }
}
