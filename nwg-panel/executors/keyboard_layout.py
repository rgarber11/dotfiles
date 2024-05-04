#!/bin/python
import argparse
import json
import os
import socket
import subprocess
import sys

# NOTE: THIS COPIES CODE FROM nwg-piotr/nwg-panel. While I prefer my implementation of this to his,
# know that I stand on the shoulders of giants.


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def hyprctl(cmd, buf_size=2048):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(
            "/tmp/hypr/{}/.socket.sock".format(os.getenv("HYPRLAND_INSTANCE_SIGNATURE"))
        )
        s.send(cmd.encode("utf-8"))

        output = b""
        while True:
            buffer = s.recv(buf_size)
            if buffer:
                output = b"".join([output, buffer])
            else:
                break
        s.close()
        return output.decode("utf-8")
    except Exception as e:
        eprint(f"hyprctl: {e}")
        return ""


def list_keyboards():
    o = hyprctl("j/devices")
    devices = json.loads(o)
    return devices["keyboards"] if "keyboards" in devices else []


def get_current_layout(keyboards):
    for k in keyboards:
        if "keyboard" in k["name"]:
            return k["active_keymap"]
    return keyboards[0]["layout"]


def refresh(keyboards):
    label = get_current_layout(keyboards)
    print(label)


def change_layouts(keyboards):
    for k in keyboards:
        hyprctl(f"switchxkblayout {k['name']} next")


def to_english(keyboards):
    for k in keyboards:
        hyprctl(f"switchxkblayout {k['name']} 0")


def main():
    parser = argparse.ArgumentParser()
    keyboards = list_keyboards()
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
        subprocess.Popen(
            ["pkill", "-f", "-34", "nwg-panel"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
        )
        change_layouts(keyboards)
        sys.exit(0)
    elif args.english:
        subprocess.Popen(
            ["pkill", "-f", "-34", "nwg-panel"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
        )
        to_english(keyboards)
        sys.exit(0)
    refresh(keyboards)


if __name__ == "__main__":
    main()
