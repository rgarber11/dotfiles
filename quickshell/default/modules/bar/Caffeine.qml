//@ pragma IconTheme Qogir
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

Button {
    id: caffeineButton
    required property real leftAbsoluteX
    implicitWidth: 20
    implicitHeight: 20
    anchors.verticalCenter: parent.verticalCenter
    contentItem: IconImage {
        anchors.fill: parent
        anchors.margins: 1
        source: Quickshell.iconPath(CaffeineState.running ? "caffeine-cup-full" : "caffeine-cup-empty")
    }
    background: Rectangle {
        color: "#002b36"
        radius: 4
        border.color: caffeineButton.hovered ? "#93a1a1" : "#073642"
        border.width: 1
    }
    IdleInhibitor {
        window: caffeineButton.QsWindow.window
        enabled: CaffeineState.running && CaffeineState.keepMonitorOn
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: {
            caffeineToolTip.hide();
            caffeineMenu.shown = !caffeineMenu.shown;
        }
    }
    onClicked: {
        CaffeineState.running = !CaffeineState.running;
    }
    onHoveredChanged: {
        caffeineToolTipTimer.on = caffeineButton.hovered;
        caffeineToolTipTimer.running = true;
    }
    Tooltip {
        id: caffeineToolTip
        absoluteX: caffeineButton.x + caffeineButton.leftAbsoluteX
        absoluteY: 33
        text: CaffeineState.running ? "Caffeinated" : "Decaffeinated"
    }
    Timer {
        id: caffeineToolTipTimer
        property bool on: true
        interval: 150
        repeat: false
        running: false
        onTriggered: {
            if (on) {
                caffeineToolTip.show();
            } else {
                caffeineToolTip.hide();
            }
        }
    }
    PopupWindow {
        id: caffeineMenu
        property bool shown: false
        property real rowWidth: Math.max(keepMonitorText.implicitWidth, caffeineToggleText.implicitWidth) + 40
        implicitWidth: menuRect.implicitWidth
        implicitHeight: menuRect.implicitHeight
        color: "transparent"
        visible: shown
        anchor {
            window: QsWindow.window
            rect {
                x: caffeineButton.x + caffeineButton.leftAbsoluteX - (caffeineMenu.implicitWidth / 2)
                y: 33
            }
        }
        Rectangle {
            id: menuRect
            anchors.fill: parent
            color: "#002b36"
            radius: 4
            border.color: "#073642"
            border.width: 1
            implicitWidth: menuColumn.implicitWidth + 10
            implicitHeight: menuColumn.implicitHeight + 10
            HoverHandler {
                id: menuHover
            }
            Column {
                id: menuColumn
                anchors.centerIn: parent
                spacing: 2
                Rectangle {
                    implicitWidth: caffeineMenu.rowWidth
                    implicitHeight: keepMonitorText.implicitHeight + 8
                    radius: 4
                    color: keepMonitorMouse.containsMouse ? "#073642" : "transparent"
                    Text {
                        id: keepMonitorText
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Keep monitor on"
                        color: "#839496"
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 2
                        color: CaffeineState.keepMonitorOn ? "#859900" : "transparent"
                        border.color: "#586e75"
                        border.width: 1
                    }
                    MouseArea {
                        id: keepMonitorMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            CaffeineState.keepMonitorOn = !CaffeineState.keepMonitorOn;
                        }
                    }
                }
                Rectangle {
                    implicitWidth: caffeineMenu.rowWidth
                    implicitHeight: caffeineToggleText.implicitHeight + 8
                    radius: 4
                    color: caffeineToggleMouse.containsMouse ? "#073642" : "transparent"
                    Text {
                        id: caffeineToggleText
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: CaffeineState.running ? "Turn caffeine off" : "Turn caffeine on"
                        color: "#839496"
                    }
                    MouseArea {
                        id: caffeineToggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            CaffeineState.running = !CaffeineState.running;
                            caffeineMenu.shown = false;
                        }
                    }
                }
            }
        }
        Timer {
            interval: 1000
            running: caffeineMenu.shown && !menuHover.hovered
            onTriggered: caffeineMenu.shown = false
        }
    }
}
