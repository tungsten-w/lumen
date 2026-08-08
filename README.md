<div align="center">

#  ✦ Lumen ✦ v2.2

<br>
    
</div>

One wallpaper. One command. Your whole desktop shifts.
A rofi-driven wallpaper picker that paints your entire Hyprland desktop —> light or dark from a single image.
This is built for Wayland and more specifically for hyprland.

![Wayland](https://img.shields.io/badge/Display-Wayland-green)

---

##  What is this?

`lumen` picks a wallpaper and **propagates its palette across your entire desktop** in one shot.
Choose an image through a rofi menu or let `lumen` pick one automatically based on the
**season and/or time of day** and watch pywal, matugen, your cursor, Noctalia Shell, Obsidian
and more all switch to match, light or dark.

No more editing five config files by hand every time you change your background.

---
![image alt](https://github.com/tungsten-w/lumen/blob/main/showcase/showcase.png)
---

##  Features

-  **Wallpaper switching** with smooth transitions via [`awww`](https://github.com/LGFae/swww)
-  **rofi picker** with live thumbnail previews (auto-generated with ImageMagick)
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
| `rofi` | Wallpaper picker menu |
| `jq` | Editing Obsidian JSON configs |
| `hyprland` | Cursor + IPC (`hyprctl`) |
| Papirus icon theme | rofi thumbnail icons |
| `spicetify` | Spotify theming *(optional)* |

> ⚠️ Requires **Noctalia Shell v5** for the current theming IPC. (v4 support is commented out in the script if you are using an older version.)

---

##  Installation

```bash
git clone https://github.com/tungsten-w/lumen.git
cd lumen
chmod +x lumen.sh
```

Bind it to a key in your Hyprland config, e.g.:
the recommended keybind is `W` (mod + W)
```ini
bind = $mainMod, W, exec, ~/path/to/lumen.sh
```

---

##  Expected wallpaper layout

`lumen` expects your wallpapers organised like this under `~/Pictures/Wallpapers/`:

```
~/Pictures/Wallpapers/
├── dark/                 # dark-mode wallpapers (rofi picker)
├── light/                # light-mode wallpapers (rofi picker)
└── season-time/
    ├── day/  sunset/  night/     # auto mode by time of day
    └── hiver/ printemps/ ete/ automne/   # auto mode by season
```

Thumbnails are generated automatically into a hidden `.thumbnails/` folder in each directory.

---

##  Usage

Launch `lumen` and pick a mode from the rofi menu:

| Option | What it does |
|--------|--------------|
|  Dark | Browse `dark/` wallpapers with thumbnails |
|  Light | Browse `light/` wallpapers with thumbnails |
|  Time | Random wallpaper matching the current time of day |
|  Season | Random wallpaper matching the current season |

---

##  My setup

Built and daily-driven on Hyprland.
Part of my dotfiles: [tungsten-w/.config](https://github.com/tungsten-w/.config)

---

##  Roadmap

- [ ] Config file for custom paths (drop the hard-coded `~/Pictures/Wallpapers`)
- [ ] Proper `install.sh` <--- (im working on it ( ˘͈ ᵕ ˘͈♡))
- [ ] Transitions

---
##  License

Released under the [MIT License](LICENSE).
please feel free to fork and modify it to your liking.
