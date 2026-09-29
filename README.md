<div align="center">

<img src="https://github.com/tungsten-w/lumen/blob/main/showcase/lumen%20design%20smol.png?raw=1" alt="Lumen" width="460">

#  ✦ Lumen ✦

**One wallpaper. One command. Your whole desktop shifts.**

Pick an image, and its colors ripple out to every themed corner of your Hyprland
desktop light or dark, in one keypress.

![version](https://img.shields.io/badge/version-v2.4-C36EFF?style=flat-square) ![Rust](https://img.shields.io/badge/built_with-Rust-2b86b5?style=flat-square&logo=rust&logoColor=white) ![Hyprland](https://img.shields.io/badge/Wayland-Hyprland-9ED53C?style=flat-square&logo=hyprland&logoColor=white) ![Quickshell](https://img.shields.io/badge/UI-Quickshell-FDBBFB?style=flat-square) ![License](https://img.shields.io/badge/license-MIT-65DDE1?style=flat-square)

</div>

---

##  ⚡ Quick start

On **Arch or CachyOS**, the script does all of it — dependencies, build,
wallpaper folders, picker config:

```bash
# 1 — clone and run it
git clone https://github.com/tungsten-w/lumen.git
cd lumen
./install/install.sh
```

```ini
# 2 — bind it in your Hyprland config  (SUPER+W is recommended)
```

That's it — hit <kbd>Super</kbd>+<kbd>W</kbd> and pick an image.

Any other distribution, or you would rather do it yourself: **[Installation](#installation)**.

---

##  What is this?

Changing a wallpaper usually means changing a wallpaper. Here it means changing
**the desktop**: `lumen` extracts the palette of the image you picked and pushes
it through every app that will listen, then flips the whole system to light or
dark to match.

```
   wallpaper  ─►  matugen / pywal or wallust / noctalia  ─►  palette extracted
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

<details>
<summary><b>Everything it does</b> &mdash; one image, the whole desktop, and a picker you can take apart &nbsp;<i>(click to unfold)</i></summary>

<br>

- **Whole-desktop theming** — one image repaints GTK, rofi, tmux, Ghostty,
  Neovim, Spotify, Obsidian, your shell and your lock screen.
- **Four palette sources** — [pywal](https://github.com/dylanaraps/pywal) or
  [Wallust](https://codeberg.org/explosion-mental/wallust) for classic sixteen
  colors, [matugen](https://github.com/InioX/matugen) for Material You, and
  [Noctalia](https://github.com/noctalia-dev/noctalia)'s own. Pick the source
  for each window in **Color ▸ Source**. Wallust runs when either window uses it;
  pywal remains the default for existing setups.
- **An animated picker** drawn with [Quickshell](https://quickshell.org): a
  thumbnail grid that filters as you type, slides its selection around, and fades
  each thumbnail in as it decodes.
- **Vim keys everywhere** — `hjkl`, `gg`/`G`, `Ctrl+d`/`Ctrl+u`, two modes, and a
  block cursor to tell you which one you are in.
- **A settings panel per window** — the mode menu has its own, the picker has
  its own, 74 knobs between them and **nothing shared**: corner radii, animation
  timings, column counts, blur, colors — every one redrawn **live** on the window
  next to it, none of them needing a restart.
- **Real blur** — frosted glass over the wallpaper in the header, and compositor
  blur behind the window itself.
- **Light / dark that means something** — the cursor swaps (Bibata Classic ↔
  Ice), Obsidian switches base theme, Noctalia flips mode, Spotify reloads its
  colors without restarting.
- **Smooth wallpaper transitions** through [`awww`](https://github.com/LGFae/swww).
- **Set and forget** — `lumen --time` and `lumen --season` pick for you, with no
  prompt at all, ready for a timer.
- **Written in Rust**, so the whole thing is done in about the time the
  transition takes.
- **Wallpaper recognition** — a script that reads what is *in* the image
  (animals, colors…). Half-built, and honest about it.

</details>

---

##  Usage

Launch `lumen` and pick a mode from the menu:

| | Option | What it does |
|---|--------|--------------|
| 🌙 | Dark | Browse `dark/` wallpapers |
| ☀️ | Light | Browse `light/` wallpapers |
| 🕘 | Time | Display a random wallpaper matching the current time of the day |
| 🍂 | Season | Display a random wallpaper matching the current season |
| 🔧 | Settings | Open the menu's own settings |

Any of the first four can be switched off in the settings if you never use one. (You can also add your own custom wallpaper sources.)

### Comands without the menu

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




##  The picker

The menu and the thumbnail grid are drawn by Quickshell, out of `quickshell/lumen/`.

Out of the box they are a **copy of the old rofi themes** — same
306×165.7 element, same 3px border, same rounded frames. What is new is the
movement rofi could not do: the window springs open, the selection slides from
one wallpaper to the next, the grid rearranges itself as you type, and thumbnails
fade in as they decode. Every one of those numbers is then yours to change.

Colors are not duplicated anywhere. The QML reads generated palette files:
`~/.cache/wal/colors-rofi-dark.rasi` for pywal,
`~/.cache/wallust/colors-rofi-dark.rasi` for Wallust,
`~/.config/rofi/colors.rasi` for matugen, and
`~/.config/rofi/noctalia.rasi` for Noctalia. **Color ▸ Source** selects one.

<details>
<summary><b>&nbsp;⌨&nbsp; Keys</b> &mdash; two vim modes, and everything that works from both &nbsp;<i>(click to unfold)</i></summary>

<br>

The picker opens **in insert mode**, so you can type the name of a wallpaper the
moment the window is up — no mouse, no arrow keys. `h-j-k-l` cannot double as
movement while you are typing (half of any wallpaper collection starts with an h,
a j, a k or an l), so the grid borrows vim's two modes instead.


Anything that is not a letter works from **either** mode, so you never have to
switch if you do not want to: arrows, <kbd>Enter</kbd>,
<kbd>Home</kbd>/<kbd>End</kbd>, <kbd>PageUp</kbd>/<kbd>PageDown</kbd>, and
`hjkl`/`d`/`u` held with <kbd>Ctrl</kbd> — rofi's own
<kbd>Ctrl</kbd>+<kbd>j</kbd>/<kbd>Ctrl</kbd>+<kbd>k</kbd>, extended. Clicking
outside cancels. The mode menu takes `hjkl`, arrows, <kbd>Enter</kbd> and
<kbd>q</kbd>; it has nothing to type into, so it needs no modes at all.

</details>

<details>
<summary><b>&nbsp;⚙&nbsp; Settings</b> &mdash; <kbd>Ctrl</kbd>+<kbd>,</kbd>, or type <code>settings</code> in the picker &nbsp;<i>(click to unfold)</i></summary>

<br>

⚠️ The mode menu and the picker each have their own panel — a panel only lists what
its own window draws. Three ways in, whichever is closest to hand:

```bash
lumen --settings            # the picker's, with the grid beside it as a preview
```

- <kbd>Ctrl</kbd>+<kbd>,</kbd> from inside the picker or the mode menu, each
  opening its own;
- the **cog**, the fifth entry of the mode menu — the menu's panel, straight on
  its **Entries** tab;
- or type **`settings` into the picker's search field**. The grid tells you it is
  a command as you type it, and the field clears itself once the panel is out.

Nothing in there is a preview: the rows write straight into the settings, the
style recomputes, and the window **beside it** redraws on the same frame. There
is no thumbnail zoom in the menu's panel, and no menu entries in the picker's:

| Tab | The menu's | The picker's |
|---|---|---|
| **Presets** | Save the whole configuration under a name, put any of them back, or write your changes into one you already have | The same |

Six tabs, and <kbd>/</kbd> if you would rather not remember which one a setting is in.
| **Entries** | Which of the four modes the menu offers, and folders of your own | — |
| **Shape** | Window corner and border, the selected entry's pill and ring | Corners of the window, header, thumbnails and search field; window and thumbnail borders |
| **Tags** | — | Install [wallreco](https://github.com/tungsten-w/wallreco), or run it to tag new wallpapers and recompute the old ones |
| **Motion** | Animations on/off, speed, bounce, selection lift, and each duration on its own | The same, plus the grid's thumbnail stagger |
| **Layout** | Menu size, columns, icon size, wallpaper backdrop | Grid and spacing, thumbnails, backdrop, window and header sizes, search field |
| **Color** | Which palette to follow, background opacity, blur behind the window, and four palette colors | The same, plus the thumbnail border |

**<kbd>/</kbd> searches every tab at once.** The tabs are how the panel is
arranged, not how it is remembered: you know there is a blur *somewhere* without
knowing it is filed under Color. Typing filters all six at once and lists what is
left under the tab it came from, with its heading carried along — so Shape's two
`Window` rows come back as *Corners ▸ Window* and *Borders ▸ Window* rather than
as the same word twice. A tab's own name matches too, which makes the search a
second way to open one, and presets match by name.

It borrows the picker's two modes rather than stealing the keyboard: <kbd>/</kbd>
(or <kbd>Ctrl</kbd>+<kbd>F</kbd>) starts typing, <kbd>Enter</kbd> or
<kbd>Esc</kbd> steps out **keeping** what was found, so <kbd>j</kbd>/<kbd>k</kbd>
walk the results and <kbd>h</kbd>/<kbd>l</kbd> change them in place. A second
<kbd>Esc</kbd> drops the search and puts the tabs back; only then does one close
the panel. Picking a tab leaves the results too.

The bar draws **an icon per tab** rather than a name: six names fought over the
width of the panel and had to be shrunk to fit, six glyphs do not. Hovering one
names it, and so does moving to it with the keyboard — the name appears under the
bar for a moment, so <kbd>Tab</kbd> never drops you somewhere you cannot name.
**Presets** is first, and is where the panel opens: it is the one tab that
changes everything at once, and the one nobody finds at the far end of a bar.

Thirty three values for the menu, forty one for the picker, six tabs each — two
of which hold no values at all, only the jobs and the presets below. Each tab is short
enough to see nearly whole, and on the ones that are not, a bar down the right
edge shows how much is still under the fold, and drags.

**Nothing is shared between the two panels.** A knob both windows draw — the
window's corner and border, every animation, the whole palette, the backdrop's
framing — is stored twice, the menu's copy under the same name with a `menu`
prefix: `shape.border` is the picker's outline and `shape.menuBorder` the menu's.
So the menu can snap open while the picker glides, follow matugen while the
picker follows pywal, and be square while the picker is round. A settings file
written before the split is carried over rather than half reset: a `menu` half
the file has never heard of starts as a copy of the knob it used to be, so
upgrading leaves both windows looking exactly as they did.

**Folders of your own** are extra entries in the mode menu, added under
**Entries** in the menu's own panel. Point one at any directory — a series, a
game, a photographer — give it a name and a Nerd Font glyph, and it sits beside
Dark and Light with the same switch, so a collection you only want in December
can be put away without being typed in again next year. The thumbnail grid, the
cache and the tag search all work there unchanged.

*Add* puts one in the menu and drops you **straight into its name**; <kbd>Enter</kbd>
keeps what you typed and moves to the next line, <kbd>Esc</kbd> leaves it. Each
line says what it wants — *what it is called in the menu*, *where your images are*
— because a row that only says `empty` tells you nothing about how to stop it
being so.

**The path line shows you what is really there**, the way a file manager does.
Start typing and the directories that exist under it are listed and filtered as
you go; <kbd>Tab</kbd> goes into the one under the cursor, arrows look around.
Only folders are offered — the images inside would bury the one thing you are
looking for — and hidden ones stay hidden until you type a leading dot. The panel
has no file dialog and no clipboard, so a path is typed; typed blind it gets a
typo in it, and a typo only shows up much later as a menu entry that opens on
nothing.

A folder with no path stays out of the menu whatever its switch says, and the row
says so rather than looking finished.

Unlike `dark/` and `light/`, such a folder is neither: the same directory can
hold both. So the picker asks once you have chosen an image, and that answer is
what flips the desktop.

The menu answers with the **path itself** rather than with a name, which is why
`lumen` needs to know nothing about your categories — it opens the grid on
whatever it was handed. Folders are also left out of presets on purpose: a path
on your disk is not a look, and a preset carrying one would rewrite a stranger's
menu with folders they do not have.

**Presets** are whole configurations you can swap between. Each one is a single
JSON file in `~/.config/lumen/presets`, shaped exactly like `settings.json`
itself — so a preset is something you can read, hand-edit, keep in a dotfiles
repo, or send to someone who liked your setup. *Save this configuration* asks for
a name and writes all seventy four values — both windows' halves; *Apply* puts
them back.

**A dot and a coloured name mark the preset you are on.** It is compared, not
remembered: the row lights up whenever your settings already hold everything that
file does — applying it would change nothing — and goes out the moment you move a
slider it covers. More than one row can be lit at once, and that is honest: a
colours-only preset and a whole one can both be what you have.

`Default` is not a file: it is the original rofi measurements, which is what
makes it the one preset that can never go missing.

Applying only writes back the groups a file actually holds, so a preset carrying
nothing but `colors` restyles the palette and leaves your layout alone:

```jsonc
// ~/.config/lumen/presets/midnight.json — a palette, and nothing else
{
  "colors": { "palette": "noctalia", "opacity": 0.85, "blur": true }
}
```

Keys and groups that are not ours are skipped rather than trusted: these files
get hand-edited and copied between machines, and one typo should cost you that
line rather than the whole preset.

*Update*, on a preset's own row, writes what is on screen into that preset — so a
look you keep tuning stays one preset instead of becoming `rounded`, `rounded 2`
and `rounded final`. It is the exact inverse of *Apply*: it puts back **only the
keys that file already holds**, so `midnight` above stays three colour values and
simply picks up the palette you are looking at now, rather than swelling into a
whole configuration the first time you touch it. Unlike the cross it does not ask
twice — it is the button you reach for after every nudge of a slider, and one you
have to confirm is one you stop using. <kbd>u</kbd> on the row does the same, and
`Default`, being no file, has neither button.

*Copy* puts that same JSON on the clipboard — `Default` included, which has no
file but is still worth handing to someone as a starting point — and *Paste a
preset from the clipboard*, underneath *Save this configuration*, reads one back
and asks for a name the same way Save does. Sharing a look no longer needs the
file at `~/.config/lumen/presets` at all; a message with the JSON in it does the
same job. <kbd>c</kbd> on a preset's row is Copy from the keyboard.

**Tags** is where [wallreco](https://github.com/tungsten-w/wallreco) lives. It
writes its tags into the filenames — `sunset.png` becomes
`sunset-#orange-#warm-#sky.png` — which is exactly what the picker's search field
reads, so a tagged collection filters by keyword. The tab finds the binary or
offers to build it, then gives you two buttons: one that tags whatever has no
tags yet, and one that recomputes the lot. The second renames every wallpaper in
`~/Pictures/Wallpapers`, so it asks twice; `wallreco --undo` puts the old names
back.

| Panel | |
|---|---|
| <kbd>/</kbd> or <kbd>Ctrl</kbd>+<kbd>F</kbd> | Search every tab at once |
| <kbd>Tab</kbd> / <kbd>1</kbd>…<kbd>6</kbd> | Move between tabs |
| <kbd>u</kbd> | Write your changes into the preset under the cursor |
| <kbd>c</kbd> | Copy the preset under the cursor to the clipboard |
| <kbd>x</kbd> | Delete the preset under the cursor (twice, it asks) |
| <kbd>j</kbd> / <kbd>k</kbd> | Move through the settings |
| <kbd>h</kbd> / <kbd>l</kbd> | Change the value (<kbd>Shift</kbd> for ten times the step) |
| <kbd>Enter</kbd> | Flip a switch, or pin a color |
| <kbd>r</kbd> | Reset the tab you are in — only what it shows, never the other panel's half |
| <kbd>?</kbd> | Show this table, on top of the panel itself |
| <kbd>Esc</kbd> / <kbd>q</kbd> | Drop the search, then close the panel |

The search field itself is always on screen now rather than folded away until
asked for — a click in it, or <kbd>/</kbd>, starts typing — and <kbd>?</kbd>
opens the same table above as an overlay, for whichever key here you forget.

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

**A GIF plays there, on by default.** The strip behind the search field, and the
card behind the mode menu, both draw whatever the current wallpaper actually is —
and a plain `Image` in Quickshell can only ever show a still frame, whatever
format it is given. So the moment `lumen` finds the one on screen is a GIF, this
is what shows it moving instead, in the same box, at the same zoom and framing
as a photograph would sit in.

**The grid does the same, for the one thumbnail you have selected.** Every other
cell stays exactly what it always was — the cached, static crop `magick` took of
frame zero — so a folder of fifty GIFs is fifty cheap PNGs sitting still and one
that moves once you land on it. Walking the grid starts and stops a GIF as you go
past it; nothing plays that is not the one under the cursor.

**Animate GIFs**, right under Dim, turns both of the above off at once — back to
the still first frame everything else already drew, for whoever finds a wallpaper
moving behind their search field more distracting than charming, or would rather
not spend a decode on it.

**Blur behind the window**, over in *Color*, is a different thing: the compositor
frosts what is under the cards — following their rounded corners, and the panel
as it slides out — while the rest of the screen stays sharp. It only shows through
once *Background opacity* is under 1, and it asks over `ext-background-effect`; a
compositor that does not speak it simply ignores the request. Hyprland 0.56 does.

**Colors** start on `auto`, which means "whatever the palette made of the current
wallpaper". **Source** picks which palette that is — pywal, Wallust, matugen or Noctalia —
and the five colors under it move together when you change it. Pressing
<kbd>Enter</kbd> on one pins it to what is on screen right now and opens hue,
saturation and lightness under it; pressing <kbd>Enter</kbd> again hands it back
to the wallpaper.

</details>

**Quickshell is the only front-end.** `lumen` looks for its config at
`~/.config/quickshell/lumen/shell.qml`, or wherever the install script's own
checkout put it; point it somewhere else by hand with:

```bash
LUMEN_QS_CONFIG=/path/shell.qml  # a Quickshell config somewhere else
```

Missing `qs`, or a config it cannot find, is a hard stop with a message on
stderr rather than a silent do-nothing.

---

##  🎛️ Customization reference

<details>
<summary><b>Every knob, tab by tab</b> — what each one holds, and which window actually draws it &nbsp;<i>(click to unfold)</i></summary>

<br>

[The picker](#the-picker) above covers how the panel itself behaves — the
search, the tabs, the keyboard, the presets. This is what is actually sitting
*in* each tab, so a look at one table says whether a knob exists at all before
you go hunting for it.

### Presets — the same tab in both panels

| | |
|---|---|
| **Default** | not a file — the rofi measurements, the one preset that can never go missing |
| **Apply** | writes a saved preset's values back |
| **Update** (<kbd>u</kbd>) | writes what is on screen into a preset you already have, keeping only the keys it already held |
| **Copy** (<kbd>c</kbd>) | puts that preset's JSON on the clipboard — `Default` included |
| **Delete** (<kbd>x</kbd>) | removes a preset — asks twice |
| **Save this configuration** | names and saves everything on screen |
| **A preset from the clipboard** | reads `wl-paste`, and asks for a name to save it under |

### Entries — menu only

| | |
|---|---|
| Dark / Light / Time of day / Season | switches any of the four off the mode menu |
| Folders of your own | name, an autocompleted path, a Nerd Font icon, and an on/off switch — as many as you like |

### Shape

| Setting | Menu | Picker |
|---|:---:|:---:|
| Window corner radius | ✅ | ✅ |
| Window border | ✅ | ✅ |
| Header corner radius | — | ✅ |
| Thumbnail corner radius | — | ✅ |
| Search field corner radius | — | ✅ |
| Thumbnail border | — | ✅ |
| Selected entry — pill inset | ✅ | — |
| Selected entry — ring width | ✅ | — |
| Selected entry — ring inset | ✅ | — |

### Tags — picker only

| | |
|---|---|
| Install [wallreco](https://github.com/tungsten-w/wallreco) | builds it if it is missing |
| Tag what has no tags yet | runs it |
| Recompute every tag | asks twice — renames every wallpaper in the folder |

### Motion

| Setting | Menu | Picker |
|---|:---:|:---:|
| Animations on/off | ✅ | ✅ |
| Speed | ✅ | ✅ |
| Bounce | ✅ | ✅ |
| Selection lift | ✅ | ✅ |
| Opening / closing duration | ✅ | ✅ |
| Selection move duration | ✅ | ✅ |
| Fades and hover duration | ✅ | ✅ |
| Scroll duration | ✅ | ✅ |
| Thumbnail stagger | — | ✅ |

### Layout

| Setting | Menu | Picker |
|---|:---:|:---:|
| Window width / height | ✅ | ✅ |
| Columns | ✅ *(up to 4)* | ✅ *(up to 8)* |
| Icon size | ✅ | — |
| Column / row spacing | — | ✅ |
| **Shuffle order on open** | — | ✅ *(a fresh random order each time the grid opens — still only whichever folder it opened)* |
| Thumbnail aspect / zoom / padding | — | ✅ |
| Window padding, header height | — | ✅ |
| Search field width / height / text size | — | ✅ |
| Wallpaper backdrop zoom / framing / blur / dim | ✅ | ✅ |
| Animate GIFs | ✅ | ✅ |

### Color

| Setting | Menu | Picker |
|---|:---:|:---:|
| Palette source (pywal / Wallust / matugen / noctalia) | ✅ | ✅ |
| Background opacity | ✅ | ✅ |
| Blur behind the window | ✅ | ✅ |
| Background / Text / Border / Selection color | ✅ | ✅ |
| Thumbnail border color | — | ✅ |

Any of the five colors can be pinned: <kbd>Enter</kbd> on one freezes it at
whatever the palette currently gives it and opens hue, saturation and
lightness underneath; <kbd>Enter</kbd> again hands it back to `auto`.

</details>

---

##  Expected wallpaper layout

<details>
<summary><b>The folders it looks in</b>, and how thumbnails are cached &nbsp;<i>(click to unfold)</i></summary>

<br>

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

</details>

---

##  Dependencies

<details>
<summary><b>The tools it drives</b>, and what each one is for &nbsp;<i>(click to unfold)</i></summary>

<br>

| Tool | Role |
|------|------|
| [`awww`](https://github.com/LGFae/swww) | Wallpaper daemon + transitions |
| [`matugen`](https://github.com/InioX/matugen) | Material You palette generation |
| [`pywal`](https://github.com/dylanaraps/pywal) | Classic palette generation |
| [Wallust](https://codeberg.org/explosion-mental/wallust) | Alternative classic palette generation *(optional)* |
| `imagemagick` | Thumbnail generation + GIF handling |
| [`quickshell`](https://quickshell.org) | The picker and the settings panel |
| `jq` | Editing Obsidian JSON configs |
| `wl-clipboard` | Copying and pasting presets |
| `hyprland` | Cursor + IPC (`hyprctl`) |
| Nerd Font + Comfortaa | Menu glyphs and UI text |
| `spicetify` | Spotify theming *(optional)* |

> ⚠️ The [noctalia](https://github.com/noctalia-dev/noctalia) integration targets **Noctalia Shell v5** (`noctalia msg …`).  
⚠️  You can also use [wallreco](https://github.com/tungsten-w/wallreco) to set tags for all your wallpapers in a single command (see [usage](https://github.com/tungsten-w/wallreco#usage))

</details>

---

##  Installation

### The script — Arch and CachyOS

```bash
git clone https://github.com/tungsten-w/lumen.git
cd lumen
./install/install.sh
```

Everything it asks can be answered with Enter:

1. **Install `gum`, and an AUR helper** — only if you have neither. gum draws
   the prompts; without it they are plain text and the run carries on.
2. **Which optional pieces** you want — Wallust, Noctalia theming, Spotify recolouring.
   Space to pick, Enter to move on.
3. **Which version** to build — the latest release, or `main`.
4. **Where you keep your wallpapers.** Anywhere is fine: it makes `dark/`,
   `light/` and `season-time/` there. If that is not `~/Pictures/Wallpapers`, it
   points that path at your folder, since it is the only one the binary knows.
5. **Whether to move anything in the way** — only if there is. A folder with
   files in it is never deleted: it offers, and refuses to do it unattended.

Then it installs the dependencies, builds with `cargo install`, and links
`quickshell/lumen` out of the checkout.

```bash
./install/install.sh --dry-run    # print every step, change nothing
```

**Start with that.** It walks the whole script and prints every command it would
run, without touching a file.

| Flag | |
|---|---|
| `--dry-run` | Print every step. Change nothing. |
| `--yes` | Take every default, ask nothing. |
| `--ref REF` | Build this tag, branch or commit. |
| `--src DIR` | Keep the checkout somewhere else. |

Run it again to update — every step notices what is already done:

```bash
git -C ~/.local/share/lumen pull && ~/.local/share/lumen/install/install.sh
```

Every step it takes, every path it touches and how to undo each one is written
out in **[install/README.md](install/README.md)**.

### Wallust as a color source

Install `wallust`. The installer links the two templates from
[`wallust/templates/`](wallust/templates) into `~/.config/wallust/templates/`.
For a manual install, copy them there. If you have no Wallust config yet, the
installer creates one from [`wallust/wallust.toml`](wallust/wallust.toml).
If you already have one, add its two `[templates]` entries to your existing
section. These entries generate the Rofi palette for Lumen's picker
and a JSON palette for Brave without touching pywal's cache.

In both the menu and picker settings panels, choose **Color → Source → wallust**.
Lumen then runs `wallust run` with a dark or light palette when you change the
wallpaper. It skips `wal` when neither window uses pywal. If the two windows
choose different classic sources, Lumen runs both. Other applications can use
the same Wallust run by adding templates to your Wallust config.

An executable path in `LUMEN_WALLUST_HOOK` runs after a successful Wallust
update. Lumen passes `LUMEN_DARK_MODE=dark` or `light` and the image path in
`LUMEN_WALLPAPER`, so a desktop setup can refresh its own themes.
Set `LUMEN_SKIP_NOCTALIA=1` when that hook handles a different shell and you
do not want Lumen to launch or message upstream Noctalia. Spotify reload still
runs when Spotify is open.

### By hand — any distribution

<details>
<summary><b>Binary or source</b>, the keybind, and linking the picker's config &nbsp;<i>(click to unfold)</i></summary>

<br>

You will need these on your `PATH` first: `awww`, `matugen`, `pywal` or `wallust`,
`imagemagick`, `quickshell`, `jq`, plus a Nerd Font and Comfortaa. The
[dependency table](#dependencies) above says what each is for.

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

</details>

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

**And then it asked twice.** Live reload needs a connection to Spotify's DevTools.
The first `spicetify reload` after Spotify starts does not reload anything: it
turns DevTools on, restarts Spotify once, and says on stdout to run the command
again. Both passes exit 0 and neither takes a flag, so the exit code cannot tell
them apart — which meant the first wallpaper of every session left Spotify on the
old palette, looking exactly like the command being broken. `lumen` now reads
what the run actually did and asks a second time when it has to. Exactly once: a
run that finds no connection restarts Spotify to make one, so retrying in a loop
would be a loop of restarts.

**The thumbnail cache knows when it is stale.** Not only by timestamp: it reads
the PNG header of each thumbnail and regenerates any that were built at an older,
larger size.

**A playing GIF is not the same wallpaper twice.** The `/tmp` copy every window
already read is always a flat raster — named `.png` no matter the source, because
a plain `Image` is all that ever reads it — so it was never going to be what plays.
What does is the real file, extension and all, resolved by `lumen` itself from the
symlink it already keeps in `Pictures/Wallpapers`, and handed to Quickshell as an
environment variable rather than guessed from a fixed path. And Qt has its own
opinion here: binding `AnimatedImage`'s `sourceSize` to the size it is actually
drawn at — the same trick the still image uses to avoid decoding a 4K frame for a
340px box — quietly decodes the movie a second time once layout settles, and the
second decode comes back paused. Measured, not guessed, after a real GIF sat on
screen not moving: the fix is to tell it to play again every time it says it is
ready, which is cheap and survives however many times that happens.

</details>

---

##  My setup

Built and daily-driven on Hyprland.
Part of my dotfiles: [tungsten-w/.config](https://github.com/tungsten-w/.config)

---

##  Roadmap

<details>
<summary><b>Done, and still to do</b> &nbsp;<i>(click to unfold)</i></summary>

<br>

- [ ] Config file for custom paths (drop the hard-coded `~/Pictures/Wallpapers`)
- [ ] Release it on the AUR
- [ ] make a video about the project 
- [ ] create your own wallpaper folder
- [x] Finish the wallpaper recognition script (see [wallreco](https://github.com/tungsten-w/wallreco))
- [x] Settings panel (Ctrl+/lumen --settings/settings in the search bar)
- [x] use rust instead of bash
- [x] Quickshell
- [x] Proper [`install.sh`](install/README.md) (Arch and CachyOS)


</details>

---

##  License

Released under the [MIT License](LICENSE).
please feel free to fork and modify it to your liking.  
Art by : _.x1ansheng._   (check her instagram plz ૮꒰ ˶• ༝ •˶꒱ა ♡)
