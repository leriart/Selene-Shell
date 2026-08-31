import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// IslandPill.qml -- the orbital dock of Selene.
//
// When collapsed, the pill collapses into a single circular island:
// the central Moon with 4 satellites in low orbit. The satellites
// represent live status (media, battery, network, CPU) and each lights
// up when the relevant signal crosses a threshold. The whole rig
// rotates at the preset's `orbitAngularVelocity`, giving the dock a
// subtle "breathing" feel without distracting from active apps.
//
// On click, the island expands into the existing dashboard with the
// metrics / media / weather tabs.
Item {
    id: root

    // External API -- unchanged so Main.qml keeps working.
    property var islandSource: null
    property var visualizer: null
    property var network: null
    property var audio: null
    property var state: null
    property var resources: null
    property var weather: null

    // Notify trigger: when this increments, fire a MoonPulse wave.
    property int notifyCounter: 0
    onNotifyCounterChanged: if (notifyCounter > 0) pulse.fire()

    property bool cardExpanded: false

    readonly property real _collapsedSize: 128 * Tokens.moonRadiusScale
    readonly property real _expandedW: 540
    readonly property real _expandedH: 340

    implicitWidth:  cardExpanded ? _expandedW  : _collapsedSize
    implicitHeight: cardExpanded ? _expandedH : _collapsedSize

    width: implicitWidth
    height: implicitHeight

    Behavior on implicitWidth  { NumberAnimation { duration: Tokens.durationSlow; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: Tokens.durationSlow; easing.type: Easing.OutCubic } }

    property bool hoverState: false

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: cardExpanded = !cardExpanded
        onEntered: hoverState = true
        onExited:  hoverState = false
    }

    // -- Collapsed: the orbital dock ---------------------------------
    Item {
        anchors.fill: parent
        visible: !root.cardExpanded

        // Orbit trace -- rendered as a single border-only rectangle
        // scaled to a circle. Cheaper than a Shape for a static-ish
        // trace and doesn't crash with rapid layout changes.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.72
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g,
                                  Tokens.accent.b, Tokens.orbitTraceAlpha)
            border.width: 1
        }

        // Halo -- single soft ring around the moon.
        Rectangle {
            anchors.centerIn: parent
            width: 56 * Tokens.moonRadiusScale
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g,
                                  Tokens.accent.b,
                                  Math.min(1, Tokens.moonHaloAlpha))
            border.width: 1.4
            opacity: root.hoverState ? 1.0 : 0.6
            Behavior on opacity { NumberAnimation { duration: Tokens.durationSlow } }
        }

        // Central moon (Rectangle -- Shape paths can crash with
        // rapid parent resizes in offscreen mode).
        Rectangle {
            id: centralMoon
            anchors.centerIn: parent
            width: 36 * Tokens.moonRadiusScale
            height: width
            radius: width / 2
            color: Tokens.text
            border.color: Tokens.accent
            border.width: 2
            opacity: 0.95
            z: 2
            Behavior on width { NumberAnimation { duration: Tokens.durationSlow } }
        }

        // Satellites -- rotated by NumberAnimation on the parent
        // container; each satellite lives at its own static offset.
        Item {
            id: satContainer
            anchors.fill: parent
            rotation: 0
            NumberAnimation on rotation {
                running: Tokens.orbitsRotate
                from: 0; to: 360
                loops: Animation.Infinite
                duration: 360000 / Math.max(0.5,
                                            Math.abs(Tokens.orbitAngularVelocity))
            }
            Repeater {
                model: 4
                delegate: Item {
                    required property int index
                    readonly property real orbitR: parent.width * 0.36
                    x: parent.width / 2
                        + Math.cos(index * Math.PI / 2) * orbitR - width / 2
                    y: parent.height / 2
                        + Math.sin(index * Math.PI / 2) * orbitR - height / 2
                    width: 14; height: 14
                    readonly property bool mediaOn: index === 0
                        && root.islandSource && root.islandSource.media_playing
                    readonly property bool batLow: index === 1
                        && root.islandSource && root.islandSource.battery_present
                        && root.islandSource.battery_percent < 20
                    readonly property bool netUp:  index === 2
                        && root.network && root.network.connected
                    readonly property bool cpuHot: index === 3
                        && root.resources && root.resources.cpu_usage > 0.75
                    readonly property color satColor:
                          index === 0 ? Tokens.success
                        : index === 1 ? Tokens.danger
                        : index === 2 ? Tokens.accent
                                      : Tokens.textMuted
                    readonly property bool active:
                          mediaOn || batLow || netUp || cpuHot

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: parent.satColor
                        border.color: Qt.lighter(parent.satColor, 1.4)
                        border.width: 1
                        opacity: parent.active ? 1.0 : 0.45
                        Behavior on opacity { NumberAnimation { duration: Tokens.duration } }
                        scale: parent.active ? 1.0 : 0.7
                        Behavior on scale { NumberAnimation { duration: Tokens.duration } }
                    }
                }
            }
        }

        // Pulse wave -- three concentric expanding rectangles fired
        // on `pulse.fire()` (called from onNotifyCounterChanged).
        Item {
            id: pulse
            anchors.fill: parent

            property bool busy: false

            function fire() {
                if (busy) return;
                busy = true;
                w1._fire();
                w2._fire();
                w3._fire();
                busyTimer.restart();
            }

            Timer {
                id: busyTimer
                interval: 1600
                repeat: false
                onTriggered: pulse.busy = false
            }

            component Wave: Rectangle {
                id: waveRoot
                property int _delay: 0
                property color _color: Tokens.accent

                width: 28; height: 28; radius: 14
                color: "transparent"
                border.color: _color
                border.width: 1.6
                opacity: 0.0
                x: parent.width / 2 - width / 2
                y: parent.height / 2 - height / 2

                function _fire() {
                    width = 28;
                    height = 28;
                    opacity = 0;
                    x = parent.width / 2 - width / 2;
                    y = parent.height / 2 - height / 2;
                    _delayTimer.interval = _delay;
                    _delayTimer.restart();
                }

                Timer {
                    id: _delayTimer
                    repeat: false
                    onTriggered: {
                        waveRoot._fade.restart();
                        waveRoot._grow.restart();
                    }
                }

                SequentialAnimation on opacity {
                    id: _fade
                    running: false
                    NumberAnimation { from: 0; to: 0.7; duration: 120 }
                    NumberAnimation { from: 0.7; to: 0; duration: 1280 }
                }
                NumberAnimation on width {
                    id: _grow
                    running: false
                    from: 28
                    to: parent.width * 0.95
                    duration: 1400
                    easing.type: Easing.OutCubic
                    onRunningChanged: if (running) {
                        waveRoot.height = waveRoot.width;
                        waveRoot.x = parent.width / 2 - waveRoot.width / 2;
                        waveRoot.y = parent.height / 2 - waveRoot.height / 2;
                    }
                }
            }

            Wave { id: w1; _delay: 0;    }
            Wave { id: w2; _delay: 200;  }
            Wave { id: w3; _delay: 400;  }
        }
    }

    // -- Expanded: the full dashboard card ---------------------------
    Item {
        anchors.fill: parent
        visible: root.cardExpanded

        Rectangle {
            id: expandedCard
            anchors.fill: parent
            radius: Tokens.radiusLg
            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g,
                           Tokens.surface.b, 0.94)
            border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
            border.width: 1

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            MultiEffect {
                anchors.fill: parent
                source: wallpaper
                blurEnabled: true
                blur: 0.6
                saturation: 1.15
                opacity: 0.88
            }

            // Decorative orbital ring drawn behind the metrics so the
            // lunar theme is preserved when expanded.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.92
                height: width
                radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(Tokens.accent.r, Tokens.accent.g,
                                      Tokens.accent.b,
                                      Tokens.orbitTraceAlpha * 0.4)
                border.width: 1
                NumberAnimation on rotation {
                    running: Tokens.orbitsRotate
                    from: 0; to: 360
                    loops: Animation.Infinite
                    duration: 360000 / Math.max(0.5,
                                                Math.abs(Tokens.orbitAngularVelocity) * 0.4)
                }
            }

            GridLayout {
                anchors.fill: parent
                anchors.margins: Tokens.paddingLg
                columns: 3
                rowSpacing: Tokens.spacingMd
                columnSpacing: Tokens.spacingMd

                Label {
                    text: root.islandSource && root.islandSource.media_title
                          ? root.islandSource.media_title
                          : "selene"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                    Layout.columnSpan: 3
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Item {
                    id: mediaBlock
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90

                    readonly property var bars: {
                        if (!root.visualizer || !root.visualizer.bars_json)
                            return [];
                        try { return JSON.parse(root.visualizer.bars_json); }
                        catch (e) { return []; }
                    }

                    Label {
                        text: root.islandSource && root.islandSource.media_playing
                              ? "\u25B6 playing" : "\u23F8 idle"
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }

                    Row {
                        anchors.bottom: parent.bottom
                        spacing: 2

                        Repeater {
                            model: mediaBlock.bars.length > 0
                                   ? mediaBlock.bars.length : 28
                            delegate: Rectangle {
                                required property int index
                                width: 3
                                height: mediaBlock.bars.length > 0
                                        ? 4 + (mediaBlock.bars[index] || 0) * 26
                                        : 6
                                color: Tokens.accent
                                radius: 1
                                opacity: 0.9
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        text: "cpu " + (root.resources
                                ? Math.round(root.resources.cpu_usage * 100) + "%"
                                : "--")
                        color: Tokens.text
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }
                    Label {
                        text: "ram " + (root.resources
                                ? Math.round(root.resources.ram_usage * 100) + "%"
                                : "--")
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        text: root.islandSource && root.islandSource.battery_present
                              ? "\u26A1 " + root.islandSource.battery_percent + "%"
                              : ""
                        color: Tokens.text
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }
                    Label {
                        text: root.weather && root.weather.available
                              ? "\u00B0" + Math.round(root.weather.temp) + " " + root.weather.weather_desc
                              : ""
                        color: Tokens.textMuted
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
