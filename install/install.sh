#!/usr/bin/env bash
#
# lumen — installer for Arch and CachyOS.
#
#     ./install/install.sh              install, asking as it goes
#     ./install/install.sh --help       every flag
#
# What every step does, and every path it touches, is written out in the
# README.md beside this file.
#
# It installs the dependencies, puts a checkout somewhere it can be updated
# from, builds the binary with cargo, links the Quickshell config, and makes
# the wallpaper folders wherever you want them.
#
# Nothing here is clever. Every step is skipped when it is already done, so
# running it again is how you update; anything that would overwrite something
# you own asks first; and --dry-run prints the whole run without touching a
# single file.

set -euo pipefail

readonly REPO_URL="https://github.com/tungsten-w/lumen.git"
readonly DEFAULT_SRC="${XDG_DATA_HOME:-$HOME/.local/share}/lumen"

# What quickshell_config() looks for. Compiled into the binary, so it is not
# ours to move.
readonly QS_LINK="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/lumen"

# `lumen` reads this path and no other. That is why the folder you choose is
# reached through a link rather than by the binary being told where it is.
readonly WALLPAPER_HOME="$HOME/Pictures/Wallpapers"

readonly WALLPAPER_TREE=(
    dark
    light
    season-time/day season-time/sunset season-time/night
    season-time/hiver season-time/printemps season-time/ete season-time/automne
)

ASSUME_YES=0
DRY_RUN=0
WANTED_REF=""
SRC=""
AUR=""
WANT_WALLUST=0

# ── Saying things ─────────────────────────────────────────────────────
# gum when it is there, plain text when it is not: the script has to be able to
# install gum, so it cannot need gum in order to speak.

has_gum() { command -v gum >/dev/null 2>&1; }

# The cat. It is here because a wallpaper picker may as well be pleasant, and
# because a long install reads better with something at the top of it.
#
# Drawn plain when gum is missing, which at the banner it usually is — gum is
# installed a few steps below this, and the cat comes first.
cat_says() {
    local face="$1" line="$2"
    local art
    art=$(printf ' /\\_/\\\n(%s)   lumen\n > ^ <    %s' "$face" "$line")
    if has_gum; then
        gum style --border rounded --border-foreground 212 --foreground 212 \
            --padding "0 2" --margin "1 0" "$art"
    else
        printf '\n\033[35m%s\033[0m\n\n' "$art"
    fi
}

banner() { cat_says " o.o " "one wallpaper, and the whole desktop follows"; }
purrs()  { cat_says " -.- " "$1"; }

step() {
    if has_gum; then
        printf '\n'
        gum style --foreground 212 --bold "» $*"
    else
        printf '\n\033[1;35m» %s\033[0m\n' "$*"
    fi
}

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
skip() { printf '  \033[2m· %s\033[0m\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\n\033[31m✗ %s\033[0m\n\n' "$*" >&2; exit 1; }

confirm() {
    local prompt="$1"
    if (( ASSUME_YES )); then
        say "$prompt — yes, because --yes"
        return 0
    fi
    if has_gum; then
        gum confirm "$prompt"
    else
        local reply
        read -r -p "  $prompt [y/N] " reply
        [[ "$reply" =~ ^[Yy] ]]
    fi
}

ask() {
    local prompt="$1" fallback="$2" reply
    if (( ASSUME_YES )); then
        printf '%s' "$fallback"
        return
    fi
    if has_gum; then
        reply=$(gum input --prompt "  $prompt " --value "$fallback")
    else
        read -r -p "  $prompt [$fallback] " reply
    fi
    printf '%s' "${reply:-$fallback}"
}

# Runs a command — or, under --dry-run, prints it and does nothing.
run() {
    if (( DRY_RUN )); then
        printf '  \033[2m$ %s\033[0m\n' "$*"
        return 0
    fi
    "$@"
}

usage() {
    cat <<'USAGE'
lumen — installer for Arch and CachyOS.

Usage:
  ./install/install.sh [options]

Options:
  --yes            take every default, ask nothing (for unattended runs)
  --dry-run        print every step without changing anything
  --ref REF        build this tag, branch or commit instead of asking
  --src DIR        keep the checkout here (default: ~/.local/share/lumen)
  -h, --help       this

Run it again to update: every step notices what is already done.
USAGE
}

# ── Preflight ─────────────────────────────────────────────────────────
# Everything that would stop the run is checked before the run touches
# anything, so a machine that cannot be installed onto is left exactly as it
# was rather than half done.

preflight() {
    step "Checking this machine"

    [[ -f /etc/arch-release ]] || die "This installer is for Arch and CachyOS. See the README for other distributions."
    command -v pacman >/dev/null || die "No pacman here, so this is not the Arch family after all."

    if [[ ${EUID} -eq 0 ]]; then
        die "Do not run this as root. It builds into your own ~/.cargo and writes your own ~/.config; it will ask for sudo only to install packages."
    fi

    command -v sudo >/dev/null || die "sudo is needed to install packages."
    command -v curl >/dev/null || die "curl is needed to reach the AUR and GitHub."

    local pretty
    pretty=$(sed -n 's/^PRETTY_NAME="\(.*\)"$/\1/p' /etc/os-release 2>/dev/null || true)
    ok "${pretty:-Arch-family Linux}"

    if [[ -z "${WAYLAND_DISPLAY:-}" ]] && ! command -v hyprctl >/dev/null; then
        warn "Hyprland was not found. lumen will install, but the cursor and IPC bits need it."
    fi
}

# ── gum ───────────────────────────────────────────────────────────────

ensure_gum() {
    has_gum && { skip "gum is already here"; return; }

    step "Installing gum"
    say "It draws the prompts below. Without it they are plain text, which works too."
    if confirm "Install gum?"; then
        install_now "gum" || warn "gum could not be installed; carrying on with plain prompts."
    else
        skip "Carrying on with plain prompts"
    fi
}

# ── The AUR ───────────────────────────────────────────────────────────
# Half of what lumen drives lives there, and which half depends on the distro:
# CachyOS ships awww, matugen and quickshell in its own repositories, plain
# Arch does not. Rather than encode that, every dependency below lists the
# names it may go under and the first one that exists wins.

ensure_aur_helper() {
    local helper
    for helper in paru yay; do
        if command -v "$helper" >/dev/null; then
            AUR="$helper"
            skip "AUR helper: $helper"
            return
        fi
    done

    step "Installing an AUR helper"
    say "paru builds the packages that are not in the repositories."
    if ! confirm "Install paru?"; then
        warn "Without one, anything not in your repositories will be skipped."
        return
    fi

    install_now "base-devel git" || die "base-devel and git are needed to build paru."

    local tmp
    tmp=$(mktemp -d)
    run git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    if (( DRY_RUN )); then
        printf '  \033[2m$ (cd %s/paru-bin && makepkg -si)\033[0m\n' "$tmp"
    else
        ( cd "$tmp/paru-bin" && makepkg -si --noconfirm )
    fi
    rm -rf "$tmp"
    command -v paru >/dev/null && AUR="paru" && ok "paru installed"
}

# Installs straight from the repositories, for the two things needed before the
# dependency pass can run at all.
install_now() {
    local pkgs="$1"
    # shellcheck disable=SC2086
    run sudo pacman -S --needed --noconfirm $pkgs
}

# Prints where a package can be had from: "repo", "aur", or nothing.
source_of() {
    local pkg="$1"
    if pacman -Si "$pkg" >/dev/null 2>&1; then
        printf 'repo'
    elif [[ -n "$AUR" ]] && "$AUR" -Si "$pkg" >/dev/null 2>&1; then
        printf 'aur'
    fi
}

# ── Dependencies ──────────────────────────────────────────────────────
# label | candidate package names | how to tell it is there | why
#
# Presence is judged on what lumen itself would find, not on what pacman
# thinks: spicetify lives in ~/.spicetify and belongs to no package at all, and
# a font is a font whether it arrived from a repository or was dropped into
# ~/.local/share/fonts by hand. `font:Name` asks fontconfig, anything else is a
# command to look for on PATH.

readonly REQUIRED=(
    "git|git|git|Cloning this checkout, and updating it"
    "rust|rust rustup|cargo|Building lumen"
    "awww|awww awww-git|awww|Setting the wallpaper, and the transition"
    "matugen|matugen matugen-bin|matugen|Material You palettes"
    "pywal|python-pywal16 python-pywal|wal|The classic sixteen colours"
    "imagemagick|imagemagick|magick|Thumbnails, and GIF handling"
    "quickshell|quickshell quickshell-git|qs|The picker and the settings panel"
    "jq|jq|jq|Editing Obsidian's JSON"
    "wl-clipboard|wl-clipboard|wl-copy|Copying and pasting presets"
    "JetBrains Mono Nerd Font|ttf-jetbrains-mono-nerd|font:JetBrainsMono Nerd Font|The menu glyphs"
    "Comfortaa|ttf-comfortaa|font:Comfortaa|The interface text"
)

readonly OPTIONAL=(
    "wallust|wallust wallust-bin|wallust|Another classic color source"
    "noctalia|noctalia-shell noctalia-git|noctalia|Theming the Noctalia shell"
    "spicetify|spicetify-cli|spicetify|Recolouring Spotify"
)

# Whether one row of the tables above is already satisfied.
have_dep() {
    local probe="$1"
    if [[ "$probe" == font:* ]]; then
        command -v fc-list >/dev/null 2>&1 || return 1
        # No `grep -q`: it closes the pipe on the first match, fc-list dies of
        # SIGPIPE, and `set -o pipefail` reports the whole thing as a failure —
        # so every font would look missing on a machine that has them all.
        fc-list : family 2>/dev/null | grep -iF "${probe#font:}" >/dev/null
        return
    fi
    command -v "$probe" >/dev/null 2>&1
}

install_dependencies() {
    step "Dependencies"

    local -a repo_pkgs=() aur_pkgs=() unavailable=()
    local row label candidates probe why pkg found origin

    local -a wanted=("${REQUIRED[@]}")

    if ((${#OPTIONAL[@]})) && [[ $ASSUME_YES -eq 0 ]] && has_gum; then
        local choice
        # `|| true` because choosing nothing exits non-zero, and choosing
        # nothing is a perfectly good answer.
        choice=$(printf '%s\n' "${OPTIONAL[@]}" | cut -d'|' -f1 |
            gum choose --no-limit --header "  Optional — space to pick, enter to go on" || true)
        while IFS= read -r label; do
            [[ -z "$label" ]] && continue
            for row in "${OPTIONAL[@]}"; do
                [[ "${row%%|*}" == "$label" ]] && wanted+=("$row")
            done
        done <<<"$choice"
    elif (( ASSUME_YES )); then
        wanted+=("${OPTIONAL[@]}")
    fi

    for row in "${wanted[@]}"; do
        IFS='|' read -r label candidates probe why <<<"$row"

        if have_dep "$probe"; then
            [[ "$label" == "wallust" ]] && WANT_WALLUST=1
            skip "$label — already here"
            continue
        fi

        found=""
        origin=""
        for pkg in $candidates; do
            origin=$(source_of "$pkg")
            [[ -n "$origin" ]] && { found="$pkg"; break; }
        done

        if [[ -z "$found" ]]; then
            unavailable+=("$label")
            warn "$label — no package found under: $candidates"
            continue
        fi

        [[ "$label" == "wallust" ]] && WANT_WALLUST=1

        say "$label — $found ($origin) · $why"
        if [[ "$origin" == "repo" ]]; then
            repo_pkgs+=("$found")
        else
            aur_pkgs+=("$found")
        fi
    done

    if ((${#repo_pkgs[@]})); then
        run sudo pacman -S --needed --noconfirm "${repo_pkgs[@]}"
    fi
    if ((${#aur_pkgs[@]})); then
        [[ -n "$AUR" ]] || die "These need the AUR and there is no helper: ${aur_pkgs[*]}"
        run "$AUR" -S --needed --noconfirm "${aur_pkgs[@]}"
    fi

    ((${#repo_pkgs[@]} + ${#aur_pkgs[@]})) || ok "Everything was already installed"
    ((${#unavailable[@]})) && warn "Install by hand: ${unavailable[*]}"
    return 0
}

# ── The checkout ──────────────────────────────────────────────────────
# The binary is only half of lumen: the Quickshell config is a folder of files
# that has to sit where the binary looks for it. So a checkout is kept rather
# than thrown away, both halves come from it, and updating is `git pull`
# followed by another run of this script.

# The repository this script was run from, if it was run from one at all.
enclosing_clone() {
    local here root
    # Empty when the script arrived down a pipe (`curl … | bash`), which is
    # exactly the case where there is no clone to be inside of.
    [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]:-}" ]] || return 1
    here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || return 1
    root=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null) || return 1
    [[ -f "$root/lumen/Cargo.toml" && -f "$root/quickshell/lumen/shell.qml" ]] || return 1
    printf '%s' "$root"
}

# The newest v*.*.* tag on the remote. `git ls-remote` rather than the GitHub
# API: no token, no rate limit, and it is the same list the Releases page has.
latest_tag() {
    git ls-remote --tags --refs "$REPO_URL" 'v*' 2>/dev/null |
        awk -F/ '{print $NF}' | sort -V | tail -1
}

choose_ref() {
    [[ -n "$WANTED_REF" ]] && { printf '%s' "$WANTED_REF"; return; }

    local tag
    tag=$(latest_tag)

    if (( ASSUME_YES )); then
        printf '%s' "${tag:-main}"
        return
    fi
    if [[ -z "$tag" ]]; then
        printf 'main'
        return
    fi
    if ! has_gum; then
        local reply
        read -r -p "  Build which? [1] release $tag  [2] main : " reply
        [[ "$reply" == "2" ]] && printf 'main' || printf '%s' "$tag"
        return
    fi

    local picked
    picked=$(gum choose --header "  Which version?" \
        "Latest release — $tag" \
        "main — the newest code, work in progress included")
    [[ "$picked" == main* ]] && printf 'main' || printf '%s' "$tag"
}

fetch_source() {
    step "Source"

    local here
    if here=$(enclosing_clone); then
        SRC="$here"
        ok "Using the clone this script came from: $SRC"
        say "Its checkout is left exactly as it is — build it as it stands."
        return
    fi

    local ref
    ref=$(choose_ref)

    if [[ -d "$SRC/.git" ]]; then
        say "Updating $SRC"
        run git -C "$SRC" fetch --tags --prune origin
    else
        say "Cloning into $SRC"
        run mkdir -p "$(dirname "$SRC")"
        run git clone "$REPO_URL" "$SRC"
    fi

    say "Checking out $ref"
    if (( DRY_RUN )); then
        printf '  \033[2m$ git -C %s checkout %s\033[0m\n' "$SRC" "$ref"
    else
        # A branch has to follow its remote; a tag is a fixed point and has no
        # upstream to pull from.
        if git -C "$SRC" rev-parse --verify --quiet "origin/$ref" >/dev/null; then
            git -C "$SRC" checkout -B "$ref" "origin/$ref"
        else
            git -C "$SRC" checkout --detach "$ref"
        fi
    fi
    ok "$SRC at $ref"
}

# ── Building ──────────────────────────────────────────────────────────

build_lumen() {
    step "Building lumen"
    say "cargo puts the binary in ~/.cargo/bin, which needs no root."
    # --locked builds against the Cargo.lock in the repository rather than
    # whatever resolves today, so what you get is what was tested.
    run cargo install --path "$SRC/lumen" --locked --force
    ok "lumen $( (( DRY_RUN )) && echo "would be" || echo "is") installed"
}

# ── Wallpapers ────────────────────────────────────────────────────────
# The binary reads ~/Pictures/Wallpapers and nothing else — eight places in
# main.rs and one in Wallreco.qml. So you may keep the collection anywhere, and
# what makes that work is a link at the path lumen insists on. Nothing here
# deletes a folder that has anything in it.

link_wallpapers() {
    local chosen="$1"

    [[ "$chosen" == "$WALLPAPER_HOME" ]] && return 0

    if [[ -L "$WALLPAPER_HOME" ]]; then
        local points_at
        points_at=$(readlink -f "$WALLPAPER_HOME" || true)
        if [[ "$points_at" == "$(readlink -f "$chosen")" ]]; then
            skip "$WALLPAPER_HOME already points there"
            return 0
        fi
        confirm "$WALLPAPER_HOME points at $points_at. Point it at $chosen instead?" || return 1
        run rm "$WALLPAPER_HOME"
    elif [[ -d "$WALLPAPER_HOME" ]]; then
        if [[ -n "$(ls -A "$WALLPAPER_HOME" 2>/dev/null)" ]]; then
            warn "$WALLPAPER_HOME is a real folder, and it is not empty."
            say  "lumen can only read that path, so it has to become a link to $chosen."
            (( ASSUME_YES )) && { warn "Refusing to move your wallpapers unattended. Re-run without --yes."; return 1; }
            confirm "Move everything in it into $chosen, then link?" || return 1
            run mkdir -p "$chosen"
            # A dotglob'd mv, so `.thumbnails` comes along with the rest.
            if (( DRY_RUN )); then
                printf '  \033[2m$ mv %s/* %s/.[!.]* -> %s\033[0m\n' "$WALLPAPER_HOME" "$WALLPAPER_HOME" "$chosen"
            else
                ( shopt -s dotglob nullglob; mv -n "$WALLPAPER_HOME"/* "$chosen"/ )
            fi
            run rmdir "$WALLPAPER_HOME"
        else
            run rmdir "$WALLPAPER_HOME"
        fi
    fi

    run mkdir -p "$(dirname "$WALLPAPER_HOME")"
    run ln -s "$chosen" "$WALLPAPER_HOME"
    ok "$WALLPAPER_HOME → $chosen"
}

make_wallpaper_tree() {
    step "Wallpapers"
    say "Where do you keep them? Anywhere is fine — lumen will be pointed at it."

    local chosen
    chosen=$(ask "Folder:" "$WALLPAPER_HOME")
    chosen="${chosen/#\~/$HOME}"
    [[ -n "$chosen" ]] || { warn "No folder given; skipping."; return 0; }

    local leaf
    for leaf in "${WALLPAPER_TREE[@]}"; do
        run mkdir -p "$chosen/$leaf"
    done
    ok "dark/, light/ and season-time/ made under $chosen"

    link_wallpapers "$chosen" || warn "Left $WALLPAPER_HOME alone. lumen will read it, not $chosen."
}

# ── Config ────────────────────────────────────────────────────────────

# Links `target` at `link`, and never over the top of something you wrote.
link_into() {
    local target="$1" link="$2" what="$3"

    # `ln -s` does not check what it points at, so a target that is not there
    # still links — and leaves a dead link that fails later, somewhere else,
    # looking like something other than a missing file. A checkout really can be
    # missing a folder.
    if [[ ! -e "$target" ]]; then
        warn "$what: $target is not there. Nothing was linked."
        return 1
    fi

    if [[ -L "$link" ]]; then
        if [[ "$(readlink -f "$link" || true)" == "$(readlink -f "$target")" ]]; then
            skip "$what already linked"
            return 0
        fi
        confirm "$link points somewhere else. Repoint it at the checkout?" || return 1
        run rm "$link"
    elif [[ -e "$link" ]]; then
        confirm "$link exists and is yours, not a link. Move it aside to $link.bak?" || return 1
        run mv "$link" "$link.bak"
    fi

    run mkdir -p "$(dirname "$link")"
    run ln -s "$target" "$link"
    ok "$what → $target"
}

link_config() {
    step "Config"

    link_into "$SRC/quickshell/lumen" "$QS_LINK" "Quickshell config" ||
        warn "Quickshell config not linked; lumen has nothing left to draw with."
}

setup_wallust() {
    (( WANT_WALLUST )) || command -v wallust >/dev/null 2>&1 || return 0

    step "Wallust templates"
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/wallust"
    run mkdir -p "$dir/templates" "$HOME/.cache/wallust"
    for name in lumen-rofi.rasi lumen-colors.json; do
        if [[ ! -e "$dir/templates/$name" && ! -L "$dir/templates/$name" ]]; then
            run ln -s "$SRC/wallust/templates/$name" "$dir/templates/$name"
        else
            skip "$name already exists"
        fi
    done

    if [[ ! -e "$dir/wallust.toml" ]]; then
        run cp "$SRC/wallust/wallust.toml" "$dir/wallust.toml"
        ok "Wallust config created"
    elif ! grep -q 'lumen_rofi' "$dir/wallust.toml" ||
         ! grep -q 'lumen_json' "$dir/wallust.toml"; then
        warn "Add the two [templates] entries from $SRC/wallust/wallust.toml to $dir/wallust.toml."
    else
        skip "Lumen's Wallust template entries already present"
    fi
}

# ── Done ──────────────────────────────────────────────────────────────

summary() {
    step "Done"
    purrs "all set. go pick something."


    case ":$PATH:" in
        *":$HOME/.cargo/bin:"*) ok "~/.cargo/bin is on your PATH" ;;
        *) warn "~/.cargo/bin is not on your PATH. Add it, or \`lumen --settings\` will not resolve:"
           say  '  export PATH="$HOME/.cargo/bin:$PATH"' ;;
    esac

    say ""
    say "Drop some wallpapers in dark/ and light/, then bind it:"
    say ""
    say "  bind = \$mainMod, W, exec, $HOME/.cargo/bin/lumen"
    say ""
    say "  lumen              the menu"
    say "  lumen --settings   the panel, with the picker beside it"
    say "  lumen --thumbs     build the thumbnail cache now"
    say ""
    say "To update: git -C $SRC pull && $SRC/install/install.sh"
}

# ── Main ──────────────────────────────────────────────────────────────

main() {
    SRC="$DEFAULT_SRC"

    while (( $# )); do
        case "$1" in
            --yes|-y)   ASSUME_YES=1 ;;
            --dry-run)  DRY_RUN=1 ;;
            --ref)      [[ $# -ge 2 ]] || die "--ref needs a tag, branch or commit."
                        WANTED_REF="$2"; shift ;;
            --src)      [[ $# -ge 2 ]] || die "--src needs a directory."
                        SRC="$2"; shift ;;
            -h|--help)  usage; exit 0 ;;
            *)          printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done

    [[ -n "$SRC" ]] || die "--src needs a directory."

    banner
    (( DRY_RUN )) && step "Dry run — nothing below will be changed"

    preflight
    ensure_gum
    ensure_aur_helper
    install_dependencies
    fetch_source
    build_lumen
    make_wallpaper_tree
    link_config
    setup_wallust
    summary
}

# Sourcing the script gets you its functions and changes nothing, which is how
# the steps below are tested one at a time.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi
