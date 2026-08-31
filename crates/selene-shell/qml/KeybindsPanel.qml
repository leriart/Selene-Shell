import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Keybind cheatsheet (Ambxst/NothingLess binds viewer port) -- renders
// the `binds` list from init.lua as a two-column grid of key -> action
// chips. The list is user-editable, so this panel doubles as live
// documentation of the user's own config. Opened with
// `selene run binds` or SUPER + / in a real session.
Rectangle {
    id: root

    property var config: null

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible ? close() : open(); }
    function open() {
        visible = true;
        rebuild();
        forceActiveFocus();
    }
    function close() { visible = false; }

    // binds_json is ["SUPER + D -> dashboard", ...]; split each entry
    // into {key, action} for the two-column layout. Entries without a
    // "->" separator show as-is in the action column.
    property var parsed: []

    function rebuild() {
        const out = [];
        try {
            const raw = JSON.parse(config ? config.binds_json : "[]");
            for (const entry of raw) {
                const s = String(entry);
                const idx = s.indexOf("->");
                if (idx >= 0) {
                    out.push({
                        key: s.slice(0, idx).trim(),
                        action: s.slice(idx + 2).trim()
                    });
                } else {
                    out.push({ key: "", action: s });
                }
            }
        } catch (e) {
            // Malformed JSON: leave the panel empty rather than crash.
        }
        parsed = out;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.barMargin * 4, 640)
        height: Math.min(parent.height - Tokens.barMargin * 4,
                         column.implicitHeight + Tokens.paddingLg * 2)

        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.94)
        radius: Tokens.radiusLg
        border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.paddingLg
            spacing: Tokens.spacingMd

            Label {
                text: "Keybinds"
                color: Tokens.text
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontLg
                font.bold: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(grid.implicitHeight, 420)
                contentHeight: grid.implicitHeight
                clip: true

                GridLayout {
                    id: grid
                    width: parent.width
                    columns: 2
                    columnSpacing: Tokens.spacingMd
                    rowSpacing: Tokens.spacingSm

                    Repeater {
                        model: root.parsed
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            // Key chip -- fixed-width, monospace.
                            Rectangle {
                                visible: modelData.key.length > 0
                                Layout.preferredHeight: 26
                                Layout.preferredWidth: Math.min(
                                    keyLabel.implicitWidth + Tokens.paddingMd * 2, 170)
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.color: Qt.rgba(1, 1, 1, 0.14)
                                border.width: 1

                                Label {
                                    id: keyLabel
                                    anchors.centerIn: parent
                                    text: modelData.key
                                    color: Tokens.accent
                                    font.family: Tokens.monoFamily
                                    font.pixelSize: Tokens.fontXs
                                    elide: Text.ElideRight
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                text: modelData.action
                                color: Tokens.text
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontSm
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Label {
                visible: root.parsed.length === 0
                text: "No binds configured -- add `binds` entries to init.lua."
                color: Tokens.textMuted
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    Keys.onEscapePressed: root.close()
}
