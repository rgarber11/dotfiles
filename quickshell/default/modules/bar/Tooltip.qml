pragma ComponentBehavior: Bound
import Quickshell
import QtQuick

PopupWindow {
    id: root
    required property real absoluteX
    required property real absoluteY
    required property string text
    property bool shown: false
    signal show
    signal hide
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
        opacity: 0.0
        border.color: "#073642"
        border.width: 1
        Text {
            id: toolTipText
            anchors.centerIn: parent
            text: root.text
            color: "#839496"
        }
        states: State {
            name: "visibility"
            when: root.shown == true
            PropertyChanges {
                toolTipRect {
                    opacity: 1.0
                }
                root {
                    visible: true
                }
            }
        }

        transitions: [
            Transition {
                from: "*"
                to: "visibility"
                NumberAnimation {
                    target: toolTipRect
                    properties: "opacity"
                    easing.type: Easing.InOutQuad
                    duration: 150
                }
            },
            Transition {
                from: "visibility"
                to: "*"
                NumberAnimation {
                    target: toolTipRect
                    properties: "opacity"
                    easing.type: Easing.InOutQuad
                    duration: 150
                }
                onRunningChanged: {
                    if (!running) {
                        root.visible = false;
                    }
                }
            }
        ]
    }
    anchor {
        window: QsWindow.window
        rect {
            x: root.absoluteX - (this.width / 2)
            y: root.absoluteY
        }
    }
    visible: false
    onShow: {
        root.shown = true;
    }
    onHide: {
        root.shown = false;
    }
}
