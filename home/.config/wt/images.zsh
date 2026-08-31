# Inline images in the pane, via kitty's graphics protocol. Sourced from
# .zshrc; every function here is skipped outside kitty.
#
#   icat FILE...        show images (also reads piped image data)
#   ilast [DIR]         the newest image in DIR (default: here) - screenshots,
#                       generated charts, anything an agent just wrote
#   iclear              wipe images out of the pane (they survive clear)
[[ -n ${KITTY_WINDOW_ID:-} ]] && (( $+commands[kitten] )) || return 0

icat() { kitten icat --align left "$@" }

ilast() {
  local dir=${1:-.} f
  f=$(find "$dir" -maxdepth 1 -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
           -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.svg' \) 2>/dev/null \
      | xargs -I{} stat -f '%m %N' {} 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  [[ -n $f ]] || { print -u2 "ilast: no images in $dir"; return 1 }
  print -P "%F{244}${f/#$HOME/~}%f"
  kitten icat --align left "$f"
}

iclear() { kitten icat --clear }
