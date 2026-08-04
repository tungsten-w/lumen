#!/usr/bin/env sh

# Vérification ImageMagick
command -v magick >/dev/null 2>&1 || {
  echo "ImageMagick requis : sudo pacman -S imagemagick"
  exit 1
}

DIR="$1"
[ -z "$DIR" ] && {
  echo "Usage: $0 /chemin/dossier"
  exit 1
}

find "$DIR" -type f \( \
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \
\) -print0 | while IFS= read -r -d '' file
do

# Skip si déjà tagué
case "$file" in
  *"#"*) continue ;;
esac

hex=$(magick "$file" \
  -resize 120x120^ \
  -gravity center -extent 120x120 \
  -blur 0x8 \
  -colors 6 \
  -format "%c" histogram:info: \
  | sed -n 's/.*#\([0-9A-Fa-f]\{6\}\).*/\1/p' \
  | head -n 1)
  # RGB
  r=$((16#${hex:0:2}))
  g=$((16#${hex:2:2}))
  b=$((16#${hex:4:2}))

  maxc=$(( r > g ? (r > b ? r : b) : (g > b ? g : b) ))
  minc=$(( r < g ? (r < b ? r : b) : (g < b ? g : b) ))
  saturation=$(( maxc - minc ))

  # GRAY (peu saturé)
  if [ "$saturation" -lt 20 ]; then
      name="#gray"

  # PINK (rouge dominant + bleu présent)
  elif [ "$r" -gt 180 ] && [ "$b" -gt 120 ]; then
      name="#pink"

  # ORANGE (rouge fort + vert moyen)
  elif [ "$r" -gt 180 ] && [ "$g" -gt 80 ] && [ "$g" -lt 180 ]; then
      name="#orange"

  # ROUGE
  elif [ "$r" -gt "$g" ] && [ "$r" -gt "$b" ]; then
      name="#red"

  # JAUNE
  elif [ "$r" -gt "$b" ] && [ "$g" -gt "$b" ]; then
      name="#yellow"

  # VERT
  elif [ "$g" -gt "$r" ] && [ "$g" -gt "$b" ]; then
      name="#green"

  # BLEU
  elif [ "$b" -gt "$r" ] && [ "$b" -gt "$g" ]; then
      name="#blue"

  # CYAN
  elif [ "$g" -gt "$r" ] && [ "$b" -gt "$r" ]; then
      name="#cyan"

  # VIOLET
  elif [ "$r" -gt "$g" ] && [ "$b" -gt "$g" ]; then
      name="#purple"

  else
      name="gray"
  fi


  ext="${file##*.}"
  base="${file%.*}"
  new="${base}-${name}.${ext}"

  [ "$file" != "$new" ] && [ ! -e "$new" ] && {
    echo "→ $file → $new"
    mv "$file" "$new"
  }
done
