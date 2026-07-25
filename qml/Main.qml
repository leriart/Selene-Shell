import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts

import io.github.selene.shell

ApplicationWindow {
    id: root
    visible: true
    width: 560
    height: 460
    title: "Selene -- Rust <-> Hyprland <-> QML"

    Bridge {
        id: bridge
        greeting: "Selene -- bridge ready."
        counter: 0
        hyprland_status: "not connected"
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: bridge.refresh()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        Label {
            text: "selene-shell skeleton -- ipc bridge"
            font.pixelSize: 22
            font.bold: true
            color: "#dcdcdc"
        }

        Label {
            text: "Rust + cxx-qt + QML + Lua (coming) -- hyprland-rs live"
            color: "#888"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            color: bridge.connected ? "#1e3a1e" : "#3a1e1e"
            radius: 4

            Label {
                anchors.centerIn: parent
                text: (bridge.connected ? "CONNECTED" : "DISCONNECTED")
                    + " -- " + bridge.hyprland_status
                color: bridge.connected ? "#7ee787" : "#f97583"
                font.pixelSize: 12
            }
        }

        GridLayout {
            columns: 2
            columnSpacing: 16
            rowSpacing: 6
            Layout.fillWidth: true

            Label { text: "active workspace"; color: "#888" }
            Label {
                text: bridge.active_workspace_id + "  (" + bridge.active_workspace_name + ")"
                color: "#a78bfa"
                font.bold: true
            }

            Label { text: "workspace count"; color: "#888" }
            Label {
                text: bridge.workspace_count
                color: "#a78bfa"
                font.bold: true
            }

            Label { text: "active window"; color: "#888" }
            Label {
                text: bridge.active_window_class || "(none)"
                color: "#dcdcdc"
            }

            Label { text: "title"; color: "#888" }
            Label {
                text: bridge.active_window_title || "-"
                color: "#dcdcdc"
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "#1a1b1e"
            radius: 8
            border.color: "#333"
            border.width: 1

            Label {
                anchors.fill: parent
                anchors.margins: 16
                text: bridge.greeting
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
                color: "#a78bfa"
                font.pixelSize: 14
            }
        }

        TextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: "Your name"
        }

        RowLayout {
            spacing: 8

            Button {
                text: "Greet"
                onClicked: bridge.greeting = bridge.greet(nameField.text)
            }

            Button {
                text: "Increment"
                onClicked: bridge.increment()
            }

            Button {
                text: "Refresh IPC"
                onClicked: bridge.refresh()
            }

            Button {
                text: "Quit"
                onClicked: Qt.quit()
            }
        }

        Label {
            text: "counter: " + bridge.counter
            color: "#a78bfa"
        }

        Item { Layout.fillHeight: true }
    }
}
