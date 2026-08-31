import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// TerminalPanel.qml -- embedded PTY view (Hax port).
//
// Owns nothing except its layout and the text input. The actual
// subprocess, ring buffer and keystroke plumbing live in the Rust
// `Terminal` QObject so multiple panels can share the same backend.
Rectangle {
    id: root

    property var terminal: null
    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible ? close() : open(); }
    function open() {
        visible = true;
        if (terminal && !terminal.running) terminal.spawn_default();
        forceActiveFocus();
        termInput.forceActiveFocus();
    }
    function close() { visible = false; }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.barMargin * 4, 880)
        height: Math.min(parent.height - Tokens.barMargin * 4, 560)
        radius: Tokens.radiusLg
        color: Qt.rgba(Tokens.bg.r, Tokens.bg.g, Tokens.bg.b, 0.96)
        border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.paddingLg
            spacing: Tokens.spacingSm

            // Header.
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "Terminal"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Label {
                    visible: terminal && terminal.command.length > 0
                    text: terminal ? terminal.command : ""
                    color: Tokens.textDim
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                }
                Button {
                    text: "clear"
                    onClicked: if (terminal) terminal.clear()
                }
                Button {
                    text: terminal && terminal.running ? "stop" : "new"
                    onClicked: {
                        if (!terminal) return;
                        if (terminal.running) terminal.close();
                        else terminal.spawn_default();
                    }
                }
                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            // Output list.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Qt.rgba(0, 0, 0, 0.55)
                radius: Tokens.radiusMd

                ListView {
                    id: outputList
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 0
                    verticalLayoutDirection: ListView.BottomToTop
                    ScrollBar.vertical: ScrollBar {}

                    property var lines: {
                        if (!terminal) return [];
                        try { return JSON.parse(terminal.output_lines || "[]"); }
                        catch (e) { return []; }
                    }

                    model: lines

                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: ListView.view.width
                        height: 18
                        color: "transparent"

                        Label {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            color: modelData === "\\u00a0"
                                   ? Qt.rgba(1,1,1,0.05)
                                   : Tokens.text
                            font.family: Tokens.monoFamily
                            font.pixelSize: 12
                            elide: Text.ElideNone
                            wrapMode: Text.NoWrap
                        }
                    }

                    // Auto-scroll to bottom on new content.
                    Connections {
                        target: terminal
                        function onOutput_linesChanged() {
                            outputList.positionViewAtBeginning();
                        }
                    }
                }
            }

            // Input row.
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: termInput
                    Layout.fillWidth: true
                    placeholderText: terminal && terminal.running
                                     ? "$ enter a command" : "(idle)"
                    color: Tokens.text
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontSm
                    background: Rectangle {
                        color: Qt.rgba(0, 0, 0, 0.35)
                        radius: Tokens.radiusSm
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1
                    }
                    onAccepted: {
                        if (!terminal || !terminal.running) return;
                        terminal.write(text + "\n");
                        text = "";
                    }
                    Keys.onPressed: function(event) {
                        if (!terminal || !terminal.running) return;
                        // Ctrl+C sends SIGINT-ish (Ctrl-C byte).
                        if ((event.modifiers & Qt.ControlModifier)
                            && event.key === Qt.Key_C) {
                            terminal.write_bytes([3]);
                            event.accepted = true;
                            return;
                        }
                        // Arrow keys send ANSI escape sequences.
                        if (event.key === Qt.Key_Up) {
                            terminal.write_bytes([27, 91, 65]);
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Down) {
                            terminal.write_bytes([27, 91, 66]);
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Right) {
                            terminal.write_bytes([27, 91, 67]);
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Left) {
                            terminal.write_bytes([27, 91, 68]);
                            event.accepted = true;
                            return;
                        }
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: root.close()
}