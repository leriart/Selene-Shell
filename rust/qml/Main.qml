import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts

import io.github.selene.shell

ApplicationWindow {
    id: root
    visible: true
    width: 720
    height: 480
    title: "Selene -- Rust <-> Hyprland <-> QML"
    color: Tokens.bg

    // Background wallpaper renders inside the ApplicationWindow. Layer-shell
    // support would push it underneath the compositor's windows; see TODO.md.
    WallpaperSurface {
        id: wallpaper
        anchors.fill: parent
        wallpaper: wallpaperBackend
        z: -1
    }

    Bridge {
        id: bridge
        greeting: "Selene -- bridge ready."
        counter: 0
        hyprland_status: "not connected"

        Component.onCompleted: bridge.start_listener()
    }

    Spawner {
        id: spawner

        Component.onCompleted: spawner.refresh()
    }

    Island {
        id: islandBackend

        Component.onCompleted: islandBackend.refresh()
    }

    Notifier {
        id: notifierBackend

        Component.onCompleted: {
            notifierBackend.refresh_from_disk();
            notifierBackend.start_dbus();
        }
    }

    Config {
        id: configBackend

        Component.onCompleted: {
            configBackend.reload();
            configBackend.start_watcher();
        }
    }

    Palette {
        id: paletteBackend

        Component.onCompleted: {
            paletteBackend.set_source(wallpaperBackend.current_path
                                     || paletteBackend.default_source());
            paletteBackend.refresh();
        }
    }

    Connections {
        target: wallpaperBackend
        function onCurrentPathChanged() {
            if (wallpaperBackend.current_path.length > 0) {
                paletteBackend.set_source(wallpaperBackend.current_path);
                paletteBackend.refresh();
            }
        }
    }

    Wallpaper {
        id: wallpaperBackend

        Component.onCompleted: wallpaperBackend.refresh()
    }

    Audio {
        id: audioBackend

        Component.onCompleted: audioBackend.refresh()
    }

    Network {
        id: networkBackend

        Component.onCompleted: networkBackend.refresh()
    }

    Bluetooth {
        id: bluetoothBackend

        Component.onCompleted: bluetoothBackend.refresh()
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: paletteBackend.refresh()
    }

    Connections {
        target: paletteBackend
        function onAccentChanged() {
            Tokens.accent = paletteBackend.accent;
        }
        function onBackgroundChanged() {
            Tokens.bg = paletteBackend.background;
        }
        function onSurfaceChanged() {
            Tokens.surface = paletteBackend.surface;
        }
        function onTextColorChanged() {
            // Palette property is `text_color`; QML converts to camelCase
            // for the signal handler hook above this line.
            Tokens.text = paletteBackend.text_color;
        }
    }

    Connections {
        // Config-driven tokens: react to live changes from settings /
        // hot-reloaded init.lua so the whole shell re-themes immediately.
        target: configBackend
        function onFont_familyChanged() {
            if (configBackend.font_family && configBackend.font_family.length > 0)
                Tokens.fontFamily = configBackend.font_family;
        }
        function onTheme_accentChanged() {
            if (configBackend.theme_accent && configBackend.theme_accent.length > 0) {
                Tokens.accent = configBackend.theme_accent;
                // Override the palette's wallpaper-derived accent so the
                // user-facing settings choice wins until the next refresh.
                paletteBackend.set_source(paletteBackend.source_path);
            }
        }
        function onTheme_backgroundChanged() {
            if (configBackend.theme_background && configBackend.theme_background.length > 0)
                Tokens.bg = configBackend.theme_background;
        }
        function onTheme_surfaceChanged() {
            if (configBackend.theme_surface && configBackend.theme_surface.length > 0)
                Tokens.surface = configBackend.theme_surface;
        }
    }

    Component.onCompleted: {
        // Seed the font family from the actual config (not the singleton's
        // default) so the user's choice in init.lua always wins.
        if (configBackend.font_family && configBackend.font_family.length > 0)
            Tokens.fontFamily = configBackend.font_family;
    }

    Timer {
        // Island metrics tick: /proc + /sys reads, clock, MPRIS metadata.
        // 2s cadence so CPU% deltas stay meaningful.
        interval: 2000
        running: true
        repeat: true
        onTriggered: islandBackend.refresh()
    }

    Timer {
        // Audio state poll: keep volume / mute fresh in case external apps
        // (wpctl, media players) changed the sink underneath us.
        interval: 5000
        running: true
        repeat: true
        onTriggered: audioBackend.refresh()
    }

    Timer {
        // Network state poll: signal / re-association can change without a
        // notifiable event; poll every 15s to keep the quick settings honest.
        interval: 15000
        running: true
        repeat: true
        onTriggered: networkBackend.refresh()
    }

    Timer {
        // Bluetooth state poll: 20s is fine -- pairing / discovery usually
        // last several seconds, and bluetoothctl is heavier than pactl.
        interval: 20000
        running: true
        repeat: true
        onTriggered: bluetoothBackend.refresh()
    }

    Timer {
        // Slow fallback refresh; the Rust event listener pushes real updates
        // through the cxx-qt queued bridge, this is just a safety net in case
        // an event slips through (or we started without a Hyprland session).
        interval: 10000
        running: true
        repeat: true
        onTriggered: bridge.refresh()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.barMargin
        spacing: Tokens.spacingMd

        Bar {
            id: bar
            Layout.fillWidth: true
            bridge: bridge
            launcher: launcher
            island: islandBackend
        }

        IslandPill {
            id: islandWidget
            Layout.alignment: Qt.AlignHCenter
            islandSource: islandBackend
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Tokens.surface
            radius: Tokens.radiusMd
            border.color: Tokens.border
            border.width: 1

            GridLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                columns: 2
                columnSpacing: Tokens.spacingLg
                rowSpacing: Tokens.spacingSm

                Label {
                    text: "cpu"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    text: islandBackend.cpu_percent.toFixed(1) + "%  (load " +
                          islandBackend.load_avg_1.toFixed(2) + ")"
                    color: Tokens.text
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontMd
                }

                Label {
                    text: "ram"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    text: islandBackend.ram_used_mb + " / " + islandBackend.ram_total_mb + " MB"
                    color: Tokens.text
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontMd
                }

                Label {
                    text: "battery"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    text: islandBackend.battery_present
                          ? (islandBackend.battery_percent + "%  " + islandBackend.battery_status)
                          : "none"
                    color: Tokens.text
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontMd
                }

                Label {
                    text: "media"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: (islandBackend.media_playing ? "> " : "|| ") +
                          islandBackend.media_title + " - " + islandBackend.media_artist +
                          (islandBackend.media_player.length > 0
                           ? "  [" + islandBackend.media_player + "]" : "")
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    elide: Text.ElideRight
                }

                Label {
                    text: "active workspace"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: bridge.active_workspace_id + "  " + (bridge.active_workspace_name || "(none)")
                    color: Tokens.accent
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontMd
                    font.bold: true
                }

                Label {
                    text: "workspace count"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    text: bridge.workspace_count
                    color: Tokens.accent
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontMd
                    font.bold: true
                }

                Label {
                    text: "active window"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: bridge.active_window_class || "(none)"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                }

                Label {
                    text: "title"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: bridge.active_window_title || "-"
                    color: Tokens.text
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                    elide: Text.ElideRight
                }

                Label {
                    text: "hyprland"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: bridge.hyprland_status
                    color: bridge.connected ? Tokens.success : Tokens.danger
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontSm
                }

                Label {
                    text: "config"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    Layout.fillWidth: true
                    text: (configBackend.defaults_used ? "defaults" : "loaded") + "  " +
                          (configBackend.status || "")
                    color: configBackend.defaults_used ? Tokens.danger : Tokens.textMuted
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontXs
                    elide: Text.ElideRight
                }

                Label {
                    text: "panel height"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    text: String(configBackend.panel_height) + " px  (" +
                          configBackend.panel_position + ", " +
                          (configBackend.panel_transparent ? "transparent" : "opaque") + ")"
                    color: Tokens.text
                    font.family: Tokens.monoFamily
                    font.pixelSize: Tokens.fontSm
                }

                Label {
                    text: "accent"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Rectangle {
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: 56
                    radius: 4
                    color: configBackend.theme_accent
                    border.color: Tokens.border
                    border.width: 1
                }

                Item { Layout.columnSpan: 2; Layout.fillHeight: true }

                Label {
                    text: "counter"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
                Label {
                    text: bridge.counter + " -- " + bridge.greeting
                    color: Tokens.accent
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "Your name"
            }

            Button {
                text: "Greet"
                onClicked: bridge.greeting = bridge.greet(nameField.text)
            }
            Button {
                text: "+"
                onClicked: bridge.increment()
            }
            Button {
                text: "Refresh"
                onClicked: bridge.refresh()
            }
            Button {
                text: "Launcher"
                onClicked: launcher.open()
            }
            Button {
                text: "Notif"
                onClicked: notifierPanel.toggle()
            }
            Button {
                text: "Walls"
                onClicked: wallpaperPicker.toggle()
            }
            Button {
                text: "Settings"
                onClicked: settingsPanel.toggle()
            }
            Button {
                text: "Audio"
                onClicked: audioPanel.toggle()
            }
            Button {
                text: "Net"
                onClicked: networkPanel.toggle()
            }
            Button {
                text: "BT"
                onClicked: bluetoothPanel.toggle()
            }
            Button {
                text: "Quit"
                onClicked: Qt.quit()
            }
        }
    }

    Launcher {
        id: launcher
        anchors.fill: parent
        z: 1000
        spawner: spawner
        Keys.onEscapePressed: launcher.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R) {
                launcher.toggle();
                event.accepted = true;
            } else if (event.modifiers === (Qt.ControlModifier | Qt.AltModifier)) {
                if (event.key === Qt.Key_Right) {
                    wallpaperBackend.next_wall();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    wallpaperBackend.previous_wall();
                    event.accepted = true;
                }
            }
        }
    }

    NotificationPanel {
        id: notifierPanel
        anchors.fill: parent
        z: 1100
        notifier: notifierBackend
    }

    WallpaperPicker {
        id: wallpaperPicker
        anchors.fill: parent
        z: 1200
        wallpaper: wallpaperBackend
        Keys.onEscapePressed: wallpaperPicker.close()
    }

    SettingsPanel {
        id: settingsPanel
        anchors.fill: parent
        z: 1300
        config: configBackend
        Keys.onEscapePressed: settingsPanel.close()
    }

    AudioPanel {
        id: audioPanel
        anchors.fill: parent
        z: 1400
        audio: audioBackend
        Keys.onEscapePressed: audioPanel.close()
    }

    NetworkPanel {
        id: networkPanel
        anchors.fill: parent
        z: 1500
        network: networkBackend
        Keys.onEscapePressed: networkPanel.close()
    }

    BluetoothPanel {
        id: bluetoothPanel
        anchors.fill: parent
        z: 1600
        bluetooth: bluetoothBackend
        Keys.onEscapePressed: bluetoothPanel.close()
    }
}
