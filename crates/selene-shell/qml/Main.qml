import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

import io.github.selene.shell

ApplicationWindow {
    id: root
    visible: true
    width: typeof __seleneRenderSize !== "undefined" ? __seleneRenderSize.width : 720
    height: typeof __seleneRenderSize !== "undefined" ? __seleneRenderSize.height : 480
    title: "Selene -- Rust <-> Hyprland <-> QML"
    color: Tokens.bg

    // Optional screenshot mode: when main.cpp is invoked with
    // `--show=<panel>`, it sets this context property and we open the
    // matching panel before the QQuickWindow snapshot fires.
    property string screenshotPanel: typeof __seleneScreenshotPanel !== "undefined"
                                    ? __seleneScreenshotPanel : ""
    property string __launcherQuery: typeof __seleneLauncherQuery !== "undefined"
                                    ? __seleneLauncherQuery : ""
    onScreenshotPanelChanged: console.log("selene: screenshotPanel =", screenshotPanel)

    function applyScreenshotPanel(name) {
        if (!name) return;
        const prefill = (name === "launcher" && __launcherQuery.length > 0)
                      ? __launcherQuery : "";
        switch (name) {
        case "launcher":  launcher.open(prefill); break;
        case "notif":     notifierPanel.open(); break;
        case "walls":     wallpaperPicker.open(); break;
        case "settings":  settingsPanel.open(); break;
        case "audio":     audioPanel.open(); break;
        case "net":       networkPanel.open(); break;
        case "bt":        bluetoothPanel.open(); break;
        case "sidebar":   sidebar.open = true; break;
        case "clipboard": clipboardPanel.open(); break;
        case "picker":   colorPickerPanel.open(); break;
        case "dashboard": islandWidget.cardExpanded = true; break;
        }
    }

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

    Clipboard {
        id: clipboardBackend
        Component.onCompleted: clipboardBackend.refresh()
    }

    Picker {
        id: pickerBackend
    }

    State {
        id: stateBackend
    }

    Visualizer {
        id: visualizerBackend

        Component.onCompleted: visualizerBackend.start()
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
        // Disable the palette->Tokens wiring when the user has explicitly
        // opted out (Config.palette_follow_wallpaper == false). The
        // Config-driven connections below always apply, so the manual
        // theme_* values take over in that mode.
        enabled: configBackend === null || configBackend.palette_follow_wallpaper
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
            if (configBackend.theme_accent && configBackend.theme_accent.length > 0)
                Tokens.accent = configBackend.theme_accent;
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
        // Seed theme tokens from Config first so a user who has set
        // theme_* in init.lua gets their colors immediately rather than
        // waiting for the first palette refresh.
        if (configBackend.theme_accent && configBackend.theme_accent.length > 0)
            Tokens.accent = configBackend.theme_accent;
        if (configBackend.theme_background && configBackend.theme_background.length > 0)
            Tokens.bg = configBackend.theme_background;
        if (configBackend.theme_surface && configBackend.theme_surface.length > 0)
            Tokens.surface = configBackend.theme_surface;
        if (configBackend.font_family && configBackend.font_family.length > 0)
            Tokens.fontFamily = configBackend.font_family;
        // Open the requested panel for headless screenshot capture.
        // Use a Timer so the Window is fully realized and the panel
        // components are constructed before we ask them to open.
        if (screenshotPanel.length > 0) {
            const timer = Qt.createQmlObject('import QtQml; Timer { interval: 250; running: true; onTriggered: { applyScreenshotPanel(screenshotPanel); } }',
                                              root, "screenshot-timer");
        }
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

    // Caelestia-style chrome: just the floating bar at the top and a
    // small island pill at the bottom-right. The rest of the desktop
    // is the wallpaper -- the debug grid + button bar are gone in
    // favour of the launcher overlay and the JSON-driven panels.
    Bar {
        id: bar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Tokens.barMargin
        bridge: bridge
        island: islandBackend
        network: networkBackend
        bluetooth: bluetoothBackend
        audio: audioBackend
        backdropSource: wallpaper
    }

    IslandPill {
        id: islandWidget
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Tokens.barMargin
        anchors.bottomMargin: Tokens.barMargin
        islandSource: islandBackend
        visualizer: visualizerBackend
        network: networkBackend
        audio: audioBackend
        state: stateBackend
        cardExpanded: typeof __seleneScreenshotPanel !== "undefined"
                      && __seleneScreenshotPanel === "dashboard"
    }

    Sidebar {
        id: sidebar
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        audio: audioBackend
        network: networkBackend
        bluetooth: bluetoothBackend
        launcher: launcher
        wallpaperPicker: wallpaperPicker
        clipboard: clipboardPanel
        picker: colorPickerPanel
        open: typeof __seleneScreenshotPanel !== "undefined"
              && __seleneScreenshotPanel === "sidebar"
    }

    Launcher {
        id: launcher
        anchors.fill: parent
        z: 1000
        spawner: spawner
        Keys.onEscapePressed: launcher.close()
    }

    Item {
        id: keys
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

    ClipboardPanel {
        id: clipboardPanel
        anchors.fill: parent
        z: 1700
        clipboard: clipboardBackend
        Keys.onEscapePressed: clipboardPanel.close()
    }

    ColorPickerPanel {
        id: colorPickerPanel
        anchors.fill: parent
        z: 1800
        picker: pickerBackend
        Keys.onEscapePressed: colorPickerPanel.close()
    }
}
