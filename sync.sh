#!/usr/bin/env bash
# Копирует актуальные конфиги в ~/dotfiles (без бэкапов и секретов)
DOT="$(cd "$(dirname "$0")" && pwd)"
C="$HOME/.config"
copy() {   # copy <откуда> <куда в репо>
  [ -e "$1" ] || return 0
  mkdir -p "$DOT/$2"
  rsync -a --delete --exclude '*.bak*' --exclude '*.bak.*' --exclude 'lazy-lock.json' \
        --exclude '__pycache__' "$1"/ "$DOT/$2"/
}
copyf() { [ -f "$1" ] && mkdir -p "$DOT/$(dirname "$2")" && cp "$1" "$DOT/$2"; }

copy "$C/niri"              config/niri
copy "$C/quickshell/kellos-music" config/quickshell/kellos-music
copy "$C/waybar"            config/waybar
copy "$C/kitty"             config/kitty
copy "$C/nvim"              config/nvim
copy "$C/fastfetch"         config/fastfetch
copy "$C/Kvantum/Kellos"    config/Kvantum/Kellos
copy "$C/mako"              config/mako
copy "$C/fuzzel"            config/fuzzel
copy "$C/swaylock"          config/swaylock
copyf "$C/starship.toml"            config/starship.toml
copyf "$C/Kvantum/kvantum.kvconfig" config/Kvantum/kvantum.kvconfig
copyf "$HOME/.local/bin/ks"   bin/ks
copyf "$HOME/.local/bin/buds" bin/buds

# наши блоки из .bashrc (fastfetch и т.п.)
mkdir -p "$DOT/shell"
sed -n '/# >>> /,/# <<< /p' "$HOME/.bashrc" > "$DOT/shell/bashrc.kellos"

# темы для Stylus, если лежат в Загрузках
for f in "$HOME"/Загрузки/kellos-*.user.css "$HOME"/Downloads/kellos-*.user.css; do
  [ -f "$f" ] && mkdir -p "$DOT/stylus" && cp "$f" "$DOT/stylus/"
done

# обои (из конфига niri), если не огромные
WP=$(grep -oE 'swaybg"[^}]*"-i" "[^"]+"' "$C/niri/config.kdl" 2>/dev/null | grep -oE '"[^"]+"$' | tr -d '"')
WP="${WP/#\~/$HOME}"
if [ -f "$WP" ] && [ "$(stat -c %s "$WP")" -lt 15000000 ]; then
  mkdir -p "$DOT/wallpaper" && cp "$WP" "$DOT/wallpaper/"
fi
