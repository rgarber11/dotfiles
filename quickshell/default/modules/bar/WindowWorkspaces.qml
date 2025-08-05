import Quickshell
import Quickshell.Hyprland
import QtQuick
import Quickshell.Widgets
import QtQuick.Controls

Repeater {
    id: windowWorkspaces

    required property HyprlandWorkspace workspace
    required property HyprlandMonitor hyprlandMonitor
    required property int numWorkspaces
    required property int numWindows
    required property real fullWidth
    model: workspace.toplevels
    delegate: Button {
        id: toplevelButton
        implicitWidth: Math.min(windowText.implicitWidth + 35, (fullWidth / numWindows) - 15 * numWorkspaces)
        anchors.verticalCenter: parent.verticalCenter
        height: 24
        contentItem: Row {
            spacing: 4
            leftPadding: 1
            IconImage {
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                source: Quickshell.iconPath(DesktopEntries.heuristicLookup(modelData.wayland.appId).icon, true)
            }
            Text {
                id: windowText
                anchors.verticalCenter: parent.verticalCenter
                color: "#93a1a1"
                text: modelData.title.length > 0 ? modelData.title : "Untitled"
                font.pointSize: 10
                font.family: "sans"
                elide: Text.ElideRight
                width: toplevelButton.width - 30
            }
        }
        background: Rectangle {
            id: toplevelRect
            color: modelData.activated ? "#073642" : "#002b36"
            radius: 4
            border.color: toplevelButton.hovered ? "#93a1a1" : "#073642"
            border.width: 1
        }
        onClicked: {
            modelData.wayland.activate();
        }
    }
}
