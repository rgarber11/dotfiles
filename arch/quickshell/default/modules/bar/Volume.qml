pragma ComponentBehavior: Bound
//@ pragma IconTheme Qogir-dark
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Controls

Button {
    id: volumeButton
    required property real leftAbsoluteX
    implicitWidth: 20
    implicitHeight: 20
    anchors.verticalCenter: parent.verticalCenter
    contentItem: IconImage {
        anchors.fill: parent
        anchors.margins: 1
        source: Quickshell.iconPath(AudioDevices.iconName, true)
    }
    background: Rectangle {
        id: volumeRect
        color: "#002b36"
        radius: 4
        border.color: volumeButton.hovered ? "#93a1a1" : "#073642"
        border.width: 1
    }
    PwObjectTracker {
        id: pwTracker
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }
    PwNodeLinkTracker {
        id: pwLinkTracker
        node: Pipewire.defaultAudioSink
    }
    onClicked: {
        AudioDevices.toggleMute();
    }
}
