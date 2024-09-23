#!/bin/env python
import argparse
import json
import os
import socket
import subprocess
import sys
from pathlib import Path


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def hyprctl(cmd: str, buf_size: int = 2048):
    try:
        runtime_dir = os.getenv("XDG_RUNTIME_DIR")
        if not runtime_dir:
            raise KeyError("Enironment Variable Not Found")
        hypr_instance = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
        if not hypr_instance:
            raise KeyError("Enironment Variable Not Found")
        socket_path = Path(
            runtime_dir,
            "hypr",
            hypr_instance,
            ".socket.sock",
        )
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(str(socket_path))
            _ = s.send(cmd.encode("utf-8"))
            output = b""
            while True:
                buffer = s.recv(buf_size)
                if buffer:
                    output = b"".join([output, buffer])
                else:
                    break
            return output.decode("utf-8")
    except Exception as e:
        eprint(f"hyprctl: {e}")
        return ""


def get_current_layout():
    o = hyprctl("j/devices")
    devices = json.loads(o)
    keyboards = devices["keyboards"] if "keyboards" in devices else []
    for k in keyboards:
        if "keyboard" in k["name"]:
            return k["active_keymap"]
    return keyboards[0]["layout"]


def refresh():
    label = get_current_layout()
    print(label)


def change_layouts():
    hyprctl("switchxkblayout all next")


def to_english():
    hyprctl("switchxkblayout all 0")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-s", "--switch", action="store_true", help="switches keyboard layout"
    )
    parser.add_argument(
        "-e",
        "--english",
        action="store_true",
        help="Guarantees English Layout for Keyboards",
    )
    args = parser.parse_args()
    if args.switch:
        change_layouts()
        subprocess.Popen(
            ["pkill", "-f", "-34", "nwg-panel"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
        )
    elif args.english:
        to_english()
        subprocess.Popen(
            ["pkill", "-f", "-34", "nwg-panel"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
        )
    else:
        refresh()


if __name__ == "__main__":
    main()
