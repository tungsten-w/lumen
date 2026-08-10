#!/bin/bash

# ══════════════════════════════════════════════════════════════
# FONCTIONS
# ══════════════════════════════════════════════════════════════

get_saison() {
    case $(date +%m) in
        12|01|02) echo "hiver" ;;
        03|04|05) echo "printemps" ;;
        06|07|08) echo "ete" ;;
        09|10|11) echo "automne" ;;
    esac
}

get_moment_journee() {
    HEURE=$(date +"%H")
    if   [ "$HEURE" -ge 7  ] && [ "$HEURE" -lt 18 ]; then echo "day"
    elif [ "$HEURE" -ge 18 ] && [ "$HEURE" -lt 22 ]; then echo "sunset"
    else echo "night"
    fi
}

# apply a wallpaper with rofi picker (dark/light)
pick_with_rofi() {
    local dir="$1"
    local thumb_dir="$dir/.thumbnails"
    mkdir -p "$thumb_dir"

    if [ -z "$(find "$dir" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) \
        -not -path "$thumb_dir/*")" ]; then
        echo "Erreur : Aucune image dans $dir."; exit 1
    fi

    # generate thumbnails
    while IFS= read -r img; do
        base_name=$(basename "${img%.*}")
        thumb="$thumb_dir/$base_name.png"
        if [ ! -f "$thumb" ] || [ "$thumb" -ot "$img" ]; then
            magick "$img[0]" -thumbnail 900x900\> -strip "$thumb" 2>/dev/null
        fi
    done < <(find "$dir" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) \
        -not -path "$thumb_dir/*")

    # select wallpaper with rofi
    WALLPAPER=$(find "$dir" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) \
        -not -path "$thumb_dir/*" | sort | while read -r img; do
            base_name=$(basename "${img%.*}")
            echo -en "$(basename "$img")\0icon\x1f$thumb_dir/$base_name.png\n"
    done | rofi -dmenu -p "~ Select a wallpaper ~  ⏾ " \
               -show-icons -icon-theme "Papirus" \
               -theme ~/.config/rofi/wallpaper.rasi)

    [ -z "$WALLPAPER" ] && exit 0
    echo "$dir/$WALLPAPER"
}

# apply a random wallpaper (season/hour)
pick_random() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "Erreur : $dir n'existe pas." >&2; exit 1
    fi

    WALLPAPER=$(find "$dir" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) | shuf -n 1)
    [ -z "$WALLPAPER" ] && { echo "Erreur : Aucune image dans $dir." >&2; exit 1; }
    echo "$WALLPAPER"
}

# apply all (awww, pywal, hyprpanel, obsidian...)
apply_all() {
    local wallpaper="$1"
    local dark="$2"   # true ou false

    local wal_flags matugen_mode obs_base obs_theme relaunch_obs
    if $dark; then
        wal_flags="-q"; matugen_mode="dark"
        obs_base="dark"; obs_theme="obsidian"; relaunch_obs=true
    else
        wal_flags="-l -q"; matugen_mode="light"
        obs_base="light"; obs_theme="moonstone"; relaunch_obs=false
    fi

    pkill -f feh

    # set cursor theme based on mode (dark/light)
    if $dark; then
        hyprctl setcursor Bibata-Modern-Classic 24
    else
        hyprctl setcursor Bibata-Modern-Ice 24
    fi

    # Wallpaper
    awww img "$wallpaper" --transition-type random --transition-fps 60 --transition-duration 0.7
    sleep 1.5  # let the transition finish properly
    ln -sf "$wallpaper" "$HOME/Pictures/Wallpapers/current_wallpaper.jpg"

    # ── independent tasks launched in parallel ──────────────────

    # Pywal
    ( wal -i "$wallpaper" $wal_flags || echo "Erreur pywal." ) &

    # Copy /tmp (thumbnails for hyprpanel/rofi/hyprlock...)
    cp "$wallpaper" /tmp/current_wallpaper.png &

    # HyprPanel change of theme (dont used anymore)
    #HYPRPANEL_CONF="$HOME/.config/hyprpanel/config.json"
    #jq ".\"theme.matugen_settings.mode\"=\"$matugen_mode\"" "$HYPRPANEL_CONF" \
    #    > "$HYPRPANEL_CONF.tmp" && mv "$HYPRPANEL_CONF.tmp" "$HYPRPANEL_CONF"
    #hyprpanel -q; hyprpanel &

    # Matugen (gtk/rofi/tmux/neovim theming)
    ( matugen image "$wallpaper" --mode "$matugen_mode" -c "$HOME/.config/matugen/config.toml" --prefer saturation -q ) &

    # Noctalia + Spicetify (old version : [v4])
#    (
#        if ! pgrep -f "noctalia-shell" >/dev/null; then
#            nohup qs -c noctalia-shell >/dev/null 2>&1 &
#            sleep 3
#        fi
#
#        if $dark; then
#            qs -c noctalia-shell ipc call darkMode setDark
#        else
#            qs -c noctalia-shell ipc call darkMode setLight
#        fi
#        qs -c noctalia-shell ipc call wallpaper set "$wallpaper" all
#
#        if pgrep -x spotify >/dev/null; then
#            sleep 2 && spicetify restart
#        fi
#    ) &

    # Noctalia + Spicetify (new version : [v5])
    (
        if ! pgrep -x noctalia >/dev/null; then
            nohup noctalia -d >/dev/null 2>&1 &
            sleep 3
        fi

        if $dark; then
            noctalia msg theme-mode-set dark
        else
            noctalia msg theme-mode-set light
        fi
        noctalia msg wallpaper-set "$wallpaper"

        if pgrep -x spotify >/dev/null; then
            sleep 2 && spicetify restart
        fi
    ) &

    # Ulauncher
    ( pkill -f ulauncher ) &

    # Obsidian
    (
#       pkill -f -i obsidian || true; sleep 0.5
        VAULT_APP="$HOME/Documents/Obsidian Vault/.obsidian/app.json"
        VAULT_APPEAR="$HOME/Documents/Obsidian Vault/.obsidian/appearance.json"
        jq ".baseTheme = \"$obs_base\"" "$VAULT_APP" > "$VAULT_APP.tmp" && mv "$VAULT_APP.tmp" "$VAULT_APP"
        jq ".theme = \"$obs_theme\"" "$VAULT_APPEAR" > "$VAULT_APPEAR.tmp" && mv "$VAULT_APPEAR.tmp" "$VAULT_APPEAR"
        if $relaunch_obs; then
            ( nohup flatpak run md.obsidian.Obsidian >/dev/null 2>&1 & ) \
                || ( nohup obsidian >/dev/null 2>&1 & )
        fi
    ) &

    wait
}

# ══════════════════════════════════════════════════════════════
# MENU PRINCIPAL
# ══════════════════════════════════════════════════════════════

nohup ~/.config/.scripts/wallpaper_recognition.sh &

CHOIX=$(echo -e "\n\n󱠃\n󱩹" | rofi -dmenu -theme ~/.config/rofi/wallpaperchoise.rasi)

case "$CHOIX" in
    "")   # Dark — rofi picker
        WP=$(pick_with_rofi "$HOME/Pictures/Wallpapers/dark")
        [ -z "$WP" ] && exit 0
        apply_all "$WP" true
        ;;
    "")   # Light — rofi picker
        WP=$(pick_with_rofi "$HOME/Pictures/Wallpapers/light")
        [ -z "$WP" ] && exit 0
        apply_all "$WP" false
        ;;
    "󱠃")  # hour — random, dark if night
        MOMENT=$(get_moment_journee)
        WP=$(pick_random "$HOME/Pictures/Wallpapers/season-time/$MOMENT")
        [ -z "$WP" ] && exit 0
        [[ "$MOMENT" == "night" || "$MOMENT" == "sunset" ]] && DARK=true || DARK=false
        apply_all "$WP" $DARK
        ;;
    "󱩹")  # Saison — random, light
        SAISON=$(get_saison)
        WP=$(pick_random "$HOME/Pictures/Wallpapers/season-time/$SAISON")
        [ -z "$WP" ] && exit 0
        apply_all "$WP" false
        ;;
    *)
        exit 0
        ;;
esac
