#!/bin/bash

if [ ! -f "/home/rgarber11/.config/hypr/hyprland/dpms_state" ]; then
        echo "on" >/home/rgarber11/.config/hypr/hyprland/dpms_state
        exit 0
fi

if [[ $(</home/rgarber11/.config/hypr/hyprland/dpms_state) = "on" ]]; then
        echo "off" >/home/rgarber11/.config/hypr/hyprland/dpms_state
        hyprctl dispatch dpms off
else
        echo "on" >/home/rgarber11/.config/hypr/hyprland/dpms_state
        hyprctl dispatch dpms on
fi
