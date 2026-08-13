#!/bin/bash
hyprctl switchxkb layout all 0
pidof hyprlock || hyprlock
