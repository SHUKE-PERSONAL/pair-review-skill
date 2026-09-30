#!/usr/bin/env bash
# Split the screen 50/50: a dedicated pair-review browser showing the exported
# walkthrough on top, this terminal on the bottom (easier to read a diff this way).
#
# The browser runs on its own profile with a CDP port, so focus.mjs can scroll and
# highlight it without touching the operator's normal browser or keyboard focus.
# Re-running with another walkthrough reuses the open window.
#
# X11 only (needs wmctrl + xdotool); no Wayland support (window move/resize
# needs a compositor-specific tool there).
#
# Usage:
#   ./split-view.sh <path-to-walkthrough.html> [cdp-port, default 9333]

set -euo pipefail

html="${1:?usage: split-view.sh <path-to-walkthrough.html> [cdp-port]}"
port="${2:-9333}"
here="$(cd "$(dirname "$0")" && pwd)"
profile_dir="${XDG_CACHE_HOME:-$HOME/.cache}/pair-review-browser"

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

if curl -sf -m 2 "http://127.0.0.1:${port}/json/version" >/dev/null; then
    node "$here/focus.mjs" --open "$path" --port "$port"
else
    exe=""
    for candidate in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge; do
        if command -v "$candidate" >/dev/null 2>&1; then
            exe="$candidate"
            break
        fi
    done
    [ -n "$exe" ] || { echo "no Chrome / Chromium / Edge found"; exit 1; }
    # --class sets the WM_CLASS, so the window can be found apart from the operator's own browser.
    nohup "$exe" --remote-debugging-port="$port" --user-data-dir="$profile_dir" --class=pair-review-browser \
        --no-first-run --no-default-browser-check --new-window "file://$path" >/dev/null 2>&1 &
    disown
fi

br_id=""
for _ in $(seq 20); do
    sleep 0.5
    br_id=$(xdotool search --onlyvisible --class pair-review-browser 2>/dev/null | head -1 || true)
    [ -n "$br_id" ] && break
done

if [ -n "$br_id" ]; then
    xdotool windowmove "$br_id" 0 0
    xdotool windowsize "$br_id" "$screen_w" "$half_h"
    echo "browser (CDP $port) -> top"
else
    echo "pair-review browser window not found"
fi
