import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland

Row {
    id: leftRow
    required property HyprlandMonitor hyprlandMonitor
    anchors {
        left: parent.left
        verticalCenter: parent.verticalCenter
        leftMargin: 10
    }
    spacing: 4
    property var topLevelCount: Hyprland.toplevels.values.filter(function (toplevel) {
        return (toplevel.workspace?.id < 0) || (toplevel.monitor === leftRow.hyprlandMonitor);
    }).length
    Text {
        id: monitorText
        color: "#839396"
        text: leftRow.hyprlandMonitor.name
        rightPadding: 8
        anchors.verticalCenter: parent.verticalCenter
        font.family: "mono"
        font.pointSize: 10
    }
    Repeater {
        id: workspaceContainer
        width: leftRow.width - monitorText.width - 8
        model: Hyprland.workspaces.values.filter(function (ws) {
            return ws.id < 0 || ws.monitor === leftRow.hyprlandMonitor;
        })
        delegate: Row {
            id: workspaceRow
            height: 24
            spacing: 4
            Text {
                id: workspaceText
                color: "#93a1a1"
                text: `${modelData.id > 0 ? modelData.id.toString() : "S"}:`
                rightPadding: 4
                anchors.verticalCenter: parent.verticalCenter
            }
            WindowWorkspaces {
                id: windowWorkspaces
                workspace: modelData
                hyprlandMonitor: leftRow.hyprlandMonitor
                numWindows: leftRow.topLevelCount
                numWorkspaces: Hyprland.workspaces.values.filter(function (ws) {
                    return ws.monitor === leftRow.hyprlandMonitor;
                }).length
                fullWidth: workspaceContainer.width
            }
        }
    }
}
