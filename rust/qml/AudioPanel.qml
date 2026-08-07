import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property var audio: null

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible = !visible; }
    function open() { visible = true; }
    function close() { visible = false; }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.barMargin
        width: 360

        color: Tokens.surface
        radius: Tokens.radiusLg
        border.color: Tokens.border
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true

                Label {
                    text: "audio"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: audio ? (audio.default_sink_name || "(no sink)") : ""
                    color: Tokens.textMuted
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 160
                }

                Button {
                    text: "refresh"
                    enabled: audio !== null
                    onClicked: if (audio) audio.refresh()
                }
                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            Label {
                Layout.fillWidth: true
                text: audio ? audio.status : ""
                color: audio && audio.available ? Tokens.textMuted : Tokens.danger
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
                elide: Text.ElideRight
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            // -- Volume slider ------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Label {
                    text: "vol"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    Layout.preferredWidth: 36
                }

                Slider {
                    id: volumeSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 150
                    stepSize: 1
                    value: audio ? audio.volume_percent : 0
                    enabled: audio !== null && audio.available
                    onMoved: if (audio) audio.set_volume(value)
                }

                Label {
                    text: audio ? (String(audio.volume_percent) + "%") : "--"
                    color: Tokens.text
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontSm
                    Layout.preferredWidth: 48
                    horizontalAlignment: Text.AlignRight
                }

                Button {
                    text: audio && audio.muted ? "unmute" : "mute"
                    enabled: audio !== null && audio.available
                    onClicked: if (audio) audio.toggle_mute()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Button {
                    text: "-10%"
                    enabled: audio !== null && audio.available
                    onClicked: if (audio) audio.bump(-10)
                }
                Button {
                    text: "+5%"
                    enabled: audio !== null && audio.available
                    onClicked: if (audio) audio.bump(5)
                }
                Button {
                    text: "+15%"
                    enabled: audio !== null && audio.available
                    onClicked: if (audio) audio.bump(15)
                }
                Item { Layout.fillWidth: true }
            }

            // -- Sink list ----------------------------------------------
            Label {
                text: "sinks"
                color: Tokens.accent
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontMd
                font.bold: true
                Layout.topMargin: Tokens.spacingSm
            }

            Item {
                id: sinksCore
                property var sinks: []
                function reload() {
                    if (!root.audio) { sinks = []; return; }
                    try {
                        sinks = JSON.parse(root.audio.sinks_json || "[]") || [];
                    } catch (e) {
                        sinks = [];
                    }
                }

                Connections {
                    target: root.audio
                    function onSinks_jsonChanged() { sinksCore.reload(); }
                }
                Component.onCompleted: sinksCore.reload()
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: Tokens.spacingXs

                    Label {
                        visible: sinksCore.sinks.length === 0
                        text: "no sinks reported by pactl"
                        color: Tokens.textMuted
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: sinksCore.sinks

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: Tokens.radiusSm
                            color: modelData.default
                                   ? Qt.darker(Tokens.accent, 4.5)
                                   : "transparent"
                            border.color: modelData.default
                                          ? Tokens.accent
                                          : Tokens.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Tokens.spacingSm
                                spacing: Tokens.spacingSm

                                Rectangle {
                                    Layout.preferredWidth: 8
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: modelData.muted ? Tokens.danger : Tokens.success
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.description || modelData.name
                                        color: Tokens.text
                                        font.family: Tokens.fontFamily
                                        font.pixelSize: Tokens.fontSm
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        color: Tokens.textDim
                                        font.family: Tokens.monoFamily
                                        font.pixelSize: Tokens.fontXs
                                        elide: Text.ElideMiddle
                                    }
                                }

                                Label {
                                    text: String(modelData.volume_percent) + "%"
                                    color: Tokens.textMuted
                                    font.family: Tokens.monoFamily
                                    font.pixelSize: Tokens.fontXs
                                    Layout.preferredWidth: 40
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (audio) audio.set_default_sink(modelData.name)
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
