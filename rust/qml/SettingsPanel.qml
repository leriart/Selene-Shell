import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property var config: null

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
        width: 400

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
                    text: "settings"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "save"
                    enabled: config !== null
                    onClicked: if (config) config.save()
                }
                Button {
                    text: "reload"
                    enabled: config !== null
                    onClicked: if (config) config.reload()
                }
                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            Label {
                Layout.fillWidth: true
                text: config ? config.status : ""
                color: config && config.defaults_used ? Tokens.danger : Tokens.textMuted
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
                elide: Text.ElideRight
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: Tokens.spacingMd

                    // -- Panel ------------------------------------------------
                    Label {
                        text: "panel"
                        color: Tokens.accent
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontMd
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "height"
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            Layout.preferredWidth: 110
                        }
                        SpinBox {
                            from: 24; to: 96
                            value: config ? config.panel_height : 36
                            onValueModified: if (config) config.set_value("panel.height", String(value))
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "position"
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            Layout.preferredWidth: 110
                        }
                        ComboBox {
                            model: ["top", "bottom"]
                            currentIndex: config && config.panel_position === "bottom" ? 1 : 0
                            onActivated: function(i) {
                                if (config) config.set_value("panel.position", i === 1 ? "bottom" : "top")
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "transparent"
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            Layout.preferredWidth: 110
                        }
                        Switch {
                            checked: config ? config.panel_transparent : true
                            onToggled: if (config) config.set_value("panel.transparent", checked ? "true" : "false")
                        }
                    }

                    // -- Launcher ---------------------------------------------
                    Label {
                        text: "launcher"
                        color: Tokens.accent
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontMd
                        font.bold: true
                        Layout.topMargin: Tokens.spacingSm
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "width"
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            Layout.preferredWidth: 110
                        }
                        SpinBox {
                            from: 320; to: 1280; stepSize: 16
                            value: config ? config.launcher_width : 640
                            onValueModified: if (config) config.set_value("launcher.width", String(value))
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "max results"
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            Layout.preferredWidth: 110
                        }
                        SpinBox {
                            from: 4; to: 32
                            value: config ? config.launcher_max_results : 8
                            onValueModified: if (config) config.set_value("launcher.max_results", String(value))
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "show icons"
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            Layout.preferredWidth: 110
                        }
                        Switch {
                            checked: config ? config.launcher_show_icons : true
                            onToggled: if (config) config.set_value("launcher.show_icons", checked ? "true" : "false")
                        }
                    }

                    // -- Theme ------------------------------------------------
                    Label {
                        text: "theme"
                        color: Tokens.accent
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontMd
                        font.bold: true
                        Layout.topMargin: Tokens.spacingSm
                    }

                    Repeater {
                        model: [
                            { label: "accent", key: "theme.accent" },
                            { label: "background", key: "theme.background" },
                            { label: "surface", key: "theme.surface" }
                        ]

                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            Label {
                                text: modelData.label
                                color: Tokens.textMuted
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontSm
                                Layout.preferredWidth: 110
                            }

                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 4
                                border.color: Tokens.border
                                border.width: 1
                                color: {
                                    if (!config) return "transparent";
                                    if (modelData.key === "theme.accent") return config.theme_accent;
                                    if (modelData.key === "theme.background") return config.theme_background;
                                    return config.theme_surface;
                                }
                            }

                            TextField {
                                Layout.fillWidth: true
                                font.family: Tokens.monoFamily
                                font.pixelSize: Tokens.fontSm
                                text: {
                                    if (!config) return "";
                                    if (modelData.key === "theme.accent") return config.theme_accent;
                                    if (modelData.key === "theme.background") return config.theme_background;
                                    return config.theme_surface;
                                }
                                onEditingFinished: if (config) config.set_value(modelData.key, text)
                            }
                        }
                    }

                    // -- Font -------------------------------------------------
                    Label {
                        text: "font"
                        color: Tokens.accent
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontMd
                        font.bold: true
                        Layout.topMargin: Tokens.spacingSm
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "family"
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            Layout.preferredWidth: 110
                        }
                        TextField {
                            Layout.fillWidth: true
                            text: config ? config.font_family : ""
                            font.pixelSize: Tokens.fontSm
                            onEditingFinished: if (config) config.set_value("font.family", text)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: "size"
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            Layout.preferredWidth: 110
                        }
                        SpinBox {
                            from: 8; to: 32
                            value: config ? config.font_size : 13
                            onValueModified: if (config) config.set_value("font.size", String(value))
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
