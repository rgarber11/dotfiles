//@ pragma IconTheme Qogir

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick.Controls

Repeater {
    id: trayRepeater
    model: SystemTray.items
    required property real leftAbsoluteX
    delegate: Rectangle {
        id: trayButton
        required property SystemTrayItem modelData
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 20
        implicitHeight: 20
        color: "#002b36"
        border.color: "#073642"
        border.width: 1
        radius: 4
        IconImage {
            anchors.fill: parent
            anchors.margins: 1
            source: trayButton.modelData.icon
        }
        MouseArea {
            id: trayMouseArea
            hoverEnabled: true
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton && !trayButton.modelData.onlyMenu && trayButton.modelData.title !== "Network") {
                    trayButton.modelData.activate();
                } else if (mouse.button === Qt.MiddleButton && !trayButton.modelData.onlyMenu) {
                    trayButton.modelData.secondaryActivate();
                } else if (trayButton.modelData.hasMenu) {
                    trayButton.modelData.display(QsWindow.window, trayButton.x + trayRepeater.leftAbsoluteX + (trayButton.width / 2), 32);
                }
            }
            onEntered: {
                trayButton.border.color = "#839496";
                trayToolTipTimer.on = true;
                trayToolTipTimer.running = true;
            }
            onExited: {
                trayButton.border.color = "#073642";
                trayToolTipTimer.on = false;
                trayToolTipTimer.running = true;
            }
        }
        Tooltip {
            id: trayToolTip
            absoluteX: trayButton.x + trayRepeater.leftAbsoluteX
            absoluteY: 33
            text: trayButton.modelData.tooltipTitle !== "" ? trayButton.modelData.tooltipTitle : trayButton.modelData.tooltipDescription !== "" ? trayButton.modelData.tooltipDescription : trayButton.modelData.title
        }
        Timer {
            id: trayToolTipTimer
            property bool on: true
            interval: 150
            repeat: false
            running: false
            onTriggered: {
                if (on) {
                    trayToolTip.show();
                } else {
                    trayToolTip.hide();
                }
            }
        }
    }
}
