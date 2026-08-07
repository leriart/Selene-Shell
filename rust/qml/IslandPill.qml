import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // Source of metrics/media data (a Rust Island QObject).
    property var islandSource: null

    implicitWidth: cardExpanded ? 480 : 220
    implicitHeight: cardExpanded ? 160 : 36

    width: implicitWidth
    height: implicitHeight

    property bool cardExpanded: false

    Behavior on implicitWidth {
        NumberAnimation { duration: Tokens.durationSlow; easing.type: Easing.OutCubic }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: Tokens.durationSlow; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 18
        color: cardExpanded ? Tokens.surface : Tokens.surfaceAlt
        border.color: Tokens.border
        border.width: 1

        Behavior on color {
            ColorAnimation { duration: Tokens.duration }
        }

        // Collapsed pill: media + load average
        Item {
            anchors.fill: parent
            visible: !root.cardExpanded

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: root.islandSource && root.islandSource.media_playing
                           ? Tokens.success : Tokens.textDim
                    Layout.alignment: Qt.AlignVCenter
                }

                Label {
                    text: (root.islandSource && root.islandSource.media_title) || "selene"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: 56
                    radius: 9
                    color: Qt.darker(Tokens.accent, 3.0)

                    Label {
                        anchors.centerIn: parent
                        text: root.islandSource
                              ? ("load " + root.islandSource.load_avg_1.toFixed(2))
                              : "--"
                        color: Tokens.accent
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }
                }
            }
        }

        // Expanded card
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            visible: root.cardExpanded

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Label {
                    text: "island"
                    color: Tokens.accent
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: root.islandSource
                          ? ("load " + root.islandSource.load_avg_1.toFixed(2))
                          : "--"
                    color: Tokens.textMuted
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 12
                    Layout.preferredHeight: 12
                    radius: 6
                    color: root.islandSource && root.islandSource.media_playing
                           ? Tokens.success : Tokens.textDim
                    Layout.alignment: Qt.AlignVCenter
                }
                Label {
                    text: (root.islandSource && root.islandSource.media_title) || "Nothing playing"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    text: (root.islandSource && root.islandSource.media_artist) || "--"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label {
                        text: "ram"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        Layout.preferredWidth: 40
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: Tokens.surfaceAlt
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * (root.islandSource
                                ? root.islandSource.ram_used_mb / Math.max(1, root.islandSource.ram_total_mb)
                                : 0)
                            radius: 3
                            color: Tokens.accent
                            Behavior on width {
                                NumberAnimation { duration: Tokens.duration }
                            }
                        }
                    }
                    Label {
                        text: root.islandSource
                              ? (root.islandSource.ram_used_mb + " / " + root.islandSource.ram_total_mb + " MB")
                              : "--"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        Layout.preferredWidth: 130
                        horizontalAlignment: Text.AlignRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label {
                        text: "proc"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        Layout.preferredWidth: 40
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.islandSource
                              ? (root.islandSource.procs_running + " running / " + root.islandSource.procs_total + " total")
                              : "--"
                        color: Tokens.text
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }
                    Label {
                        text: "l5 " + (root.islandSource
                              ? root.islandSource.load_avg_5.toFixed(2)
                              : "--")
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        Layout.preferredWidth: 90
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Button {
                    text: "lock"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                    enabled: root.islandSource !== null
                    onClicked: if (root.islandSource) root.islandSource.lock()
                }
                Button {
                    text: "suspend"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                    enabled: root.islandSource !== null
                    onClicked: if (root.islandSource) root.islandSource.suspend()
                }
                Button {
                    text: "reboot"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                    enabled: root.islandSource !== null
                    onClicked: if (root.islandSource) root.islandSource.reboot()
                }
                Button {
                    text: "logout"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                    enabled: root.islandSource !== null
                    onClicked: if (root.islandSource) root.islandSource.logout()
                }
                Item { Layout.fillWidth: true }
            }

            Label {
                text: (root.islandSource && root.islandSource.power_summary) || ""
                color: Tokens.textDim
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cardExpanded = !root.cardExpanded
            onDoubleClicked: root.cardExpanded = false
        }
    }
}
