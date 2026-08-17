<div align="center">

<img src="https://github.com/tungsten-w/lumen/blob/main/showcase/lumen%20design%20smol.png?raw=1" alt="Lumen" width="460">

#  ✦ Lumen ✦

**One wallpaper. One command. Your whole desktop shifts.**

Pick an image, and its colors ripple out to every themed corner of your Hyprland
desktop — light or dark, in one keypress.

![version](https://img.shields.io/badge/version-2.3.1-474064?style=flat-square) ![Rust](https://img.shields.io/badge/built_with-Rust-474064?style=flat-square&logo=rust&logoColor=white) ![Hyprland](https://img.shields.io/badge/Wayland-Hyprland-474064?style=flat-square&logo=hyprland&logoColor=white) ![Quickshell](https://img.shields.io/badge/UI-Quickshell-474064?style=flat-square) ![License](https://img.shields.io/badge/license-MIT-474064?style=flat-square)

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

Changing a wallpaper usually means changing a wallpaper. Here it means changing
**the desktop**: `lumen` extracts the palette of the image you picked and pushes
it through every app that will listen, then flips the whole system to light or
dark to match.

```
   wallpaper  ─►  matugen / pywal  ─►  palette extracted
       │                                     │
       └──────────────►  palette propagated across:
                         GTK · rofi · tmux · Ghostty · Spicetify
                         cursor · Noctalia Shell · Obsidian · hyprlock
```

No more editing five config files by hand every time you change your background.
Pick it yourself from a thumbnail grid, or let `lumen` choose one for the time of
day or the season and never think about it again.

---

<div align="center">

![Lumen showcase](https://github.com/tungsten-w/lumen/blob/main/showcase/showcase.png?raw=1)

</div>

---

##  Features

- **Whole-desktop theming** — one image repaints GTK, rofi, tmux, Ghostty,
  Neovim, Spotify, Obsidian, your shell and your lock screen.
- **Two palette engines at once** — [pywal](https://github.com/dylanaraps/pywal)
  for the classic sixteen, [matugen](https://github.com/InioX/matugen) for
  Material You. Both run in parallel, and they feed different apps.
- **An animated picker** drawn with [Quickshell](https://quickshell.org): a
  thumbnail grid that filters as you type, slides its selection around, and fades
  each thumbnail in as it decodes.
- **Vim keys everywhere** — `hjkl`, `gg`/`G`, `Ctrl+d`/`Ctrl+u`, two modes, and a
  block cursor to tell you which one you are in.
- **A settings panel with 53 knobs** — corner radii, animation timings, column
  counts, blur, colors — every one of them redrawn **live** on the picker next to
  it, none of them needing a restart.
- **Real blur** — frosted glass over the wallpaper in the header, and compositor
  blur behind the window itself.
- **Light / dark that means something** — the cursor swaps (Bibata Classic ↔
  Ice), Obsidian switches base theme, Noctalia flips mode, Spotify reloads its
  colors without restarting.
- **Smooth wallpaper transitions** through [`awww`](https://github.com/LGFae/swww).
- **Set and forget** — `lumen --time` and `lumen --season` pick for you, with no
  prompt at all, ready for a timer.
- **rofi is still there** as a fallback, pixel for pixel, for machines without
  Quickshell.
- **Written in Rust**, so the whole thing is done in about the time the
  transition takes.
- **Wallpaper recognition** — a script that reads what is *in* the image
  (animals, colors…). Half-built, and honest about it.

---

##  Usage

Launch `lumen` and pick a mode from the menu:

| | Option | What it does |
|---|--------|--------------|
| 🌙 | Dark | Browse `dark/` wallpapers with thumbnails |
| ☀️ | Light | Browse `light/` wallpapers with thumbnails |
| 🕘 | Time | Random wallpaper matching the current time of day |
| 🍂 | Season | Random wallpaper matching the current season |
| ⚙️ | Settings | Open the settings panel |

Any of the first four can be switched off in the settings if you never use one.
The cog cannot — that would leave you with no way back in.

### Without the menu

```bash
lumen --time     # a random wallpaper for the time of day, no prompt
lumen --season   # a random wallpaper for the season, no prompt
lumen --thumbs   # rebuild the thumbnail cache, show nothing
lumen --help     # all of the above, from the horse's mouth
```

`--time` and `--season` are the menu's own entries with the menu taken out, so a
timer can call them. They take a lock while they work: a timer firing on top of a
run that is still painting would leave pywal and matugen writing over each
other's palette, so the older run is stopped first — along with the tools it
started, which outlive it.

<details>
<summary>Running <code>--time</code> on a schedule</summary>

<br>

```ini
# ~/.config/systemd/user/lumen-time.timer
[Unit]
Description=Follow the time of day

[Timer]
OnCalendar=*-*-* 07,18,22:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

```ini
# ~/.config/systemd/user/lumen-time.service
[Service]
Type=oneshot
ExecStart=%h/.local/bin/lumen --time
```

```bash
systemctl --user enable --now lumen-time.timer
```

Those three times are the boundaries `lumen` uses itself: day from 07:00, sunset
from 18:00, night from 22:00.

</details>

---

##  The picker

The menu and the thumbnail grid are drawn by Quickshell, out of `quickshell/lumen/`.

Out of the box they are a **pixel-for-pixel copy of the old rofi themes** — same
306×165.7 element, same 3px border, same rounded frames. What is new is the
movement rofi could not do: the window springs open, the selection slides from
one wallpaper to the next, the grid rearranges itself as you type, and thumbnails
fade in as they decode. Every one of those numbers is then yours to change.

Colors are not duplicated anywhere. The QML reads the very same
`~/.config/rofi/colors.rasi` and `~/.cache/wal/colors-rofi-dark.rasi` that the
rasi themes read, so the picker recolors itself along with the rest of the
desktop, for free, forever.

### Keys

The picker opens **in insert mode**, so you can type the name of a wallpaper the
moment the window is up — no mouse, no arrow keys. `hjkl` cannot double as
movement while you are typing (half of any wallpaper collection starts with an h,
a j, a k or an l), so the grid borrows vim's two modes instead.

| Insert mode | |
|---|---|
| type anything | Filter by name |
| <kbd>Enter</kbd> | Apply the selection |
| <kbd>Esc</kbd> | Leave insert mode, keeping the filter |

| Normal mode | |
|---|---|
| <kbd>h</kbd> <kbd>j</kbd> <kbd>k</kbd> <kbd>l</kbd> | Move through the grid |
| <kbd>g</kbd><kbd>g</kbd> / <kbd>G</kbd> | First / last wallpaper |
| <kbd>Ctrl</kbd>+<kbd>d</kbd> / <kbd>Ctrl</kbd>+<kbd>u</kbd> | Half a screen down / up |
| <kbd>i</kbd> or <kbd>/</kbd> | Back to the search field |
| <kbd>q</kbd> / <kbd>Esc</kbd> | Cancel |

The search field is pink while it holds the keyboard and turns to the selection
color once it does not, and its cursor becomes a vim block. That is the whole
mode indicator — no banner, no label.

Anything that is not a letter works from **either** mode, so you never have to
switch if you do not want to: arrows, <kbd>Enter</kbd>,
<kbd>Home</kbd>/<kbd>End</kbd>, <kbd>PageUp</kbd>/<kbd>PageDown</kbd>, and
`hjkl`/`d`/`u` held with <kbd>Ctrl</kbd> — rofi's own
<kbd>Ctrl</kbd>+<kbd>j</kbd>/<kbd>Ctrl</kbd>+<kbd>k</kbd>, extended. Clicking
outside cancels. The mode menu takes `hjkl`, arrows, <kbd>Enter</kbd> and
<kbd>q</kbd>; it has nothing to type into, so it needs no modes at all.

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

Nothing in there is a preview: the rows write straight into the settings, the
style recomputes, and the picker **beside it** redraws on the same frame. Fifty
three values, across five tabs, each short enough to see nearly whole:

| Tab | What is in it |
|---|---|
| **Menu** | Which of the four modes the mode menu offers |
| **Shape** | Corner radii (windows, header, thumbnails, search field), border widths, the mode menu's pill and ring |
| **Motion** | Animations on/off, speed, bounce, selection lift, and each duration on its own |
| **Layout** | Columns and spacing, thumbnail aspect / zoom / padding, wallpaper backdrop zoom / framing / blur / dim, window and header sizes, search field, mode menu |
| **Color** | Background opacity, blur behind the window, and the five palette colors |

| Panel | |
|---|---|
| <kbd>Tab</kbd> / <kbd>1</kbd>…<kbd>5</kbd> | Move between tabs |
| <kbd>j</kbd> / <kbd>k</kbd> | Move through the settings |
| <kbd>h</kbd> / <kbd>l</kbd> | Change the value (<kbd>Shift</kbd> for ten times the step) |
| <kbd>Enter</kbd> | Flip a switch, or pin a color |
| <kbd>r</kbd> | Reset the tab you are in |
| <kbd>Esc</kbd> / <kbd>q</kbd> | Close the panel |

Values land in `~/.config/lumen/settings.json` as you move a slider — there is no
save button, because there is nothing to save. The file is hand-editable and
watched, so writing to it from an editor restyles an open picker as you hit save.
Delete it, or use the last row of a tab, to go back to the defaults.

**Two knobs deserve a word.** *Thumbnails → Zoom* is how far into each thumbnail
the grid crops; rofi fitted the image in a 340px box and clipped it, and that is
the number. *Wallpaper backdrop* is the big image across the header, which rofi
drew at exactly the window's width, pinned to the top, with nothing else on offer:

- **Zoom** — above 1× it crops left and right rather than squeezing.
- **Framing** — which band of it the header shows, 0 being the top rofi used.
- **Blur** and **Dim** — the frosted-glass version, with the search field
  floating on it. Both are 0 by default, and at 0 the effect is skipped entirely
  rather than drawn as a no-op.

**Blur behind the window**, over in *Color*, is a different thing: the compositor
frosts what is under the cards — following their rounded corners, and the panel
as it slides out — while the rest of the screen stays sharp. It only shows through
once *Background opacity* is under 1, and it asks over `ext-background-effect`; a
compositor that does not speak it simply ignores the request. Hyprland 0.56 does.

**Colors** start on `auto`, which means "whatever pywal and matugen made of the
current wallpaper". Pressing <kbd>Enter</kbd> on one pins it to what is on screen
right now and opens hue, saturation and lightness under it; pressing
<kbd>Enter</kbd> again hands it back to the wallpaper.

</details>

**rofi is still there.** `lumen` falls back to the old themes whenever `qs` or the
Quickshell config is missing — or if `qs` fails to start — so nothing breaks on a
machine without Quickshell. To pin it by hand:

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
    ├── day/  sunset/  night/             # auto mode by time of day
    └── hiver/ printemps/ ete/ automne/   # auto mode by season
```

Sub-directories are searched too, so organise inside them however you like.
Thumbnails go into a hidden `.thumbnails/` folder in each directory, one `magick`
per core, capped at 512px — and are regenerated when the source changes, or when
a larger, older cache is found. `lumen --thumbs` builds them all ahead of time and
sweeps out the ones whose wallpaper is gone.

---

##  Dependencies

| Tool | Role |
|------|------|
| [`awww`](https://github.com/LGFae/swww) | Wallpaper daemon + transitions |
| [`matugen`](https://github.com/InioX/matugen) | Material You palette generation |
| [`pywal`](https://github.com/dylanaraps/pywal) | Classic palette generation |
| `imagemagick` | Thumbnail generation + GIF handling |
| [`quickshell`](https://quickshell.org) | The picker and the settings panel |
| `rofi` | The picker *(fallback)* |
| `jq` | Editing Obsidian JSON configs |
| `hyprland` | Cursor + IPC (`hyprctl`) |
| Nerd Font + Comfortaa | Menu glyphs and UI text |
| `spicetify` | Spotify theming *(optional)* |

> ⚠️ The [noctalia](https://github.com/noctalia-dev/noctalia) integration targets **Noctalia Shell v5** (`noctalia msg …`).
you can also use [wallreco](https://github.com/tungsten-w/wallreco) to set tags for all your wallpapers in a single command (see [usage](https://github.com/tungsten-w/wallreco#usage))

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

Bind it to a key in your Hyprland config — `W` (mod + W) is the recommended one:

```ini
bind = $mainMod, W, exec, /usr/local/bin/lumen
```

Make sure the binary is on your `PATH` as well. A keybind can call it by its full
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

##  Under the hood

<details>
<summary>A few things that were harder than they look <i>(click to unfold)</i></summary>

<br>

**The picker had to be measured, not ported.** rofi rounds its box model its own
way, so reading `wallpaper.rasi` and reproducing the numbers gave a window that
was only *nearly* right. The sizes here were taken off a screenshot of the real
thing instead, then compared back pixel by pixel: 1.4% of pixels differ, and all
of them are antialiasing on an edge. Same story for the thumbnails —
`element-icon { size: 340px }` fits the image inside a 340px box and lets the
element clip it, which zooms the visible crop in rather than fitting it.

**Everything downstream is derived.** The settings hold raw values; the style
computes the rest. Ask for four columns and the thumbnails resize themselves; make
the window narrower and the grid follows. Every derivation is clamped, so a
500px header in a 300px window shrinks instead of pushing the grid off the bottom
of the screen.

**Spotify was a race, not a bug.** `spicetify reload` fired two seconds after the
wallpaper changed and appeared to do nothing at all. It ran fine — it just ran
early: Noctalia writes Spotify's colors from its own template three seconds in.
`lumen` now waits for that file to actually be rewritten before reloading, rather
than for a duration it guessed.

**The thumbnail cache knows when it is stale.** Not only by timestamp: it reads
the PNG header of each thumbnail and regenerates any that were built at an older,
larger size.

</details>

---

##  My setup

Built and daily-driven on Hyprland.
Part of my dotfiles: [tungsten-w/.config](https://github.com/tungsten-w/.config)

---

##  Roadmap

- [ ] Config file for custom paths (drop the hard-coded `~/Pictures/Wallpapers`)
- [ ] Proper `install.sh` <--- (im working on it ( ˘͈ ᵕ ˘͈♡))
- [ ] Finish the wallpaper recognition script
- [x] Transitions
- [x] Settings panel (Ctrl+, / `lumen --settings`)
- [x] use rust instead of bash
- [x] Quickshell

---

##  License

Released under the [MIT License](LICENSE).
please feel free to fork and modify it to your liking.  
Art by : _.x1ansheng._   (check her instagram plz ૮꒰ ˶• ༝ •˶꒱ა ♡)
