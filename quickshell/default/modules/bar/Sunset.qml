pragma ComponentBehavior: Bound
//@ pragma IconTheme Qogir-dark
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Controls

Button {
    id: sunsetButton
    required property real leftAbsoluteX
    implicitWidth: 20
    implicitHeight: 20
    anchors.verticalCenter: parent.verticalCenter
    contentItem: IconImage {
        anchors.fill: parent
        anchors.margins: 1
        source: Quickshell.iconPath(SunsetState.running ? "redshift-status-on" : "redshift-status-off")
    }
    background: Rectangle {
        color: "#002b36"
        radius: 4
        border.color: sunsetButton.hovered ? "#93a1a1" : "#073642"
        border.width: 1
    }
    onClicked: {
        SunsetState.running = !SunsetState.running;
    }
    Tooltip {
        id: sunsetToolTip
        absoluteX: sunsetButton.x + sunsetButton.leftAbsoluteX
        absoluteY: 33
        text: SunsetState.running ? "Sunsetted" : "Daylight"
    }
    onHoveredChanged: {
        sunsetToolTipTimer.on = sunsetButton.hovered;
        sunsetToolTipTimer.running = true;
    }
    Timer {
        id: sunsetToolTipTimer
        property bool on: true
        interval: 150
        repeat: false
        running: false
        onTriggered: {
            if (on) {
                sunsetToolTip.show();
            } else {
                sunsetToolTip.hide();
            }
        }
    }
}
