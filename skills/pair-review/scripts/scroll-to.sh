#!/usr/bin/env bash
# Jump the already-open walkthrough browser to a specific change anchor
# (e.g. #change-003) so the operator sees the right block without manual
# scrolling, right as the agent starts explaining that unit.
#
# X11 only (needs xdotool); no Wayland support.
#
# Usage:
#   ./scroll-to.sh <path-to-walkthrough.html> <anchor, e.g. change-003>

set -euo pipefail

html="${1:?usage: scroll-to.sh <path-to-walkthrough.html> <anchor>}"
anchor="${2:?usage: scroll-to.sh <path-to-walkthrough.html> <anchor>}"

command -v xdotool >/dev/null 2>&1 || { echo "xdotool not found — install it (e.g. apt install xdotool)"; exit 1; }

br_id=$(xdotool search --onlyvisible --class 'firefox|chrome|chromium' 2>/dev/null | head -1 || true)
if [ -z "$br_id" ]; then
    echo "browser window not found"
    exit 0
fi

path=$(readlink -f "$html")
url="file://${path}#${anchor}"

xdotool windowactivate "$br_id"
sleep 0.3
xdotool key --window "$br_id" ctrl+l
sleep 0.15
xdotool type --window "$br_id" -- "$url"
sleep 0.15
# One Enter often just dismisses the omnibox autocomplete suggestion instead
# of navigating; a second Enter reliably commits the typed URL.
xdotool key --window "$br_id" Return
sleep 0.15
xdotool key --window "$br_id" Return

echo "browser -> $url"
