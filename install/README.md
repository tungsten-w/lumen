<div align="center">

```
 /\_/\
( o.o )
 > ^ <
```

**What the installer does, step by step, and every path it touches.**

</div>

---

## In one line

```bash
git clone https://github.com/tungsten-w/lumen.git && ./lumen/install/install.sh
```

Arch and CachyOS only. It installs the dependencies, keeps a checkout it can
update from, builds the binary with cargo, links the Quickshell config, and
makes the wallpaper folders wherever you want them.

Run it again to update — every step notices what is already done.

---

## Why there is an installer at all

`cargo install` gets you the binary and nothing else, and the binary is only
half of lumen. The picker and the settings panel are **QML files** that
Quickshell reads off disk — lumen has no other front-end to fall back on, so
without them there is nothing to draw with at all. They are looked for at
fixed paths compiled into the binary:

```rust
// quickshell_config(), main.rs
$LUMEN_QS_CONFIG
~/.config/quickshell/lumen/shell.qml
~/.config/lumen/quickshell/lumen/shell.qml
```

So something has to put files in the right places, and that something is this
script. It is why it keeps a checkout instead of throwing one away.

---

## Usage

```
./install/install.sh [options]
```

| Flag | |
|---|---|
| `--dry-run` | Print every step. Change nothing, anywhere. |
| `--yes`, `-y` | Take every default and ask nothing. For unattended runs. |
| `--ref REF` | Build this tag, branch or commit instead of asking which. |
| `--src DIR` | Keep the checkout here. Default `~/.local/share/lumen`. |
| `-h`, `--help` | The same table, shorter. |

**Start with `--dry-run`.** It walks the whole script and prints every command
it would run, prefixed with `$`, without touching a file. It is the honest way
to see what you are about to agree to.

---

## The steps

### 1 — Checking this machine

Everything that could stop the run is checked *before* the run changes
anything, so a machine that cannot be installed onto is left exactly as it was
rather than half done.

- `/etc/arch-release` and `pacman` — this script speaks one packaging language.
- **Not root.** It builds into your `~/.cargo` and writes your `~/.config`;
  running it as root would leave both owned by root. It asks for `sudo` only
  where packages are installed.
- `sudo` and `curl` are present.
- Hyprland is *warned* about rather than required: lumen installs fine without
  it, but the cursor swap and the IPC calls need it.

### 2 — gum

`gum` draws the prompts. It is offered rather than required, because the script
has to be able to install gum and therefore cannot need gum in order to speak:
every prompt has a plain-text twin, and the cat is drawn either way.

### 3 — An AUR helper

`paru` or `yay`, whichever you have. If neither, it offers to build `paru-bin`
from the AUR the manual way. Decline and the run carries on — anything that is
not in your repositories is simply reported and skipped.

### 4 — Dependencies

Ten required, three optional (`wallust`, `noctalia`, `spicetify`) offered through a
`gum choose` you can leave empty.

Two things are worth knowing here.

**Package names are not hard-coded.** Each dependency carries a list of names it
might go under, and the first one that exists wins — `pacman` first, the AUR
after. This is not defensiveness, it is necessary: CachyOS ships `awww`,
`matugen` and `quickshell` in its own repositories, while plain Arch has them
only as `awww-git`, `matugen-bin` and `quickshell-git`, and `noctalia-shell`
becomes `noctalia-git`. Encoding either distribution's answer would break the
other.

**Presence is judged on what lumen itself would find**, not on what pacman
thinks it installed:

| Kind | How it is checked | Why |
|---|---|---|
| Programs | `command -v` | `spicetify` lives in `~/.spicetify` and belongs to no package |
| Fonts | `fc-list` | A font dropped into `~/.local/share/fonts` by hand counts |

<details>
<summary>The table, in full</summary>

<br>

| | Package candidates | Looked for | For |
|---|---|---|---|
| git | `git` | `git` | Cloning this checkout, and updating it |
| rust | `rust` `rustup` | `cargo` | Building lumen |
| awww | `awww` `awww-git` | `awww` | Setting the wallpaper, and the transition |
| matugen | `matugen` `matugen-bin` | `matugen` | Material You palettes |
| pywal | `python-pywal16` `python-pywal` | `wal` | The classic sixteen colours |
| *wallust* | `wallust` `wallust-bin` | `wallust` | Alternative classic colors |
| imagemagick | `imagemagick` | `magick` | Thumbnails, and GIF handling |
| quickshell | `quickshell` `quickshell-git` | `qs` | The picker and the settings panel |
| jq | `jq` | `jq` | Editing Obsidian's JSON |
| Nerd Font | `ttf-jetbrains-mono-nerd` | fontconfig | The menu glyphs |
| Comfortaa | `ttf-comfortaa` | fontconfig | The interface text |
| *noctalia* | `noctalia-shell` `noctalia-git` | `noctalia` | Theming the Noctalia shell |
| *spicetify* | `spicetify-cli` | `spicetify` | Recolouring Spotify |

`awww` is the renamed successor of `swww` — same author, now at
[codeberg.org/LGFae/awww](https://codeberg.org/LGFae/awww).

</details>

### 5 — Source

**If you ran the script from a clone, that clone is used** and its checkout is
left exactly where you put it. This is what makes the script safe to run inside
your own fork or dotfiles repository: it will not move you off your branch.

Otherwise it clones to `~/.local/share/lumen` (or `--src`) and asks which
version to build:

- **Latest release** — the newest `v*.*.*` tag, resolved with `git ls-remote`
  rather than the GitHub API, so there is no token and no rate limit.
- **main** — the newest code, work in progress included.

A branch is checked out tracking its remote; a tag is checked out detached,
because a tag is a fixed point with no upstream to pull from.

### 6 — Building

```bash
cargo install --path "$SRC/lumen" --locked --force
```

`--locked` builds against the `Cargo.lock` in the repository rather than
whatever resolves today, so what you get is what was tested. The binary lands in
`~/.cargo/bin`, which needs no root — the script checks that it is on your
`PATH` at the end and tells you if it is not.

### 7 — Wallpapers

You are asked where you keep them, and anywhere is a valid answer. The folders
are made there:

```
<your folder>/
├── dark/
├── light/
└── season-time/
    ├── day/  sunset/  night/
    └── hiver/  printemps/  ete/  automne/
```

**Then it makes `~/Pictures/Wallpapers` point at your folder**, because that is
the one path the binary knows — eight places in `main.rs` and one in
`Wallreco.qml`. Until the config file on the roadmap exists, a link is what lets
you keep the collection where you like.

What happens to a `~/Pictures/Wallpapers` that is already there:

| What it is | What happens |
|---|---|
| Not there | The link is made |
| Already a link to your folder | Nothing |
| A link somewhere else | Asks before repointing it |
| An **empty** folder | Removed, then linked |
| A folder **with things in it** | Asks to move them into your folder first, then links |

**Nothing that has anything in it is ever deleted.** Under `--yes` the last row
refuses outright rather than move your wallpapers unattended, and says so. The
move carries hidden folders across too, so an existing `.thumbnails/` cache
comes with it instead of being orphaned.

### 8 — Config

One symlink out of the checkout:

| Link | Target |
|---|---|
| `~/.config/quickshell/lumen` | `$SRC/quickshell/lumen` |

If Wallust is installed, the installer also links Lumen's two Wallust templates
into `~/.config/wallust/templates/` and creates `~/.cache/wallust/`. It creates
`~/.config/wallust/wallust.toml` only when no config exists. If you already have
one, it leaves the file alone and prints the two entries to add from
`$SRC/wallust/wallust.toml`.

A path that is already the right link is left alone. A path that is a link
somewhere else asks before being repointed. **A real file or folder you wrote is
never overwritten** — it is moved to `<name>.bak` and only with your say-so.

### 9 — Done

The `PATH` check, the Hyprland keybind to copy, the three commands worth
knowing, and how to update. The keybind is *printed*, not appended:
`hyprland.conf` is yours and no installer should be editing it behind you.

---

## Everything it touches

Nothing outside this list is written to, and every line of it is skipped when it
is already right.

| Path | What | Removable |
|---|---|---|
| `~/.local/share/lumen` | The checkout, unless `--src` | `rm -rf` |
| `~/.cargo/bin/lumen` | The binary | `cargo uninstall lumen` |
| `~/.config/quickshell/lumen` | Symlink | `rm` |
| `~/.config/wallust/templates/lumen-*` | Symlinks, if Wallust is present | `rm` |
| `~/.config/wallust/wallust.toml` | Created only if absent | Keep or remove as you prefer |
| `~/.cache/wallust` | Generated palette cache | `rm -rf` |
| `~/Pictures/Wallpapers` | Folder, or a symlink to yours | `rm` the link |
| *your wallpaper folder* | The `dark/ light/ season-time/` tree | Yours |
| System packages | Through `pacman` and the AUR helper | `pacman -Rns` |

There is no uninstall script. The table above is the whole of it.

---

## Updating

```bash
git -C ~/.local/share/lumen pull
~/.local/share/lumen/install/install.sh
```

Or, from your own clone, `git pull && ./install/install.sh`. The second run
rebuilds only if the source changed, reports every link as already made, and
leaves your wallpapers alone.

---

## Testing it

The script is **sourceable**: sourcing it defines its functions and runs
nothing, which is how each step can be exercised on its own.

```bash
# Every command it would run, against your real machine, changing nothing
./install/install.sh --dry-run

# One step, against a throwaway HOME
( export HOME=$(mktemp -d)
  source install/install.sh
  ASSUME_YES=1
  link_wallpapers "$HOME/somewhere" )
```

A full run against a disposable `HOME` is the honest end-to-end test, and needs
no container:

```bash
HOME=/tmp/fake ./install/install.sh --yes --src /tmp/fake/src
```

---

## When it goes wrong

| | |
|---|---|
| **`lumen: command not found`** | `~/.cargo/bin` is not on your `PATH`. Add `export PATH="$HOME/.cargo/bin:$PATH"` to your shell's rc file. |
| **`lumen` errors instead of opening** | `qs` is missing, or `~/.config/quickshell/lumen` is not linked — Quickshell is the only front-end there is, so lumen says so on stderr and stops rather than opening nothing. |
| **`no package found under: …`** | That dependency is not in your repositories and not in the AUR under the names tried. Install it by hand; the script names it and carries on. |
| **cargo says `v2.3.1` after checking out a later tag** | The crate version in `Cargo.toml` trails the git tags. Cosmetic — the code is the tag you asked for. |
| **It refused to touch `~/Pictures/Wallpapers`** | You passed `--yes` and that folder has files in it. Run it again without `--yes` and it will offer to move them. |

---

## What it deliberately does not do

- **Install Hyprland.** A compositor is not an installer's business. It warns.
- **Edit `hyprland.conf`.** It prints the keybind for you to paste.
- **Run as root**, or install to `/usr/local/bin`. Everything lands in your home
  where it can be removed without sudo.
- **Support other distributions.** Four of the dependencies have no package
  outside Arch and CachyOS. The README at the repository root has the manual
  route.
- **Uninstall.** See the table above.
