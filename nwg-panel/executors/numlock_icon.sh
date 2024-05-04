#!/bin/bash

if [ $(brightnessctl --device "*numlock" -m | sed -n "s/^.*,leds,\([0-9]\+\).*/\1/p") -eq 1 ]; then
    printf "\n"
    printf "\n"
else 
    printf "num-lock-off\n"
    printf "\n"
fi
