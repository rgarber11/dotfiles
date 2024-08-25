#!/bin/bash
if [ "$#" -eq 0 ]; then
	if pgrep 'gammastep' >/dev/null; then
		printf "night-light-symbolic\n"
		printf "\n"
	else
		printf "night-light-disabled-symbolic\n"
		printf "\n"
	fi
    else
	if pgrep 'gammastep' >/dev/null; then
		pkill -SIGTERM gammastep > /dev/null 2>&1
	else
		hyprctl dispatch exec -- gammastep -O 3400K
	fi
	pkill -f -35 nwg-panel
fi
