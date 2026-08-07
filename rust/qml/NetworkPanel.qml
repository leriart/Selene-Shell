import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property var network: null

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible = !visible; }
    function open() { visible = true; }
    function close() { visible = false; }

    function selectedPassword() {
        return passwordField.text;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.barMargin
        width: 380

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
                    text: "network"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Switch {
                    text: "wifi"
                    checked: network ? network.wifi_enabled : false
                    enabled: network !== null && network.available
                    onToggled: {
                        if (network) {
                            if (checked) network.wifi_on();
                            else network.wifi_off();
                        }
                    }
                }

                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            Label {
                Layout.fillWidth: true
                text: network ? network.status : ""
                color: network && network.available ? Tokens.textMuted : Tokens.danger
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: Tokens.radiusSm
                color: Tokens.surfaceAlt
                border.color: Tokens.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingSm
                    spacing: 0

                    Label {
                        Layout.fillWidth: true
                        text: network ? (network.active_ssid || network.active_name || "(no active connection)") : ""
                        color: Tokens.text
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: network ? (network.ipv4 || (network.connected ? "(no IPv4)" : "")) : ""
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Button {
                    text: "disconnect"
                    enabled: network && network.connected
                    onClicked: if (network) network.disconnect()
                }
                Button {
                    text: "refresh"
                    enabled: network !== null
                    onClicked: if (network) network.refresh()
                }
                Item { Layout.fillWidth: true }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            Label {
                text: "nearby wifi"
                color: Tokens.accent
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontMd
                font.bold: true
            }

            Item {
                id: wifiCore
                property var networks: []
                function reload() {
                    if (!root.network) { networks = []; return; }
                    try {
                        networks = JSON.parse(root.network.wifi_json || "[]") || [];
                    } catch (e) {
                        networks = [];
                    }
                }

                Connections {
                    target: root.network
                    function onWifi_jsonChanged() { wifiCore.reload(); }
                }
                Component.onCompleted: wifiCore.reload()
            }

            TextField {
                id: passwordField
                Layout.fillWidth: true
                placeholderText: "wifi password (if needed)"
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
                echoMode: TextInput.Password
                visible: false
            }

            RowLayout {
                visible: wifiCore.networks.length > 0
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Button {
                    text: keyField.text || "use password"
                    onClicked: {
                        keyField.visible = !keyField.visible;
                        passwordField.visible = keyField.visible;
                    }
                }
                TextField {
                    id: keyField
                    visible: false
                    Layout.fillWidth: true
                    placeholderText: "password"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    echoMode: TextInput.Password
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: Tokens.spacingXs

                    Label {
                        visible: wifiCore.networks.length === 0
                        text: network && network.wifi_enabled
                              ? "no networks visible"
                              : "wifi off -- toggle to scan"
                        color: Tokens.textMuted
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: wifiCore.networks

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: Tokens.radiusSm
                            color: modelData.in_use
                                   ? Qt.darker(Tokens.accent, 4.5)
                                   : "transparent"
                            border.color: modelData.in_use
                                          ? Tokens.accent
                                          : Tokens.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Tokens.spacingSm
                                spacing: Tokens.spacingSm

                                Label {
                                    text: modelData.bars || "▂"
                                    color: Tokens.accent
                                    font.family: Tokens.monoFamily
                                    font.pixelSize: Tokens.fontSm
                                    Layout.preferredWidth: 32
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.ssid
                                    color: Tokens.text
                                    font.family: Tokens.fontFamily
                                    font.pixelSize: Tokens.fontSm
                                    elide: Text.ElideRight
                                }
                                Label {
                                    text: (modelData.security && modelData.security !== "--")
                                          ? "🔒"
                                          : ""
                                    color: Tokens.textMuted
                                    font.family: Tokens.fontFamily
                                    font.pixelSize: Tokens.fontSm
                                }
                                Label {
                                    text: (modelData.signal || "0") + "%"
                                    color: Tokens.textMuted
                                    font.family: Tokens.monoFamily
                                    font.pixelSize: Tokens.fontXs
                                    Layout.preferredWidth: 36
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (network) {
                                        let pwd = keyField.visible ? keyField.text : passwordField.text;
                                        network.connect_ssid(modelData.ssid, pwd);
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
