import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Controls
import Quickshell.Services.SystemTray

Repeater {
    model: SystemTray.items
    delegate: Rectangle {
        id: trayButton
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 20
        implicitHeight: 20
        color: "#002b36"
        border.color: "#073642"
        border.width: 1
        radius: 4
        IconImage {
            anchors.centerIn: parent
            width: parent.width - 1
            height: parent.height - 1
            source: modelData.icon
        }
        MouseArea {
            id: trayMouseArea
            hoverEnabled: true
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton && !modelData.onlyMenu && (modelData.title !== "caffeine" && modelData.title !== "Network")) {
                    modelData.activate();
                } else if (mouse.button === Qt.MiddleButton && !modelData.onlyMenu) {
                    modelData.secondaryActivate();
                } else if (modelData.hasMenu) {
                    modelData.display(panel, trayButton.x + rightRow.x, 32);
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
        PopupWindow {
            id: trayToolTip
            implicitWidth: toolTipRect.implicitWidth
            implicitHeight: toolTipRect.implicitHeight
            color: "transparent"
            Rectangle {
                id: toolTipRect
                anchors.fill: parent
                color: "#002b36"
                implicitWidth: toolTipText.implicitWidth + 10
                implicitHeight: toolTipText.implicitHeight + 10
                radius: 15
                border.color: "#073642"
                border.width: 1
                Text {
                    id: toolTipText
                    anchors.centerIn: parent
                    text: modelData.tooltipTitle !== "" ? modelData.tooltipTitle : modelData.tooltipDescription !== "" ? modelData.tooltipDescription : modelData.title
                    color: "#839496"
                }
            }
            anchor {
                window: panel
                rect {
                    x: trayButton.x + rightRow.x - (this.width / 2)
                    y: 33
                }
            }
            visible: false
            State {
                name: "visible"
                when: trayToolTip.visible
            }
            Transition {
                reversible: true
                PropertyAnimation {
                    target: trayToolTip
                    property: "visible"
                    duration: 1000
                    easing.type: Easing.InOutQuad
                }
            }
        }
        Timer {
            id: trayToolTipTimer
            property bool on: true
            interval: 100
            repeat: false
            running: false
            onTriggered: {
                if (on) {
                    trayToolTip.visible = true;
                } else {
                    trayToolTip.visible = false;
                }
            }
        }
    }
}
