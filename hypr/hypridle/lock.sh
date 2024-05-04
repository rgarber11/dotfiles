#!/bin/bash
python /home/rgarber11/.config/nwg-panel/executors/keyboard_layout.py -e
[ pidof hyprlock ] || hyprlock
