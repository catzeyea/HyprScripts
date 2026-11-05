#!/usr/bin/env bash

SHADER_DIR="/usr/share/hyprshade/shaders"

selected=$(find "$SHADER_DIR" -maxdepth 1 -type f -name '*.frag' -printf '%f\n' | sort | fzf \
    --prompt="Shader > " \
    --header="Enter: aktivieren | r: hyprctl reload | q: beenden" \
    --bind "q:abort" \
    --bind "r:execute(hyprctl reload)")

if [[ -n "$selected" ]]; then
    hyprshade on "$SHADER_DIR/$selected"
fi