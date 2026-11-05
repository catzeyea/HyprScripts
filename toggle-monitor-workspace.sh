#!/usr/bin/env bash
# Toggle between the two workspaces of the focused side monitor.
# HDMI-A-1 (left): 6 <-> 7   |   HDMI-A-2 (right): 8 <-> 9
# --move: move the focused window to the other workspace instead of switching.

read -r mon ws < <(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.name) \(.activeWorkspace.id)"')

case "$mon" in
  HDMI-A-1) [[ $ws == 6 ]] && target=7 || target=6 ;;
  HDMI-A-2) [[ $ws == 8 ]] && target=9 || target=8 ;;
  *) exit 0 ;;
esac

if [[ $1 == --move ]]; then
  hyprctl dispatch "hl.dsp.window.move({ workspace = $target, follow = false })"
else
  hyprctl dispatch "hl.dsp.focus({ workspace = $target })"
fi
