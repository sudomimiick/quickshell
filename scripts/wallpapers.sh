#!/bin/sh
# Lists the wallpapers in a folder and makes small thumbnails for the picker.
#   $1 folder   $2 thumbnail folder   $3 thumbnail size in px
# Prints "F<tab>path" for every picture (sorted), then "E", then
# "T<tab>path<tab>thumbnail" as each thumbnail is ready — cached ones straight away,
# new ones as they're made (several at a time, at low priority). Thumbnails are made
# with whatever is installed: vipsthumbnail, gdk-pixbuf-thumbnailer or ImageMagick.

dir=$1
cache=$2
size=${3:-512}

[ -d "$dir" ] || {
    echo E
    exit 0
}
mkdir -p "$cache"

list=$(find -L "$dir" -maxdepth 3 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
    -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.jxl' -o -iname '*.avif' \) 2>/dev/null | sort -fV)
[ -n "$list" ] && printf '%s\n' "$list" | sed 's/^/F\t/'
echo E
[ -n "$list" ] || exit 0

thumb() { printf '%s/%s.png' "$cache" "$(printf '%s' "$1" | md5sum | cut -c1-32)"; }

todo=$(mktemp) || exit 0
trap 'rm -f "$todo"' EXIT
printf '%s\n' "$list" | while IFS= read -r f; do
    t=$(thumb "$f")
    if [ -s "$t" ] && [ "$t" -nt "$f" ]; then
        printf 'T\t%s\t%s\n' "$f" "$t"
    else
        printf '%s\n' "$f" >>"$todo"
    fi
done
[ -s "$todo" ] || exit 0

if command -v vipsthumbnail >/dev/null 2>&1; then
    tool=vips
elif command -v gdk-pixbuf-thumbnailer >/dev/null 2>&1; then
    tool=pixbuf
elif command -v magick >/dev/null 2>&1; then
    tool=magick
elif command -v convert >/dev/null 2>&1; then
    tool=convert
else
    exit 0 # no thumbnailer: the picker shrinks the pictures itself (slower)
fi
export tool size cache

tr '\n' '\0' <"$todo" | nice -n 10 xargs -0 -r -n 1 -P "$(nproc 2>/dev/null || echo 2)" sh -c '
    f=$1
    t="$cache/$(printf "%s" "$f" | md5sum | cut -c1-32).png"
    tmp="$t.part.png"
    case $tool in
        vips) vipsthumbnail "$f" --size "${size}x${size}" -o "$tmp" ;;
        pixbuf) gdk-pixbuf-thumbnailer -s "$size" "$f" "$tmp" ;;
        magick) magick "$f[0]" -auto-orient -thumbnail "${size}x${size}" "$tmp" ;;
        convert) convert "$f[0]" -auto-orient -thumbnail "${size}x${size}" "$tmp" ;;
    esac >/dev/null 2>&1 && [ -s "$tmp" ] && mv -f "$tmp" "$t" && printf "T\t%s\t%s\n" "$f" "$t"
    rm -f "$tmp"
' sh
