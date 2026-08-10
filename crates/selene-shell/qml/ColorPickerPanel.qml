import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Color picker (Ambxst feature). Spawns `hyprpicker` to freeze the
// screen and grab a pixel. The picked hex is shown in a preview card
// along with HSV / RGB approximations for quick cross-checking.
Rectangle {
    id: root

    property var picker: null

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
        width: 380

        color: Tokens.surface
        radius: Tokens.radiusLg
        border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "color picker"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Button { text: "x"; onClicked: root.close() }
            }

            Label {
                Layout.fillWidth: true
                text: picker ? picker.status : ""
                color: Tokens.textMuted
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
                elide: Text.ElideRight
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Tokens.spacingMd

                    // Big swatch
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 220
                        radius: Tokens.radiusLg
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        color: {
                            if (picker && picker.color_hex.length > 0)
                                return picker.color_hex;
                            return "transparent";
                        }

                        // Empty-state hint overlay
                        Label {
                            anchors.centerIn: parent
                            visible: !picker || picker.color_hex.length === 0
                            text: picker && !picker.enabled
                                  ? "hyprpicker not installed"
                                  : "no color picked yet"
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                        }
                    }

                    // Hex readout
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: picker ? picker.color_hex : ""
                        color: Tokens.text
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontLg
                    }

                    // RGB / HSL helpers
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        visible: picker && picker.color_hex.length > 0

                        RowLayout {
                            anchors.fill: parent
                            spacing: Tokens.spacingSm

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Tokens.radiusSm
                                color: Tokens.surfaceAlt
                                border.color: Tokens.border
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.spacingSm

                                    Label {
                                        text: "R"
                                        color: Tokens.textMuted
                                        font.family: Tokens.monoFamily
                                        font.pixelSize: Tokens.fontXs
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignRight
                                        text: root.rgb("r")
                                        color: Tokens.text
                                        font.family: Tokens.monoFamily
                                        font.pixelSize: Tokens.fontSm
                                    }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Tokens.radiusSm
                                color: Tokens.surfaceAlt
                                border.color: Tokens.border
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.spacingSm

                                    Label {
                                        text: "G"
                                        color: Tokens.textMuted
                                        font.family: Tokens.monoFamily
                                        font.pixelSize: Tokens.fontXs
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignRight
                                        text: root.rgb("g")
                                        color: Tokens.text
                                        font.family: Tokens.monoFamily
                                        font.pixelSize: Tokens.fontSm
                                    }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Tokens.radiusSm
                                color: Tokens.surfaceAlt
                                border.color: Tokens.border
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.spacingSm

                                    Label {
                                        text: "B"
                                        color: Tokens.textMuted
                                        font.family: Tokens.monoFamily
                                        font.pixelSize: Tokens.fontXs
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignRight
                                        text: root.rgb("b")
                                        color: Tokens.text
                                        font.family: Tokens.monoFamily
                                        font.pixelSize: Tokens.fontSm
                                    }
                                }
                            }
                        }
                    }

                    // Action buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        Button {
                            Layout.fillWidth: true
                            text: picker && picker.running
                                  ? "picking..." : "pick"
                            enabled: picker !== null && picker.enabled && !picker.running
                            onClicked: if (picker) picker.pick()
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "pick + copy"
                            enabled: picker !== null && picker.enabled && !picker.running
                            onClicked: if (picker) picker.pick_and_copy()
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // Helpers
    function hexToInt(hex) {
        if (!hex || hex.length < 7) return 0;
        return parseInt(hex.substring(1, 3), 16);
    }

    function rgb(ch) {
        if (!picker || !picker.color_hex || picker.color_hex.length < 7) return "-";
        const off = (ch === "r") ? 1 : (ch === "g") ? 3 : 5;
        return String(parseInt(picker.color_hex.substring(off, off + 2), 16));
    }
}
