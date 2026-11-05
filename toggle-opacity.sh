#!/bin/bash
addr=$(hyprctl activewindow -j | jq -r '.address')
hyprctl setprop address:$addr opaque toggle