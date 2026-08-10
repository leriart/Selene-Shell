import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

import io.github.selene.shell

// Caelestia/Ambxst sidebar: a thin floating tab on the left edge that,
// when hovered or clicked, slides open to reveal a vertical panel of
// quick toggles. The default Caelestia implementation uses a 1px trigger
// strip; we make it a 32px tab so it's discoverable on touchpads but
// still minimal in the wild.
Rectangle {
    id: sidebar

    // Backend references
    property var audio: null
    property var network: null
    property var bluetooth: null
    property var launcher: null
    property var wallpaperPicker: null
    property var clipboard: null
    property var picker: null
    property var notifier: null

    // Show / hide. Caelestia uses pointer hover; Ambxst uses a hot edge.
    // We use both: hover opens, click also opens, escape closes.
    property bool open: false

    // Geometry -- the implicit width is the open state; the actual
    // bound `width` follows `_currentWidth` which is animated.
    implicitWidth: 56
    implicitHeight: Math.min(parent ? parent.height - 96 : 600, 480)
    radius: open ? Tokens.radiusLg : 3

    property real _currentWidth: 6
    width: _currentWidth
    Behavior on _currentWidth {
        NumberAnimation { duration: Tokens.duration; easing.type: Easing.OutCubic }
    }
    onOpenChanged: _currentWidth = open ? 56 : 6

    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, open ? 0.85 : 0.35)
    border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
    border.width: 1

    // Backdrop blur -- only when open; otherwise the trigger strip is
    // a transparent sliver. The wallpaper root is exposed by Main.qml
    // so we can sample it directly.
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: sidebar.open && wallpaper !== null
        blur: 0.6
        opacity: 0.95
    }

    // Trigger strip -- a 6px sliver that grows on hover.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: open ? Qt.ArrowCursor : Qt.PointingHandCursor
        onEntered: sidebar.open = true
        onExited: function() {
            closeTimer.restart();
        }
        onClicked: sidebar.open = !sidebar.open
    }

    Timer {
        id: closeTimer
        interval: 250
        repeat: false
        onTriggered: sidebar.open = false
    }

    // While the panel is open, the contents are interactive.
    Item {
        anchors.fill: parent
        opacity: sidebar.open ? 1.0 : 0.0
        visible: sidebar.open
        enabled: sidebar.open
        Behavior on opacity {
            NumberAnimation { duration: Tokens.durationFast }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            // Header
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: "selene"
                color: Tokens.textMuted
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontXs
                font.bold: true
            }

            // Visual hint when collapsed -- a vertical "groove" line
            // on the right edge so the user sees the slab is interactive.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 2
                height: 24
                radius: 1
                color: Qt.rgba(1, 1, 1, 0.15)
                visible: !sidebar.open
            }

            // The quick toggles. Each `SidebarButton` calls a qinvokable
            // on the corresponding backend or opens a panel.
            SidebarButton {
                Layout.alignment: Qt.AlignHCenter
                text: "\u25A0"   // clipboard
                tooltip: "Clipboard"
                onClicked: if (sidebar.clipboard) sidebar.clipboard.toggle()
                active: sidebar.clipboard && sidebar.clipboard.visible
            }
            SidebarButton {
                Layout.alignment: Qt.AlignHCenter
                text: "\u25D0"   // palette / color
                tooltip: "Color picker"
                onClicked: if (sidebar.picker) sidebar.picker.toggle()
                active: sidebar.picker && sidebar.picker.visible
            }
            SidebarButton {
                Layout.alignment: Qt.AlignHCenter
                text: "@"
                tooltip: "Launcher"
                onClicked: if (sidebar.launcher) sidebar.launcher.toggle()
                active: sidebar.launcher && sidebar.launcher.visible
            }
            SidebarButton {
                Layout.alignment: Qt.AlignHCenter
                text: "*"
                tooltip: "Wallpapers"
                onClicked: if (sidebar.wallpaperPicker) sidebar.wallpaperPicker.toggle()
                active: sidebar.wallpaperPicker && sidebar.wallpaperPicker.visible
            }

            Item { Layout.fillHeight: true }

            // Bottom group: status badges for the network / bluetooth
            // / audio backends. Compact, always visible.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 28
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }
            Item { Layout.preferredHeight: 4 }

            SidebarBadge {
                Layout.alignment: Qt.AlignHCenter
                active: sidebar.audio && !sidebar.audio.muted
                accent: Tokens.accent
            }
            SidebarBadge {
                Layout.alignment: Qt.AlignHCenter
                active: sidebar.network && sidebar.network.connected
                accent: Tokens.success
            }
            SidebarBadge {
                Layout.alignment: Qt.AlignHCenter
                active: sidebar.bluetooth && sidebar.bluetooth.powered
                accent: Tokens.accent
            }
        }
    }
}
