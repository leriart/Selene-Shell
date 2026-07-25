import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts

import io.github.selene.shell

ApplicationWindow {
    id: root
    visible: true
    width: 520
    height: 360
    title: "Selene -- Rust <-> QML"

    Bridge {
        id: bridge
        greeting: "Selene -- bridge ready."
        counter: 0
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        Label {
            text: "selene-shell skeleton"
            font.pixelSize: 22
            font.bold: true
            color: "#dcdcdc"
        }

        Label {
            text: "Rust + cxx-qt + QML + Lua (coming next)"
            color: "#888"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
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
                font.pixelSize: 16
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
