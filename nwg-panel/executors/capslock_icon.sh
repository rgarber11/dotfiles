#!/bin/bash

if [ $(brightnessctl --device "*capslock" -m | sed -n "s/^.*,leds,\([0-9]\+\).*/\1/p") -eq 0 ]; then
    printf "\n"
    printf "\n"
else 
    printf "caps-lock-on\n"
    printf "\n"
fi
