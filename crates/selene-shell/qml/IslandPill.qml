import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Effects

Item {
    id: root

    property var islandSource: null
    property var visualizer: null
    property var network: null
    property var audio: null
    property var state: null

    implicitWidth: cardExpanded ? 540 : 220
    implicitHeight: cardExpanded ? 340 : 36

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
        radius: cardExpanded ? Tokens.radiusLg : Tokens.radiusLg
        color: cardExpanded
               ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.92)
               : Tokens.surfaceAlt
        border.color: Tokens.border
        border.width: 1

        Behavior on color {
            ColorAnimation { duration: Tokens.duration }
        }

        // Backdrop blur when expanded
        MultiEffect {
            anchors.fill: parent
            source: wallpaper
            blurEnabled: root.cardExpanded
            blur: 0.6
            saturation: 1.15
            opacity: 0.88
        }

        // -- COLLAPSED pill: media dot + title + load avg ---------
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

                Item {
                    id: vizBox
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.visualizer !== null && root.visualizer.running
                             && root.islandSource && root.islandSource.media_playing

                    property var bars: []

                    Connections {
                        target: root.visualizer
                        function onBars_jsonChanged() {
                            if (!root.visualizer) return;
                            try {
                                vizBox.bars = JSON.parse(root.visualizer.bars_json || "[]");
                            } catch (e) {
                                vizBox.bars = [];
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 1
                        Repeater {
                            model: vizBox.bars
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 1
                                Layout.maximumHeight: 18
                                Layout.preferredHeight: Math.max(1, (modelData / 100.0) * 18)
                                Layout.alignment: Qt.AlignBottom
                                color: Tokens.accent
                                radius: 1
                                Behavior on Layout.preferredHeight {
                                    NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
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

        // -- EXPANDED Dashboard ---------------------------------------
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            visible: root.cardExpanded

            // Header row
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "dashboard"
                    color: Tokens.accent
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: root.islandSource ? root.islandSource.time_hhmm : ""
                    color: Tokens.textMuted
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                }
                Label {
                    text: root.islandSource ? root.islandSource.date_ymd : ""
                    color: Tokens.textDim
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            // Media section
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                // Album art placeholder (accent-tinted block)
                Rectangle {
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 80
                    radius: Tokens.radiusMd
                    color: {
                        if (!root.islandSource) return Tokens.surfaceAlt;
                        return root.islandSource.media_playing
                               ? Qt.darker(Tokens.accent, 3.5)
                               : Tokens.surfaceAlt;
                    }
                    border.color: Tokens.border
                    border.width: 1

                    Label {
                        anchors.centerIn: parent
                        text: root.islandSource && root.islandSource.media_playing
                              ? "\u266B"
                              : "\u25A0"
                        color: root.islandSource && root.islandSource.media_playing
                               ? Tokens.accent : Tokens.textDim
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontXl
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        Layout.fillWidth: true
                        text: root.islandSource
                              ? (root.islandSource.media_title || "Nothing playing")
                              : "Nothing playing"
                        color: Tokens.text
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontMd
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.islandSource
                              ? (root.islandSource.media_artist || "--")
                              : "--"
                        color: Tokens.textMuted
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.islandSource
                              ? (root.islandSource.media_player || "")
                              : ""
                        color: Tokens.textDim
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        visible: root.islandSource
                                 && root.islandSource.media_player.length > 0
                    }
                }

                // Media controls
                RowLayout {
                    spacing: 4
                    Button {
                        text: "\u23EE"
                        enabled: root.islandSource !== null
                        font.pixelSize: Tokens.fontMd
                        onClicked: if (root.islandSource) root.islandSource.lock()
                    }
                    Button {
                        text: root.islandSource && root.islandSource.media_playing
                              ? "\u23F8" : "\u25B6"
                        enabled: root.islandSource !== null
                        font.pixelSize: Tokens.fontMd
                    }
                    Button {
                        text: "\u23ED"
                        enabled: root.islandSource !== null
                        font.pixelSize: Tokens.fontMd
                    }
                }
            }

            // Visualizer bar in media section
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                visible: root.visualizer !== null && root.visualizer.running
                         && root.islandSource && root.islandSource.media_playing

                property var bars: []

                Connections {
                    target: root.visualizer
                    function onBars_jsonChanged() {
                        if (!root.visualizer) return;
                        try {
                            parent.bars = JSON.parse(root.visualizer.bars_json || "[]");
                        } catch (e) {
                            parent.bars = [];
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 1
                    Repeater {
                        model: parent.bars
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 1
                            Layout.maximumHeight: 22
                            Layout.preferredHeight: Math.max(1, (modelData / 100.0) * 22)
                            Layout.alignment: Qt.AlignBottom
                            color: Tokens.accent
                            radius: 1
                            Behavior on Layout.preferredHeight {
                                NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            // System stats section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                // CPU
                RowLayout {
                    spacing: 8
                    Label {
                        text: "CPU"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        Layout.preferredWidth: 36
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
                                ? root.islandSource.cpu_percent / 100.0
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
                              ? root.islandSource.cpu_percent.toFixed(1) + "%"
                              : "--"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        Layout.preferredWidth: 52
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // RAM
                RowLayout {
                    spacing: 8
                    Label {
                        text: "RAM"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        Layout.preferredWidth: 36
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
                              ? (root.islandSource.ram_used_mb + "/" + root.islandSource.ram_total_mb + " MB")
                              : "--"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Battery
                RowLayout {
                    spacing: 8
                    visible: root.islandSource && root.islandSource.battery_present
                    Label {
                        text: "BAT"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        Layout.preferredWidth: 36
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
                                ? root.islandSource.battery_percent / 100.0
                                : 0)
                            radius: 3
                            color: root.islandSource && root.islandSource.battery_percent <= 15
                                   ? Tokens.danger : Tokens.success
                            Behavior on width {
                                NumberAnimation { duration: Tokens.duration }
                            }
                        }
                    }
                    Label {
                        text: root.islandSource
                              ? root.islandSource.battery_percent + "% " + root.islandSource.battery_status
                              : "--"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // Power row
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Button {
                    text: "game"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                    enabled: root.islandSource !== null
                    onClicked: if (root.state) root.state.game_mode()
                }
                Button {
                    text: "focus"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                    enabled: root.islandSource !== null
                    onClicked: if (root.state) root.state.focus_mode()
                }
                Button {
                    text: "restore"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                    enabled: root.islandSource !== null
                    onClicked: if (root.state) root.state.restore()
                }
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
                    text: "logout"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                    enabled: root.islandSource !== null
                    onClicked: if (root.islandSource) root.islandSource.logout()
                }
                Item { Layout.fillWidth: true }

                // Connection status summary
                Label {
                    text: (root.network && root.network.connected
                           ? "net up" : "net --")
                          + " | "
                          + (root.audio && !root.audio.muted
                             ? "audio " + root.audio.volume_percent + "%"
                             : "audio --")
                    color: Tokens.textDim
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                }
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
