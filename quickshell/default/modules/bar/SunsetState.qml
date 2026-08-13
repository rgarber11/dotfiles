pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias running: sunsetProc.running

    Process {
        id: sunsetProc
        command: ["hyprsunset", "-t", "4500"]
        running: false
    }
}

