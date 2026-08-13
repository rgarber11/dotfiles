pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// your singletons should always have Singleton as the type
Singleton {
    id: root
    property string time

    Process {
        id: dateProc
        command: ["date", "+%A, %B %-d| %Y %r (%s)"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.time = this.text.replace("11|", "11th,").replace("12|", "12th,").replace("13|", "13th,").replace("1|", "1st,").replace("2|", "2nd,").replace("3|", "3rd,").replace("|", "th,")
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: dateProc.running = true
    }
}
