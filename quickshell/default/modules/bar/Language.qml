pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls

// your singletons should always have Singleton as the type
Singleton {
    id: root
    property string language
    signal changeLanguage
    function setLanguage(initialText) {
        const parsedJson = JSON.parse(initialText);
        root.language = parsedJson["keyboards"].find(function (k) {
            return k.main === true;
        })["active_keymap"] ?? parsedJson["keyboards"][0]["active_keymap"] ?? "unknown";
    }
    Process {
        id: initialLangProc
        command: ["hyprctl", "-j", "devices"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.setLanguage(this.text)
        }
    }
    Process {
        id: langProc
        command: ["hyprctl", "switchxkblayout", "all", "next"]
        running: false
    }
    Component.onCompleted: {
        Hyprland.rawEvent.connect(function (event) {
            if (event.name === "activelayout") {
                root.language = event.parse(2)[1];
            }
        });
    }
    onChangeLanguage: {
        langProc.running = true;
    }
}
