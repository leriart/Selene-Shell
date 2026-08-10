import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// Bottom floating dock (NothingLess). Shows up to 8 frequent apps from
// Spawner launch statistics. The dock appears at the center bottom and
// hides behind a background glass rectangle.
Rectangle {
    id: dock

    property var spawner: null

    implicitWidth: Math.min(560, parent ? parent.width - 120 : 560)
    implicitHeight: 52
    radius: Tokens.radiusXl

    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.55)
    border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
    border.width: 1

    // Backdrop blur
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 0.6
        saturation: 1.2
        opacity: 0.92
    }

    // The key item: a top-apps model pulled from spawner stats.
    RowLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        // Fallback when no apps data is available
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            color: "transparent"
            visible: appsRepeater.count === 0
            MouseArea { anchors.fill: parent; onClicked: dock.refreshModel() }
        }

        Repeater {
            id: appsRepeater
            model: dock._model

            delegate: Rectangle {
                required property var modelData
                width: 40
                height: 40
                radius: Tokens.radiusSm
                color: hoverArea.containsMouse
                       ? Qt.rgba(1, 1, 1, 0.08)
                       : "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.10)
                border.width: 1

                Label {
                    anchors.centerIn: parent
                    text: modelData.label ? modelData.label.charAt(0).toUpperCase() : "?"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                    font.bold: true
                }

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (dock.spawner && modelData.exec)
                            dock.spawner.launch(modelData.exec)
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

    // Internal model built from spawner.stats_json. We parse it on
    // each dock.open and cache the top N entries.
    property var _model: []

    function refreshModel() {
        if (!spawner) { _model = []; return; }
        try {
            var apps = JSON.parse(spawner.apps_json || "[]");
            // Filter to apps with weight > 0, sort by weight desc
            var ranked = apps.filter(function(a) { return (a.weight || 0) > 0; });
            ranked.sort(function(a, b) { return (b.weight || 0) - (a.weight || 0); });
            _model = ranked.slice(0, 8);
        } catch (e) {
            _model = [];
        }
    }

    onSpawnerChanged: refreshModel()
    Component.onCompleted: refreshModel()
}
