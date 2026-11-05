#!/bin/bash
CONFIG_DIR="/home/unterhose/.config/waybar"
STATE_FILE="/tmp/waybar-output-mode"
MODE=$(cat "$STATE_FILE" 2>/dev/null || echo "all")

pkill waybar

if [ "$MODE" = "all" ]; then
  cp "$CONFIG_DIR/config-hdmi.jsonc" "$CONFIG_DIR/config.jsonc"
  echo "hdmi" > "$STATE_FILE"
else
  cp "$CONFIG_DIR/config-all.jsonc" "$CONFIG_DIR/config.jsonc"
  echo "all" > "$STATE_FILE"
fi

waybar &