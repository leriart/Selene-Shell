import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Workspace overview (NothingLess Overview port) -- a grid of the
// current Hyprland workspaces. Each card renders the workspace number
// plus up to four "window tiles" (class + title) from the live
// `windows_json` the Bridge pulls from `hyprctl clients -j`. Clicking
// a card dispatches `workspace <id>` and closes the overlay.
//
// Toggled with SUPER+TAB, the sidebar button, or `selene run overview`.
Rectangle {
    id: root

    // Injected by Main.qml.
    property var bridge: null
    property var config: null

    // Parsed copies of bridge state.
    property var workspaces: []
    property var windows: []

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
        if (!bridge) { workspaces = []; windows = []; return; }
        try {
            const ws = JSON.parse(bridge.workspaces_json || "[]");
            workspaces = Array.isArray(ws) ? ws : [];
        } catch (e) {
            workspaces = [];
        }
        try {
            const w = JSON.parse(bridge.windows_json || "[]");
            windows = Array.isArray(w) ? w : [];
        } catch (e) {
            windows = [];
        }
    }

    // Windows on a given workspace id, capped at 6 per card.
    function windowsOn(wsId) {
        const out = [];
        for (let i = 0; i < windows.length; ++i) {
            if (windows[i].workspace_id === wsId) {
                out.push(windows[i]);
                if (out.length >= 6) break;
            }
        }
        return out;
    }

    Connections {
        target: root.bridge
        function onWorkspaces_jsonChanged() { root.reload(); }
        function onWindows_jsonChanged() { root.reload(); }
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
                        required property int index

                        implicitWidth: 160
                        implicitHeight: 112
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

                        // Workspace label + window tiles.
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            Label {
                                Layout.alignment: Qt.AlignLeft
                                text: wsCard.modelData.name
                                      && wsCard.modelData.name !== String(wsCard.modelData.id)
                                      ? wsCard.modelData.name
                                      : "Workspace " + wsCard.modelData.id
                                color: wsCard.modelData.active ? Tokens.accent : Tokens.text
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontSm
                                font.bold: wsCard.modelData.active
                                elide: Text.ElideRight
                            }

                            // Window tiles: class glyph + short title.
                            Repeater {
                                model: root.windowsOn(wsCard.modelData.id)
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 18
                                    radius: 4
                                    color: Qt.rgba(1, 1, 1, 0.06)

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        Label {
                                            width: 20
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.class
                                                  ? modelData.class.charAt(0).toUpperCase()
                                                  : "?"
                                            color: Tokens.accent
                                            font.family: Tokens.monoFamily
                                            font.pixelSize: Tokens.fontXs
                                        }
                                        Label {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 32
                                            text: modelData.title || modelData.class || "window"
                                            color: Tokens.textMuted
                                            font.family: Tokens.fontFamily
                                            font.pixelSize: Tokens.fontXs
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            // Window count footer.
                            Item { Layout.fillHeight: true }
                            Label {
                                Layout.alignment: Qt.AlignRight
                                text: (wsCard.modelData.windows || 0)
                                      + " window" + (wsCard.modelData.windows === 1 ? "" : "s")
                                color: Tokens.textDim
                                font.family: Tokens.monoFamily
                                font.pixelSize: Tokens.fontXs
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