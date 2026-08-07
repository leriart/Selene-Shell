import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property var wallpaper: null

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() {
        visible = !visible;
        if (visible && wallpaper) wallpaper.refresh();
    }
    function open() {
        visible = true;
        if (wallpaper) wallpaper.refresh();
    }
    function close() { visible = false; }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.barMargin * 4, 720)
        height: Math.min(parent.height - Tokens.barMargin * 4, 520)

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
                spacing: Tokens.spacingSm

                Label {
                    text: "wallpapers"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: wallpaper ? (String(wallpaper.current_index + 1) + " / " + grid.count) : ""
                    color: Tokens.textMuted
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontSm
                    visible: wallpaper && wallpaper.available
                }

                Button {
                    text: "<"
                    enabled: wallpaper !== null && wallpaper.available
                    onClicked: wallpaper.previous_wall()
                }
                Button {
                    text: ">"
                    enabled: wallpaper !== null && wallpaper.available
                    onClicked: wallpaper.next_wall()
                }
                Button {
                    text: "rescan"
                    enabled: wallpaper !== null
                    onClicked: wallpaper.refresh()
                }
                Button {
                    text: "x"
                    onClicked: root.close()
                }
            }

            Label {
                Layout.fillWidth: true
                text: wallpaper ? wallpaper.directory : ""
                color: Tokens.textDim
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
                elide: Text.ElideMiddle
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Tokens.border }

            Item {
                id: modelCore
                property var entries: []

                function reload() {
                    if (!root.wallpaper) { entries = []; return; }
                    try {
                        entries = JSON.parse(root.wallpaper.paths_json || "[]") || [];
                    } catch (e) {
                        entries = [];
                    }
                }

                Connections {
                    target: root.wallpaper
                    function onPaths_jsonChanged() { modelCore.reload(); }
                }
                Component.onCompleted: modelCore.reload()
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacingLg
                visible: modelCore.entries.length === 0
                text: "no wallpapers found in " + (wallpaper ? wallpaper.directory : "?")
                color: Tokens.textMuted
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 164
                cellHeight: 124
                model: modelCore.entries

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: grid.cellWidth - 8
                    height: grid.cellHeight - 8
                    radius: Tokens.radiusSm
                    color: Tokens.surfaceAlt
                    border.color: wallpaper && wallpaper.current_path === modelData.path
                                  ? Tokens.accent : Tokens.border
                    border.width: wallpaper && wallpaper.current_path === modelData.path ? 2 : 1

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        anchors.bottomMargin: 22
                        source: modelData.kind === "image"
                                ? "file://" + modelData.path : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: modelData.kind === "image"
                    }

                    Label {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -10
                        visible: modelData.kind !== "image"
                        text: modelData.kind === "video" ? "video" : "gif"
                        color: Tokens.accent
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontMd
                        font.bold: true
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        text: modelData.name
                        color: Tokens.textMuted
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontXs
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: if (wallpaper) wallpaper.pick_index(index)
                    }
                }
            }
        }
    }
}
