import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Central hub panel (NothingLess Dashboard port) -- one overlay with
// four tabs instead of four separate panels:
//
//   Controls   quick toggles: audio / network / bluetooth /
//              brightness / power profile
//   Metrics    CPU / RAM / GPU / disk gauges (SystemResources)
//   Wallpapers the existing WallpaperPicker grid, embedded
//   Weather    current conditions + forecast (Weather)
//
// Toggled by SUPER+D, the sidebar button, or `selene run dashboard`.
Rectangle {
    id: root

    // Backend references, injected by Main.qml.
    property var audio: null
    property var network: null
    property var bluetooth: null
    property var brightness: null
    property var powerProfile: null
    property var resources: null
    property var weather: null
    property var wallpaper: null
    property var config: null
    property var notifier: null
    property var nightLight: null
    property var screenshot: null

    property int currentTab: 0

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible ? close() : open(); }
    function open() {
        visible = true;
        if (brightness) brightness.refresh();
        if (powerProfile) powerProfile.refresh();
        if (resources) resources.start_polling();
        if (nightLight) nightLight.refresh();
        if (screenshot) screenshot.refresh();
        forceActiveFocus();
    }
    function close() { visible = false; }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.barMargin * 4,
                        root.config ? root.config.dashboard_width : 920)
        height: Math.min(parent.height - Tokens.barMargin * 4, 560)

        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.92)
        radius: Tokens.radiusLg
        border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.paddingLg
            spacing: Tokens.spacingMd

            // -- Tab strip ------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Label {
                    text: "Dashboard"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Repeater {
                    model: ["Controls", "Metrics", "Wallpapers", "Weather"]
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: tabLabel.implicitWidth + Tokens.paddingMd * 2
                        radius: 15
                        color: root.currentTab === index
                               ? Tokens.accent
                               : Qt.rgba(1, 1, 1, 0.05)

                        Behavior on color {
                            ColorAnimation {
                                duration: Tokens.animDuration("standard", "small")
                            }
                        }

                        Label {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: root.currentTab === parent.index
                                   ? Tokens.bg : Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                            font.bold: root.currentTab === parent.index
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentTab = parent.index
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
            }

            // -- Pages ----------------------------------------------------
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.currentTab

                // Controls -----------------------------------------------
                ColumnLayout {
                    spacing: Tokens.spacingMd

                    // Volume slider
                    RowLayout {
                        spacing: Tokens.spacingSm
                        Layout.fillWidth: true
                        Label {
                            text: root.audio && root.audio.muted ? "\u{1F507}" : "\u{1F50A}"
                            font.pixelSize: Tokens.fontMd
                            color: Tokens.text
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.audio) root.audio.toggle_mute()
                            }
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: root.audio ? root.audio.volume_percent : 0
                            onMoved: if (root.audio) root.audio.set_volume(Math.round(value))
                        }
                        Label {
                            text: root.audio ? root.audio.volume_percent + "%" : "--"
                            color: Tokens.textMuted
                            font.family: Tokens.monoFamily
                            font.pixelSize: Tokens.fontXs
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    // Brightness slider
                    RowLayout {
                        spacing: Tokens.spacingSm
                        Layout.fillWidth: true
                        visible: root.brightness && root.brightness.available
                        Label {
                            text: "\u2600"
                            font.pixelSize: Tokens.fontMd
                            color: Tokens.text
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 0.01; to: 1.0
                            value: root.brightness ? root.brightness.brightness : 0
                            onMoved: if (root.brightness) root.brightness.apply_brightness(value)
                        }
                        Label {
                            text: root.brightness
                                  ? Math.round(root.brightness.brightness * 100) + "%" : "--"
                            color: Tokens.textMuted
                            font.family: Tokens.monoFamily
                            font.pixelSize: Tokens.fontXs
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    // Toggle chips: wifi / bluetooth / power profile / modes
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        component ToggleChip: Rectangle {
                            property string label: ""
                            property bool active: false
                            signal clicked()

                            width: chipLabel.implicitWidth + Tokens.paddingMd * 2
                            height: 34
                            radius: 17
                            color: active ? Tokens.accent : Qt.rgba(1, 1, 1, 0.05)
                            border.color: active ? Tokens.accent : Qt.rgba(1, 1, 1, 0.15)
                            border.width: 1

                            Behavior on color {
                                ColorAnimation {
                                    duration: Tokens.animDuration("standard", "small")
                                }
                            }

                            Label {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: parent.label
                                color: parent.active ? Tokens.bg : Tokens.text
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontSm
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: parent.clicked()
                            }
                        }

                        ToggleChip {
                            label: root.network && root.network.connected
                                   ? "Wi-Fi \u00B7 " + root.network.active_ssid : "Wi-Fi"
                            active: root.network && root.network.wifi_enabled
                            onClicked: {
                                if (!root.network) return;
                                root.network.wifi_enabled ? root.network.wifi_off()
                                                          : root.network.wifi_on();
                            }
                        }
                        ToggleChip {
                            label: "Bluetooth"
                            active: root.bluetooth && root.bluetooth.powered
                            onClicked: if (root.bluetooth) root.bluetooth.toggle()
                        }
                        ToggleChip {
                            label: root.powerProfile && root.powerProfile.available
                                   ? "\u26A1 " + root.powerProfile.current_profile
                                   : "\u26A1 no profiles"
                            active: root.powerProfile
                                    && root.powerProfile.current_profile === "performance"
                            onClicked: if (root.powerProfile) root.powerProfile.cycle()
                        }
                        ToggleChip {
                            label: "Game mode"
                            active: GameFocusMode.gameModeActive
                            onClicked: GameFocusMode.toggleGameMode()
                        }
                        ToggleChip {
                            label: "Focus mode"
                            active: GameFocusMode.focusModeActive
                            onClicked: GameFocusMode.toggleFocusMode()
                        }
                        ToggleChip {
                            label: "Do not disturb"
                            active: root.notifier && root.notifier.dnd_enabled
                            onClicked: if (root.notifier) root.notifier.toggle_dnd()
                        }
                        ToggleChip {
                            label: "Caffeine"
                            active: GameFocusMode.caffeineActive
                            onClicked: GameFocusMode.toggleCaffeine()
                        }
                        ToggleChip {
                            visible: root.nightLight && root.nightLight.available
                            label: "Night light"
                            active: root.nightLight && root.nightLight.active
                            onClicked: if (root.nightLight) root.nightLight.toggle()
                        }
                        ToggleChip {
                            visible: root.screenshot && root.screenshot.recorder_available
                            label: root.screenshot && root.screenshot.recording
                                   ? "\u23F9 Stop recording" : "\u{1F3AC} Record"
                            active: root.screenshot && root.screenshot.recording
                            onClicked: if (root.screenshot) root.screenshot.record_region()
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // Metrics ------------------------------------------------
                MetricsPanel {
                    resources: root.resources
                }

                // Wallpapers ---------------------------------------------
                // The existing WallpaperPicker is a full-screen overlay;
                // embedding it here keeps one source of truth for the
                // grid. It stays visible while this tab is current.
                Item {
                    WallpaperPicker {
                        id: embeddedPicker
                        anchors.fill: parent
                        wallpaper: root.wallpaper
                        visible: root.visible && root.currentTab === 2
                        // Neutralise its own dim backdrop inside the card.
                        color: "transparent"
                    }
                }

                // Weather ------------------------------------------------
                WeatherPanel {
                    weather: root.weather
                }
            }
        }
    }
}
