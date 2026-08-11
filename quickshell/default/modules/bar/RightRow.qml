import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Row {
    id: rightRow
    required property HyprlandMonitor hyprlandMonitor
    anchors {
        right: parent.right
        verticalCenter: parent.verticalCenter
        rightMargin: 10
    }
    spacing: 8
    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Repeater {
            model: Hyprland.workspaces.values.filter(function (ws) {
                return ws.id < 0 || ws.monitor === rightRow.hyprlandMonitor;
            })

            delegate: Button {
                id: control
                width: 32
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                contentItem: Text {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: modelData.active ? "#fdf6e3" : "#839496"
                    text: modelData.id > 0 ? modelData.id.toString() : "S"
                    font.pixelSize: 12
                    font.family: "sans"
                }
                background: Rectangle {
                    id: workspaceRect
                    color: modelData.active ? "#268bd2" : "#073642"
                    radius: 4
                    border.color: control.hovered ? "#93a1a1" : "#073642"
                    border.width: 1
                }
                onClicked: {
                    modelData.activate();
                }
            }
        }
    }
    Button {
        id: langButton
        anchors.verticalCenter: parent.verticalCenter
        contentItem: Text {
            id: langText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: "#93a1a1"
            text: Language.language
        }
        implicitHeight: 30
        width: langText.implicitWidth + 2
        background: Rectangle {
            id: langRect
            color: langButton.hovered ? "#073642" : "#002b36"
            radius: 4
            width: langButton.width
            height: langButton.height
        }
        onClicked: {
            Language.changeLanguage();
        }
    }
    Row {
        id: trayRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Tray {
            leftAbsoluteX: rightRow.x + trayRow.x
        }
        Caffeine {
            leftAbsoluteX: rightRow.x + trayRow.x
        }
        Volume {
            leftAbsoluteX: rightRow.x + trayRow.x
        }
        Sunset {
            leftAbsoluteX: rightRow.x + trayRow.x
        }
        Battery {}
    }
}
