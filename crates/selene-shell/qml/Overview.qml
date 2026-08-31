import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Workspace overview (NothingLess Overview port) -- a grid of the
// current Hyprland workspaces with window counts. Clicking a card
// dispatches `workspace <id>` through the Bridge and closes the
// overlay. Toggled with SUPER+TAB, the sidebar button, or
// `selene run overview`.
Rectangle {
    id: root

    // Injected by Main.qml.
    property var bridge: null
    property var config: null

    // Parsed copy of bridge.workspaces_json.
    property var workspaces: []

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible ? close() : open(); }
    function open() {
        if (bridge && bridge.refresh) bridge.refresh();
        reload();
        visible = true;
        forceActiveFocus();
    }
    function close() { visible = false; }

    function reload() {
        if (!bridge) { workspaces = []; return; }
        try {
            const parsed = JSON.parse(bridge.workspaces_json || "[]");
            workspaces = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            workspaces = [];
        }
    }

    Connections {
        target: root.bridge
        function onWorkspaces_jsonChanged() { root.reload(); }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.barMargin * 4, grid.implicitWidth + Tokens.paddingLg * 2)
        height: Math.min(parent.height - Tokens.barMargin * 4,
                         grid.implicitHeight + header.implicitHeight + Tokens.paddingLg * 2 + Tokens.spacingMd)

        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.92)
        radius: Tokens.radiusLg
        border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.paddingLg
            spacing: Tokens.spacingMd

            RowLayout {
                id: header
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Label {
                    text: "Overview"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: root.workspaces.length + " workspaces"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
            }

            GridLayout {
                id: grid
                Layout.alignment: Qt.AlignHCenter
                columns: root.config && root.config.overview_columns > 0
                         ? root.config.overview_columns : 5
                columnSpacing: Tokens.spacingMd
                rowSpacing: Tokens.spacingMd

                Repeater {
                    model: root.workspaces

                    delegate: Rectangle {
                        id: wsCard
                        required property var modelData

                        implicitWidth: 148
                        implicitHeight: 96
                        radius: Tokens.radiusMd
                        color: wsCard.modelData.active
                               ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.18)
                               : Tokens.surfaceAlt
                        border.width: wsCard.modelData.active ? 2 : 1
                        border.color: wsCard.modelData.active
                                      ? Tokens.accent
                                      : Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)

                        Behavior on color {
                            ColorAnimation { duration: Tokens.durationFast }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Tokens.spacingXs

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: wsCard.modelData.name && wsCard.modelData.name !== String(wsCard.modelData.id)
                                      ? wsCard.modelData.name
                                      : "Workspace " + wsCard.modelData.id
                                color: wsCard.modelData.active ? Tokens.accent : Tokens.text
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontMd
                                font.bold: wsCard.modelData.active
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: (wsCard.modelData.windows || 0)
                                      + (wsCard.modelData.windows === 1 ? " window" : " windows")
                                color: Tokens.textMuted
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontSm
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.bridge)
                                    root.bridge.focus_workspace(wsCard.modelData.id);
                                root.close();
                            }
                        }
                    }
                }

                // Empty state.
                Label {
                    visible: root.workspaces.length === 0
                    text: "No workspaces reported (is Hyprland running?)"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
            }
        }
    }
}
