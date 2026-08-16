<div align="center">

<img src="https://github.com/tungsten-w/lumen/blob/main/showcase/lumen%20design%20smol.png?raw=1" alt="Lumen" width="460">

#  ✦ Lumen ✦

**One wallpaper. One command. Your whole desktop shifts.**

A rofi-driven wallpaper picker that paints your entire Hyprland desktop —> light or dark from a single image.
This is built for Wayland and more specifically for hyprland.

![version](https://img.shields.io/badge/version-2.3.1-474064?style=flat-square) ![Rust](https://img.shields.io/badge/built_with-Rust-474064?style=flat-square&logo=rust&logoColor=white) ![Hyprland](https://img.shields.io/badge/Wayland-Hyprland-474064?style=flat-square&logo=hyprland&logoColor=white) ![License](https://img.shields.io/badge/license-MIT-474064?style=flat-square)

</div>

---

##  ⚡ Quick start

```bash
# 1 — grab the latest binary from the Releases page
tar xzf lumen-*-x86_64-linux-gnu.tar.gz
sudo install -m 755 lumen /usr/local/bin/

# 2 — drop your wallpapers in
mkdir -p ~/Pictures/Wallpapers/{dark,light}
```

```ini
# 3 — bind it in ~/.config/hypr/hyprland.conf
bind = $mainMod, W, exec, /usr/local/bin/lumen
```

That's it — hit <kbd>Super</kbd>+<kbd>W</kbd> and pick an image.

---

##  What is this?

`lumen` picks a wallpaper and **propagates its palette across your entire desktop** in one shot.
Choose an image through a rofi menu or let `lumen` pick one automatically based on the
**season and/or time of day** and watch pywal, matugen, your cursor, Noctalia Shell, Obsidian
and more all switch to match, light or dark.

No more editing five config files by hand every time you change your background.

---

<div align="center">

![Lumen showcase](https://github.com/tungsten-w/lumen/blob/main/showcase/showcase.png?raw=1)

</div>

---

##  Features

-  **Wallpaper switching** with smooth transitions via [`awww`](https://github.com/LGFae/swww)
-  **Quickshell picker** with live thumbnail previews (auto-generated with ImageMagick) — animated, with rofi kept as a fallback
-  **Coordinated light / dark theming** across the whole system
-  **Dual palette engines** [pywal](https://github.com/dylanaraps/pywal) + [matugen](https://github.com/InioX/matugen) (GTK, rofi, tmux, Ghostty, Spicetify, Neovim…)
-  **Cursor swap** Bibata Classic (dark) ↔ Bibata Ice (light)
-  **Noctalia Shell v5** theme + wallpaper sync
-  **Obsidian** base-theme switching (Obsidian dark ↔ Moonstone light)
-  **Spicetify** live re-theme when Spotify is running
-  **Auto mode** pick a random wallpaper by *time of day* (day / sunset / night)
-  **Seasonal mode** pick a random wallpaper by *season*
-  **recognition script** a script that recognizes what's on a wall (animal/colors...) (not fully implemented yet)

---

##  How it works

```
   wallpaper  ─►  matugen / pywal  ─►  palette extracted
       │                                     │
       └──────────────►  palette propagated across:
                         GTK · rofi · tmux · Ghostty · Spicetify
                         cursor · Noctalia Shell · Obsidian · hyprlock
```

Pick an image, and its colors ripple out to every themed component of the desktop —
in dark or light mode depending on your choice (or the time of day).

---

##  Dependencies

| Tool | Role |
|------|------|
| [`awww`](https://github.com/LGFae/swww) | Wallpaper daemon + transitions |
| [`matugen`](https://github.com/InioX/matugen) | Material You palette generation |
| [`pywal`](https://github.com/dylanaraps/pywal) | Classic palette generation |
| `imagemagick` | Thumbnail generation + GIF handling |
| [`quickshell`](https://quickshell.org) | Wallpaper picker menu |
| `rofi` | Wallpaper picker menu *(fallback)* |
| `jq` | Editing Obsidian JSON configs |
| `hyprland` | Cursor + IPC (`hyprctl`) |
| Papirus icon theme | rofi thumbnail icons |
| `spicetify` | Spotify theming *(optional)* |

> ⚠️ Requires **Noctalia Shell v5** for the current theming IPC. (v4 support is commented out in the script if you are using an older version.)

---

##  Installation

### Option 1 — prebuilt binary (recommended)

Grab the latest `lumen-*-x86_64-linux-gnu.tar.gz` from the
[Releases page](https://github.com/tungsten-w/lumen/releases), then:

```bash
tar xzf lumen-*-x86_64-linux-gnu.tar.gz
chmod +x lumen
sudo mv lumen /usr/local/bin/
```

### Option 2 — build from source

```bash
git clone https://github.com/tungsten-w/lumen.git
cd lumen/lumen
cargo build --release
# binary at target/release/lumen
```

Bind it to a key in your Hyprland config, e.g.:
the recommended keybind is `W` (mod + W)
```ini
bind = $mainMod, W, exec, /usr/local/bin/lumen
```

Make sure the binary is on your `PATH` — the keybind can call it by its full
path, but `lumen --settings` and `lumen --help` need the name to resolve:

```bash
ln -s "$PWD/target/release/lumen" ~/.local/bin/lumen   # or install it in /usr/local/bin
```

### Then — the picker

```bash
# from a clone of this repo
ln -s "$PWD/quickshell/lumen" ~/.config/quickshell/lumen
```

If `~/.config/lumen` *is* your clone, there is nothing to do: `lumen` finds the
config there too.

---

##  The picker

The menu and the thumbnail grid are drawn by [Quickshell](https://quickshell.org)
(`quickshell/lumen/`). Out of the box they are a pixel-for-pixel copy of the old
rofi themes — same sizes, same colors, same rounded frames — with the movement
rofi could not do: the window springs open, the selection slides from one
wallpaper to the next, the grid rearranges itself as you type, and thumbnails
fade in as they decode. Every one of those numbers is then yours to change from
the settings panel below.

Colors are not duplicated anywhere: the QML reads the very same
`~/.config/rofi/colors.rasi` and `~/.cache/wal/colors-rofi-dark.rasi` the rasi
themes read, so the picker recolors itself with the rest of the desktop.

### Keys

The picker opens **in insert mode**, so you can type the name of a wallpaper the
moment the window is up — no mouse, no arrow keys. `hjkl` cannot double as
movement while you are typing (half these wallpapers start with an h, a j, a k or
an l), so the grid borrows vim's two modes instead:

| Insert mode | |
|---|---|
| type anything | Filter by name |
| <kbd>Enter</kbd> | Apply the selection |
| <kbd>Esc</kbd> | Leave insert mode, keeping the filter |

| Normal mode | |
|---|---|
| <kbd>h</kbd> <kbd>j</kbd> <kbd>k</kbd> <kbd>l</kbd> | Move through the grid |
| <kbd>g</kbd> <kbd>g</kbd> / <kbd>G</kbd> | First / last wallpaper |
| <kbd>Ctrl</kbd>+<kbd>d</kbd> / <kbd>Ctrl</kbd>+<kbd>u</kbd> | Half a screen down / up |
| <kbd>i</kbd> or <kbd>/</kbd> | Back to the search field |
| <kbd>q</kbd> / <kbd>Esc</kbd> | Cancel |

The search field is pink while it holds the keyboard and turns to the selection
color once it does not, and its cursor turns into a vim block — that is the whole
mode indicator.

Anything that is not a letter works from **either** mode, so you never have to
switch if you do not want to: arrows, <kbd>Enter</kbd>, <kbd>Home</kbd>/<kbd>End</kbd>,
<kbd>PageUp</kbd>/<kbd>PageDown</kbd>, and `hjkl`/`d`/`u` held with <kbd>Ctrl</kbd>
(rofi's own <kbd>Ctrl</kbd>+<kbd>j</kbd> / <kbd>Ctrl</kbd>+<kbd>k</kbd>, extended).
Clicking outside cancels. The mode menu takes `hjkl`, arrows, <kbd>Enter</kbd> and
<kbd>q</kbd> — it has nothing to type into, so it needs no modes.

<details>
<summary><b>&nbsp;⚙&nbsp; Settings</b> &mdash; <kbd>Ctrl</kbd>+<kbd>,</kbd>, or type <code>settings</code> in the picker &nbsp;<i>(click to unfold)</i></summary>

<br>

Three ways into the same panel, whichever is closest to hand:

```bash
lumen --settings            # from a terminal, with the picker beside it as a preview
```

- <kbd>Ctrl</kbd>+<kbd>,</kbd> from inside the picker or the mode menu;
- the **cog**, the fifth entry of the mode menu — it opens the panel straight on
  its **Menu** tab;
- or type **`settings` into the picker's search field**. The grid tells you it is
  a command as you type it, and the field clears itself once the panel is out.

Everything the panel changes is redrawn **live on the window right next to it**.
It is split into four tabs, so each list is short enough to see nearly whole:

| Tab | What is in it |
|---|---|
| **Menu** | Which of the four modes the mode menu offers |
| **Shape** | Corner radii (windows, header, thumbnails, search field), border widths, the mode menu's pill and ring |
| **Motion** | Animations on/off, speed, bounce, selection lift, and each duration on its own |
| **Layout** | Columns and spacing, thumbnail aspect / zoom / padding, **wallpaper backdrop zoom, framing, blur and dim**, window and header sizes, search field, mode menu |
| **Color** | Background opacity, blur behind the window, and the five palette colors |

| Panel | |
|---|---|
| <kbd>Tab</kbd> / <kbd>1</kbd>…<kbd>5</kbd> | Move between tabs |
| <kbd>j</kbd> / <kbd>k</kbd> | Move through the settings |
| <kbd>h</kbd> / <kbd>l</kbd> | Change the value (<kbd>Shift</kbd> for ten times the step) |
| <kbd>Enter</kbd> | Flip a switch, or pin a color |
| <kbd>r</kbd> | Reset the tab you are in |
| <kbd>Esc</kbd> / <kbd>q</kbd> | Close the panel |

Values are written to `~/.config/lumen/settings.json` as you move a slider —
there is no save button, and the file is hand-editable and watched, so writing to
it from an editor restyles an open picker. The last row of each tab, or
<kbd>r</kbd>, puts that tab back to the rofi measurements.

**Menu** switches the four entries of the mode menu on and off — drop `Season`
if you never use it and the menu is three entries long. The cog is not one of
them and never leaves, so turning the last mode off cannot lock you out.

Two of those deserve a word. **Thumbnails → Zoom** is how far into each
thumbnail the grid crops — rofi fitted the image in a 340px box and clipped it,
and that is the number.

**Wallpaper backdrop** is the big image across the header, and behind the mode
menu. rofi drew it at exactly the window's width, pinned to the top, with nothing
else on offer:

- **Zoom** — above 1× it crops left and right rather than squeezing.
- **Framing** — which band of it the header shows, 0 being the top rofi used.
- **Blur** and **Dim** — the frosted-glass version, with the search field
  floating on it. Both are 0 by default, and at 0 the whole effect is skipped
  rather than drawn as a no-op.

That blur is the wallpaper *inside* the header. For the desktop **behind the
whole window**, there is **Color → Blur behind the window**: the compositor
frosts what is under the cards — following their rounded corners, and the
settings panel as it slides out — while the rest of the screen stays sharp.

It only shows through once **Color → Background opacity** is under 1, and it asks
the compositor over `ext-background-effect`; a compositor that does not speak it
simply ignores the request. Hyprland 0.56 does.

Colors start on `auto`, which means "whatever pywal and matugen made of the
current wallpaper". Pressing <kbd>Enter</kbd> on one pins it to what is on screen
right now and opens hue, saturation and lightness under it; pressing
<kbd>Enter</kbd> again hands it back to the wallpaper.

</details>

---

**rofi is still there.** `lumen` falls back to the old themes whenever `qs` or
the Quickshell config is missing — or if `qs` fails to start — so nothing breaks
on a machine without Quickshell. To pin it by hand:

```bash
LUMEN_FRONTEND=rofi lumen        # always rofi
LUMEN_QS_CONFIG=/path/shell.qml  # a Quickshell config somewhere else
```

---

##  Expected wallpaper layout

`lumen` expects your wallpapers organised like this under `~/Pictures/Wallpapers/`:

```
~/Pictures/Wallpapers/
├── dark/                 # dark-mode wallpapers (thumbnail picker)
├── light/                # light-mode wallpapers (thumbnail picker)
└── season-time/
    ├── day/  sunset/  night/     # auto mode by time of day
    └── hiver/ printemps/ ete/ automne/   # auto mode by season
```

Thumbnails are generated automatically into a hidden `.thumbnails/` folder in each directory.

---

##  Usage

Launch `lumen` and pick a mode from the menu:

| Option | What it does |
|--------|--------------|
|  Dark | Browse `dark/` wallpapers with thumbnails |
|  Light | Browse `light/` wallpapers with thumbnails |
|  Time | Random wallpaper matching the current time of day |
|  Season | Random wallpaper matching the current season |
|  Settings | Open the settings panel — see below |

Any of the first four can be switched off from the settings, if you never use one.

---

##  My setup

Built and daily-driven on Hyprland.
Part of my dotfiles: [tungsten-w/.config](https://github.com/tungsten-w/.config)

---

##  Roadmap

- [ ] Config file for custom paths (drop the hard-coded `~/Pictures/Wallpapers`)
- [ ] Proper `install.sh` <--- (im working on it ( ˘͈ ᵕ ˘͈♡))
- [ ] Transitions
- [x] Settings panel (Ctrl+, / `lumen --settings`)
- [x] use rust instead of bash
- [x] Quickshell
---
##  License

Released under the [MIT License](LICENSE).
please feel free to fork and modify it to your liking.  
Art by : _.x1ansheng._   (check her instagram plz ૮꒰ ˶• ༝ •˶꒱ა ♡)
