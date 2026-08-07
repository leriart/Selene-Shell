import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property var bluetooth: null

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
                    text: "bluetooth"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Switch {
                    text: "power"
                    checked: bluetooth ? bluetooth.powered : false
                    enabled: bluetooth !== null && bluetooth.available
                    onToggled: if (bluetooth) bluetooth.toggle()
                }

                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            Label {
                Layout.fillWidth: true
                text: bluetooth ? (bluetooth.adapter_name || "(no adapter)") : ""
                color: Tokens.textMuted
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
            }
            Label {
                Layout.fillWidth: true
                text: bluetooth ? bluetooth.status : ""
                color: bluetooth && bluetooth.available ? Tokens.textMuted : Tokens.danger
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
                elide: Text.ElideRight
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            Item {
                id: btCore
                property var devices: []
                function reload() {
                    if (!root.bluetooth) { devices = []; return; }
                    try {
                        devices = JSON.parse(root.bluetooth.devices_json || "[]") || [];
                    } catch (e) {
                        devices = [];
                    }
                }

                Connections {
                    target: root.bluetooth
                    function onDevices_jsonChanged() { btCore.reload(); }
                }
                Component.onCompleted: btCore.reload()
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: Tokens.spacingXs

                    Label {
                        visible: btCore.devices.length === 0
                        text: bluetooth && bluetooth.powered
                              ? "no paired devices"
                              : "powered off"
                        color: Tokens.textMuted
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: btCore.devices

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            radius: Tokens.radiusSm
                            color: modelData.connected
                                   ? Qt.darker(Tokens.accent, 4.5)
                                   : "transparent"
                            border.color: modelData.connected
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
                                    color: modelData.connected
                                           ? Tokens.success
                                           : (modelData.paired ? Tokens.textMuted : Tokens.border)
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Label {
                                        Layout.fillWidth: true
                                        text: modelData.name || modelData.mac
                                        color: Tokens.text
                                        font.family: Tokens.fontFamily
                                        font.pixelSize: Tokens.fontSm
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: (modelData.device_type || "") + " · " +
                                              (modelData.paired ? "paired" : "unpaired")
                                        color: Tokens.textDim
                                        font.family: Tokens.monoFamily
                                        font.pixelSize: Tokens.fontXs
                                        elide: Text.ElideRight
                                    }
                                }

                                Button {
                                    text: modelData.connected ? "drop" : "pair"
                                    enabled: bluetooth !== null && bluetooth.available
                                    onClicked: if (bluetooth) {
                                        if (modelData.connected) {
                                            bluetooth.disconnect_device(modelData.mac);
                                        } else if (modelData.paired) {
                                            bluetooth.connect_device(modelData.mac);
                                        } else {
                                            bluetooth.pair_device(modelData.mac);
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: bluetooth !== null && bluetooth.available
                                onClicked: if (bluetooth) {
                                    if (modelData.connected) {
                                        bluetooth.disconnect_device(modelData.mac);
                                    } else if (modelData.paired) {
                                        bluetooth.connect_device(modelData.mac);
                                    } else {
                                        bluetooth.pair_device(modelData.mac);
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
