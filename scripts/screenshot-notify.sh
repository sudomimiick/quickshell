#!/bin/sh
# Called by services/Screenshot.qml after every capture.
#   $1  the image file     $2  copied | saved | both     $3  the Screenshots folder
# Shows a notification with a preview and acts on the button you pick.
# (notify-send waits for your choice, so this runs detached in the background.)

file=$1
what=$2
dir=$3

pretty() {
    case $1 in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

case $what in
    copied) body="Copied to clipboard" ;;
    saved) body="Saved to $(pretty "$file")" ;;
    *) body="Copied · saved to $(pretty "$file")" ;;
esac

editor=""
if command -v satty >/dev/null 2>&1; then
    editor=satty
elif command -v swappy >/dev/null 2>&1; then
    editor=swappy
fi

set -- -A default=Open
if [ "$what" = copied ]; then
    set -- "$@" -A save=Save
else
    set -- "$@" -A folder="Show in folder"
fi
[ -n "$editor" ] && set -- "$@" -A edit=Annotate
[ "$what" != copied ] && set -- "$@" -A delete=Delete

action=$(notify-send -a Screenshot -i camera-photo -h "string:image-path:$file" "$@" "Screenshot" "$body")

case $action in
    default)
        xdg-open "$file" ;;
    folder)
        # select the file in your file manager; fall back to just opening the folder
        dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 \
            /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems \
            array:string:"file://$file" string:"" >/dev/null 2>&1 || xdg-open "$dir" ;;
    save)
        mkdir -p "$dir" && dest="$dir/$(basename "$file")" && mv -- "$file" "$dest" \
            && notify-send -a Screenshot -i camera-photo -h "string:image-path:$dest" "Screenshot saved" "$(pretty "$dest")" ;;
    edit)
        if [ "$editor" = satty ]; then
            satty --filename "$file" --output-filename "$file"
        else
            swappy -f "$file" -o "$file"
        fi ;;
    delete)
        rm -f -- "$file" ;;
esac
