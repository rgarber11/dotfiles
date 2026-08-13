import Quickshell
import Quickshell.Widgets
import QtQuick
import Quickshell.Services.UPower

Row {
    id: battery
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4
    property UPowerDevice uPower: UPower.devices.values.find(device => device.isLaptopBattery)
    IconImage {
        width: 16
        height: 16
        source: Quickshell.iconPath(battery.uPower.iconName)
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(battery.uPower.percentage * 100) + "%"
        color: "#839496"
    }
}
