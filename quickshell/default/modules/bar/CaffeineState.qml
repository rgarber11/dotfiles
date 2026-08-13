pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias running: inhibitProc.running
    property alias keepMonitorOn: caffeineSettings.keepMonitorOn

    Process {
        id: inhibitProc
        // Only inhibit "idle" (which keeps the monitors on) when keepMonitorOn is
        // set; otherwise inhibit just "sleep" so the machine stays awake but the
        // screen can still blank / DPMS off.
        command: ["systemd-inhibit", "--what=" + (root.keepMonitorOn ? "idle:sleep:handle-lid-switch" : "sleep:handle-lid-switch"), "--who=quickshell", "--why=Caffeine", "sleep", "infinity"]
        running: false
    }

    // A Process ignores command changes while running, so restart the inhibitor
    // when the scope changes mid-session to apply the new --what immediately.
    onKeepMonitorOnChanged: {
        if (inhibitProc.running) {
            inhibitProc.running = false;
            inhibitProc.running = true;
        }
    }

    FileView {
        path: Quickshell.statePath("caffeine.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
            }
        }
        JsonAdapter {
            id: caffeineSettings
            property bool keepMonitorOn: false
        }
    }
}
