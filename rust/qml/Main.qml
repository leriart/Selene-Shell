import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts

import io.github.selene.shell

ApplicationWindow {
    id: root
    visible: true
    width: 720
    height: 480
    title: "Selene -- Rust <-> Hyprland <-> QML"
    color: Tokens.bg

    Bridge {
        id: bridge
        greeting: "Selene -- bridge ready."
        counter: 0
        hyprland_status: "not connected"

        Component.onCompleted: bridge.start_listener()
    }

    Spawner {
        id: spawner

        Component.onCompleted: spawner.refresh()
    }

    Island {
        id: islandBackend

        Component.onCompleted: islandBackend.refresh()
    }

    Notifier {
        id: notifierBackend

        Component.onCompleted: notifierBackend.refresh_from_disk()
    }

    Config {
        id: configBackend

        Component.onCompleted: configBackend.reload()
    }

    Palette {
        id: paletteBackend

        Component.onCompleted: paletteBackend.refresh()
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: paletteBackend.refresh()
    }

    Timer {
        // Slow fallback refresh; the Rust event listener pushes real updates
        // through the cxx-qt queued bridge, this is just a safety net in case
        // an event slips through (or we started without a Hyprland session).
        interval: 10000
        running: true
        repeat: true
        onTriggered: bridge.refresh()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.barMargin
        spacing: Tokens.spacingMd

        Bar {
            id: bar
            Layout.fillWidth: true
            bridge: bridge
            launcher: launcher
        }

        IslandPill {
            id: islandWidget
            Layout.alignment: Qt.AlignHCenter
            islandSource: islandBackend
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Tokens.surface
            radius: Tokens.radiusMd
            border.color: Tokens.border
            border.width: 1

            GridLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                columns: 2
                columnSpacing: Tokens.spacingLg
                rowSpacing: Tokens.spacingSm

                Label {
                    text: "active workspace"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: bridge.active_workspace_id + "  " + (bridge.active_workspace_name || "(none)")
                    color: Tokens.accent
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontMd
                    font.bold: true
                }

                Label {
                    text: "workspace count"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    text: bridge.workspace_count
                    color: Tokens.accent
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontMd
                    font.bold: true
                }

                Label {
                    text: "active window"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: bridge.active_window_class || "(none)"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                }

                Label {
                    text: "title"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: bridge.active_window_title || "-"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                    elide: Text.ElideRight
                }

                Label {
                    text: "hyprland"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: bridge.hyprland_status
                    color: bridge.connected ? Tokens.success : Tokens.danger
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontSm
                }

                Label {
                    text: "config"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: (configBackend.defaults_used ? "defaults" : "loaded") + "  " +
                          (configBackend.status || "")
                    color: configBackend.defaults_used ? Tokens.danger : Tokens.textMuted
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                    elide: Text.ElideRight
                }

                Label {
                    text: "panel height"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    text: String(configBackend.panel_height) + " px  (" +
                          configBackend.panel_position + ", " +
                          (configBackend.panel_transparent ? "transparent" : "opaque") + ")"
                    color: Tokens.text
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontSm
                }

                Label {
                    text: "accent"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Rectangle {
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: 56
                    radius: 4
                    color: configBackend.theme_accent
                    border.color: Tokens.border
                    border.width: 1
                }

                Item { Layout.columnSpan: 2; Layout.fillHeight: true }

                Label {
                    text: "counter"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    text: bridge.counter + " -- " + bridge.greeting
                    color: Tokens.accent
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "Your name"
            }

            Button {
                text: "Greet"
                onClicked: bridge.greeting = bridge.greet(nameField.text)
            }
            Button {
                text: "+"
                onClicked: bridge.increment()
            }
            Button {
                text: "Refresh"
                onClicked: bridge.refresh()
            }
            Button {
                text: "Launcher"
                onClicked: launcher.open()
            }
            Button {
                text: "Notif"
                onClicked: notifierPanel.toggle()
            }
            Button {
                text: "Quit"
                onClicked: Qt.quit()
            }
        }
    }

    Launcher {
        id: launcher
        anchors.fill: parent
        z: 1000
        spawner: spawner
        Keys.onEscapePressed: launcher.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R) {
                launcher.toggle();
                event.accepted = true;
            }
        }
    }

    NotificationPanel {
        id: notifierPanel
        anchors.fill: parent
        z: 1100
        notifier: notifierBackend
    }
}
