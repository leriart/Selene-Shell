import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Clipboard history panel (Ambxst). Reads from the `cliphist` CLI which
// keeps a sqlite cache of recent clipboard entries; this panel just
// renders the JSON the Rust QObject hands us and forwards clicks back
// to `clipboard.pick(id)` which writes the entry back to the system
// clipboard (wl-copy / xclip / xsel).
Rectangle {
    id: root

    property var clipboard: null

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible = !visible; refresh() }
    function open() { visible = true; refresh() }
    function close() { visible = false; }

    function refresh() {
        if (clipboard) clipboard.refresh()
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
        width: 360

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
                spacing: Tokens.spacingSm

                Label {
                    text: "clipboard"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: clipboard ? String(clipboard.total) + " entries" : ""
                    color: Tokens.textMuted
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                }

                Button {
                    text: "wipe"
                    enabled: clipboard !== null && clipboard.total > 0
                    onClicked: if (clipboard) clipboard.wipe()
                }

                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            Label {
                Layout.fillWidth: true
                text: clipboard ? clipboard.running_status : "loading"
                color: Tokens.textMuted
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
                elide: Text.ElideRight
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacingLg
                visible: clipboard && !clipboard.is_enabled()
                text: "cliphist not installed\nInstall with your package manager\n(Arch: cliphist, Fedora: cliphist)"
                color: Tokens.textMuted
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
                horizontalAlignment: Text.AlignHCenter
            }

            Item {
                id: itemsCore
                property var entries: []
                function reload() {
                    if (!root.clipboard) { entries = []; return; }
                    try { entries = JSON.parse(root.clipboard.items_json || "[]") || []; }
                    catch (e) { entries = []; }
                }
                Connections {
                    target: root.clipboard
                    function onItems_jsonChanged() { itemsCore.reload() }
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: itemsCore.entries.length > 0

                ColumnLayout {
                    width: parent.width
                    spacing: Tokens.spacingXs

                    Repeater {
                        model: itemsCore.entries
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            radius: Tokens.radiusSm
                            color: mouseArea.containsMouse
                                   ? Qt.rgba(1, 1, 1, 0.06)
                                   : "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Tokens.spacingSm
                                spacing: 2

                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.preview || ""
                                    color: Tokens.text
                                    font.family: Tokens.fontFamily
                                    font.pixelSize: Tokens.fontSm
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.WordWrap
                                }

                                Label {
                                    text: "#" + modelData.id
                                    color: Tokens.textDim
                                    font.family: Tokens.monoFamily
                                    font.pixelSize: Tokens.fontXs
                                }
                            }

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        if (root.clipboard)
                                            root.clipboard.remove(modelData.id);
                                    } else {
                                        if (root.clipboard) {
                                            root.clipboard.pick(modelData.id);
                                            root.close();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Show a "click to copy" hint at the bottom of an empty
            // populated list (cliphist reachable but empty).
            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: clipboard && clipboard.is_enabled() && itemsCore.entries.length === 0
                text: "no history yet -- copy something"
                color: Tokens.textMuted
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
            }
        }
    }
}
