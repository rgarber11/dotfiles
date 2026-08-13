//@ pragma UseQApplication

import QtQuick
import Quickshell
import "./modules/bar"

ShellRoot {
    id: root

    Component.onCompleted: Quickshell.watchFiles = true

    Loader {
        active: true
        sourceComponent: Bar {}
    }
}
