#!/bin/bash
if [ "$#" -eq 0 ]; then
	if pgrep 'hyprsunset' >/dev/null; then
		printf "night-light-symbolic\n"
		printf "\n"
	else
		printf "night-light-disabled-symbolic\n"
		printf "\n"
	fi
else
	if pgrep 'hyprsunset' >/dev/null; then
		pkill -SIGTERM hyprsunset >/dev/null 2>&1
	else
		hyprctl dispatch exec -- hyprsunset -t 3400
	fi
	pkill -f -35 nwg-panel
fi
