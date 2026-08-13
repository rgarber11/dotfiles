import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQml.Models

Variants {
    model: Quickshell.screens
    delegate: Component {
        PanelWindow {
            id: panel
            required property var modelData
            property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(modelData)
            screen: modelData
            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 32
            color: "transparent"
            margins {
                top: 8
                left: 8
                right: 8
            }
            Rectangle {
                id: bar
                anchors.fill: parent
                color: "#002b36"
                border.color: "#073642"
                radius: Infinity
                border.width: 1
                LeftRow {
                    hyprlandMonitor: panel.hyprlandMonitor
                    width: timeText.x - 20
                }
                Text {
                    id: timeText
                    anchors.centerIn: parent
                    color: "#93a1a1"
                    text: Time.time
                    font.family: "mono"
                    font.pointSize: 11
                }
                RightRow {
                    id: rightRow
                    hyprlandMonitor: panel.hyprlandMonitor
                }
            }
        }
    }
}
