#!/usr/bin/env bash
# Split the screen 50/50: a browser showing the exported walkthrough on top,
# this terminal on the bottom (easier to read a diff this way).
#
# X11 only (needs wmctrl + xdotool); no Wayland support (window move/resize
# needs a compositor-specific tool there).
#
# Usage:
#   ./split-view.sh <path-to-walkthrough.html>

set -euo pipefail

html="${1:?usage: split-view.sh <path-to-walkthrough.html>}"

command -v wmctrl >/dev/null 2>&1 || { echo "wmctrl not found — install it (e.g. apt install wmctrl)"; exit 1; }
command -v xdotool >/dev/null 2>&1 || { echo "xdotool not found — install it (e.g. apt install xdotool)"; exit 1; }

read -r screen_w screen_h < <(xdotool getdisplaygeometry)
half_h=$((screen_h / 2))

term_id=$(xdotool search --onlyvisible --class 'gnome-terminal|konsole|xterm|alacritty|kitty|wezterm|tilix|terminator|xfce4-terminal' 2>/dev/null | head -1 || true)
if [ -n "$term_id" ]; then
    xdotool windowmove "$term_id" 0 "$half_h"
    xdotool windowsize "$term_id" "$screen_w" $((screen_h - half_h))
    echo "terminal -> bottom"
else
    echo "terminal window not found"
fi

path=$(readlink -f "$html")
before=$(xdotool search --onlyvisible --class 'firefox|chrome|chromium' 2>/dev/null || true)

xdg-open "$path" >/dev/null 2>&1 &
sleep 3

after=$(xdotool search --onlyvisible --class 'firefox|chrome|chromium' 2>/dev/null || true)
new_id=$(comm -13 <(sort <<<"$before") <(sort <<<"$after") | head -1 || true)
br_id="${new_id:-$(head -1 <<<"$after")}"

if [ -n "$br_id" ]; then
    xdotool windowactivate "$br_id"
    xdotool windowmove "$br_id" 0 0
    xdotool windowsize "$br_id" "$screen_w" "$half_h"
    echo "browser -> top"
else
    echo "browser window not found"
fi
