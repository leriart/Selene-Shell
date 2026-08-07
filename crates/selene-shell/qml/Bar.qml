import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import io.github.selene.shell

Rectangle {
    id: bar

    property var bridge: null
    property var launcher: null
    property var island: null

    height: Tokens.barHeight
    radius: Tokens.radiusMd
    color: Tokens.surface
    border.color: Tokens.border
    border.width: 1

    Behavior on opacity {
        NumberAnimation { duration: Tokens.duration; easing.type: Easing.OutCubic }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacingMd
        anchors.rightMargin: Tokens.spacingMd
        spacing: Tokens.spacingMd

        // Logo + wordmark. The logo source flips between the dark and
        // white variants based on the surface luminance so it stays
        // visible regardless of which palette is active.
        Item {
            Layout.preferredHeight: 22
            Layout.preferredWidth: 22
            Layout.alignment: Qt.AlignVCenter

            // WCAG relative luminance applied to the current surface color.
            function surfaceLuminance() {
                const c = bar.color;
                const channel = (v) => {
                    v = v / 255.0;
                    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
                };
                return 0.2126 * channel(c.r * 255)
                     + 0.7152 * channel(c.g * 255)
                     + 0.0722 * channel(c.b * 255);
            }
            property bool lightBg: surfaceLuminance() < 0.4

            Image {
                anchors.fill: parent
                source: parent.lightBg
                       ? "qrc:/qt/qml/io/github/selene/shell/assets/logo-white.png"
                       : "qrc:/qt/qml/io/github/selene/shell/assets/logo-dark.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                asynchronous: true
            }
        }

        Label {
            text: "selene"
            color: Tokens.accent
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontMd
            font.bold: true
            font.letterSpacing: 0.5
        }

        Rectangle {
            Layout.preferredHeight: Tokens.chipSize - 6
            Layout.preferredWidth: 36
            radius: Tokens.radiusSm
            color: Qt.darker(Tokens.accent, 4.5)
            border.color: Tokens.accent
            border.width: 1

            Label {
                anchors.centerIn: parent
                text: "SUPER"
                color: Tokens.accent
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (bar.launcher) bar.launcher.toggle()
            }
        }

        Item { width: Tokens.spacingSm; Layout.fillHeight: true }

        Repeater {
            model: Math.max(1, bridge ? bridge.workspace_count : 0)

            delegate: Rectangle {
                id: chip
                required property int index
                Layout.preferredWidth: Tokens.chipSize
                Layout.preferredHeight: Tokens.chipSize - 6
                radius: Tokens.radiusSm
                color: (index + 1) === (bridge ? bridge.active_workspace_id : -1)
                       ? Tokens.accentMuted
                       : "transparent"
                border.color: (index + 1) === (bridge ? bridge.active_workspace_id : -1)
                              ? Tokens.accent
                              : Tokens.border
                border.width: 1

                Behavior on color {
                    ColorAnimation { duration: Tokens.duration }
                }
                Behavior on border.color {
                    ColorAnimation { duration: Tokens.duration }
                }

                Label {
                    anchors.centerIn: parent
                    text: (index + 1).toString()
                    color: (index + 1) === (bridge ? bridge.active_workspace_id : -1)
                           ? Tokens.accent
                           : Tokens.textMuted
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontSm
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: chip.opacity = 0.85
                    onExited: chip.opacity = 1.0
                }
            }
        }

        Item { Layout.fillWidth: true; Layout.fillHeight: true }

        Rectangle {
            visible: bridge && bridge.active_window_class
            radius: Tokens.radiusSm
            color: Tokens.surfaceAlt
            border.color: Tokens.border
            border.width: 1
            Layout.preferredHeight: Tokens.chipSize - 6
            Layout.maximumWidth: 220
            Layout.preferredWidth: Math.min(220, (bridge ? (bridge.active_window_title.length * 7 + 24) : 24))

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: Tokens.duration }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.spacingSm
                anchors.rightMargin: Tokens.spacingSm
                spacing: Tokens.spacingXs

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Tokens.success
                    Layout.alignment: Qt.AlignVCenter
                }

                Label {
                    text: bridge ? bridge.active_window_class : ""
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        Rectangle {
            Layout.preferredHeight: Tokens.chipSize - 6
            Layout.preferredWidth: 38
            radius: Tokens.radiusSm
            color: bridge && bridge.connected ? Qt.darker(Tokens.accent, 3.5) : Tokens.surfaceAlt
            border.color: bridge && bridge.connected ? Tokens.success : Tokens.border
            border.width: 1

            Behavior on border.color {
                ColorAnimation { duration: Tokens.duration }
            }

            Label {
                anchors.centerIn: parent
                text: bridge && bridge.connected ? "hypr" : "off"
                color: bridge && bridge.connected ? Tokens.success : Tokens.textDim
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
            }
        }

        Rectangle {
            visible: island && island.battery_present
            Layout.preferredHeight: Tokens.chipSize - 6
            Layout.preferredWidth: 56
            radius: Tokens.radiusSm
            color: Tokens.surfaceAlt
            border.color: island && island.battery_percent <= 15 ? Tokens.danger : Tokens.border
            border.width: 1

            Label {
                anchors.centerIn: parent
                text: island ? String(island.battery_percent) + "%" : ""
                color: island && island.battery_percent <= 15 ? Tokens.danger : Tokens.text
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontSm
            }
        }

        Rectangle {
            Layout.preferredHeight: Tokens.chipSize - 6
            Layout.preferredWidth: 62
            radius: Tokens.radiusSm
            color: Tokens.surfaceAlt
            border.color: Tokens.border
            border.width: 1

            Label {
                anchors.centerIn: parent
                text: island ? island.time_hhmm : "--:--"
                color: Tokens.text
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontSm
            }
        }
    }
}
