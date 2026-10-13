#!/usr/bin/env bash
# Kellos rice — установка на свежую Fedora: bash install.sh
DOT="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%s)
echo "Пакеты…"
sudo dnf install -y niri waybar kitty neovim fastfetch mako swaybg fuzzel swaylock \
  playerctl blueman kvantum rsync git gh jetbrains-mono-fonts-all \
  fontawesome-6-free-fonts fontawesome-6-brands-fonts polkit-gnome libnotify ImageMagick || true
echo "  Quickshell (noctalia-qs) и Throne ставятся отдельно — см. README"
echo "Конфиги…"
for d in "$DOT"/config/*; do
  n=$(basename "$d"); t="$HOME/.config/$n"
  [ -e "$t" ] && cp -r "$t" "$t.bak.$TS"
  if [ -d "$d" ]; then mkdir -p "$t" && cp -r "$d"/. "$t"/; else cp "$d" "$t"; fi
done
mkdir -p "$HOME/.local/bin" && cp "$DOT"/bin/* "$HOME/.local/bin/" && chmod +x "$HOME"/.local/bin/*
grep -q 'bashrc.kellos' "$HOME/.bashrc" || echo "[ -f \"$DOT/shell/bashrc.kellos\" ] && . \"$DOT/shell/bashrc.kellos\"" >> "$HOME/.bashrc"
if ls "$DOT"/wallpaper/* >/dev/null 2>&1; then
  mkdir -p "$HOME/Изображения" && cp "$DOT"/wallpaper/* "$HOME/Изображения/"
fi
echo "Готово. Перезайди в сессию niri."
