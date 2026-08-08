import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

import io.github.selene.shell

// Floating top pill -- Caelestia / Ambxst aesthetic.
//
// Layout follows Caelestia's `bar.entries` array:
//
//   logo | workspaces | (spacer) | activeWindow | (spacer) | tray | clock | statusIcons | power
//
// The bar is a single self-contained rectangle; every cluster is a
// small helper inline. The wallpaper below us is exposed via
// `backdropSource` so the MultiEffect can sample it for the blur.
Rectangle {
    id: bar

    // Backend accessors
    property var backdropSource: null
    property var bridge: null
    property var island: null
    property var network: null
    property var bluetooth: null
    property var audio: null

    // Floating pill geometry -- anchored to top by the parent layout.
    implicitWidth: Math.min(Tokens.barMaxWidth, parent ? parent.width - 80 : Tokens.barMaxWidth)
    implicitHeight: Tokens.barHeight
    radius: Tokens.barHeight / 2

    color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, Tokens.surfaceAlpha)
    border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
    border.width: 1

    MultiEffect {
        anchors.fill: parent
        source: bar.backdropSource
        blurEnabled: bar.backdropSource !== null
        blur: Tokens.backdropBlur
        saturation: Tokens.backdropSaturation
        opacity: Tokens.layerAlpha
    }

    // -- Left: logo + workspaces ------------------------------------
    RowLayout {
        id: leftCluster
        anchors.left: parent.left
        anchors.leftMargin: Tokens.barPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.barSpacing

        // Logo -- luminance-aware source flip keeps the silhouette
        // visible regardless of which palette is active.
        Item {
            Layout.preferredHeight: Tokens.barLogoSize
            Layout.preferredWidth: Tokens.barLogoSize
            Layout.alignment: Qt.AlignVCenter
            function surfaceLuminance() {
                const c = bar.color;
                const ch = (v) => {
                    v = v / 255.0;
                    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
                };
                return 0.2126 * ch(c.r * 255)
                     + 0.7152 * ch(c.g * 255)
                     + 0.0722 * ch(c.b * 255);
            }
            property bool lightBg: surfaceLuminance() < 0.4
            Image {
                anchors.fill: parent
                source: parent.lightBg
                       ? "qrc:/qt/qml/io/github/selene/shell/assets/logo-white.png"
                       : "qrc:/qt/qml/io/github/selene/shell/assets/logo-dark.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                asynchronous: true
            }
        }

        // Workspace dots -- Caelestia-style numbered circles, accent
        // when active, dim outline otherwise.
        RowLayout {
            spacing: 6
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: Tokens.barWorkspaceSize
            Repeater {
                model: bridge ? Math.max(1, bridge.workspace_count) : 0
                delegate: Item {
                    required property int index
                    width: Tokens.barWorkspaceSize; height: Tokens.barWorkspaceSize

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: (index + 1) === (bridge ? bridge.active_workspace_id : -1)
                               ? Tokens.accent
                               : Qt.rgba(1, 1, 1, 0.04)
                        border.color: (index + 1) === (bridge ? bridge.active_workspace_id : -1)
                                      ? Tokens.accent
                                      : Qt.rgba(1, 1, 1, 0.18)
                        border.width: 1

                        Behavior on color {
                            ColorAnimation { duration: Tokens.duration; easing.type: Easing.OutCubic }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: Tokens.duration }
                        }

                        Label {
                            anchors.centerIn: parent
                            text: (index + 1).toString()
                            color: (index + 1) === (bridge ? bridge.active_workspace_id : -1)
                                   ? "#0e0f12"
                                   : Tokens.textMuted
                            font.family: Tokens.monoFamily
                            font.pixelSize: Tokens.fontXs
                            font.bold: (index + 1) === (bridge ? bridge.active_workspace_id : -1)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: parent.children[0].opacity = 0.8
                        onExited: parent.children[0].opacity = 1.0
                    }
                }
            }
        }
    }

    // -- Center: active window popout ---------------------------------
    // Caelestia shows the active window title in the center; we render
    // it as a single-line ellipsized label that fills the available
    // space between the two side clusters.
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.barPadding
        anchors.rightMargin: Tokens.barPadding
        width: Math.min(parent.width - 480, implicitWidth)
        horizontalAlignment: Text.AlignHCenter
        text: {
            if (!bridge) return "selene";
            if (bridge.active_window_title && bridge.active_window_title.length > 0)
                return bridge.active_window_title;
            if (bridge.active_window_class && bridge.active_window_class.length > 0)
                return bridge.active_window_class;
            return "selene";
        }
        color: Tokens.text
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSm
        font.letterSpacing: 0.2
        elide: Text.ElideMiddle
    }

    // -- Right: media + tray + clock + status icons + power ------------
    RowLayout {
        id: rightCluster
        anchors.right: parent.right
        anchors.rightMargin: Tokens.barPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.barSpacing

        // Media title appears next to the status icons when something
        // is playing. Caelestia shows it on the bar too; we keep
        // it short and elide.
        Label {
            Layout.maximumWidth: 180
            visible: island && island.media_playing
                     && island.media_title.length > 0
            text: (island && island.media_playing ? "\u25B6 " : "") +
                  (island ? island.media_title : "")
            color: Tokens.textMuted
            font.family: Tokens.monoFamily
            font.pixelSize: Tokens.fontXs
            elide: Text.ElideRight
        }

        BarSeparator { visible: island && island.media_playing }

        // Status icons cluster -- mirrors Caelestia's `statusIcons`
        // array. Six small dots; the ones whose backing QObject is
        // missing stay deactivated.
        RowLayout {
            spacing: 6
            Repeater {
                model: [
                    { id: "lock",    active: bridge && bridge.connected, accent: Tokens.success },
                    { id: "audio",   active: audio && !audio.muted,       accent: Tokens.accent },
                    { id: "net",     active: network && network.connected, accent: Tokens.success },
                    { id: "bt",      active: bluetooth && bluetooth.powered, accent: Tokens.accent }
                ]
                delegate: StatusDot {
                    Layout.preferredHeight: Tokens.barStatusSize
                    Layout.preferredWidth: Tokens.barStatusSize
                    active: modelData.active
                    accent: modelData.accent
                }
            }
        }

        BarSeparator {}

        // Clock
        Label {
            text: island ? island.time_hhmm : "--:--"
            color: Tokens.text
            font.family: Tokens.monoFamily
            font.pixelSize: Tokens.fontSm
            font.weight: Font.DemiBold
            Layout.alignment: Qt.AlignVCenter
        }

        BarSeparator {}

        // Battery gauge
        Item {
            Layout.preferredHeight: Tokens.barBatteryHeight
            Layout.preferredWidth: Tokens.barBatteryWidth
            Layout.alignment: Qt.AlignVCenter
            visible: island && island.battery_present

            Rectangle {
                anchors.fill: parent
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.05)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1

                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: 1
                    width: parent.width * ((island ? island.battery_percent : 0) / 100)
                    color: island && island.battery_percent <= 15
                           ? Tokens.danger : Tokens.accent
                    radius: 2

                    Behavior on width {
                        NumberAnimation { duration: Tokens.duration }
                    }
                }
            }
        }

        BarSeparator {}

        // Power button (Caelestia `power` entry). Pings a small session
        // menu popup that drives the existing Island.qinvokables. We
        // tap into the Island directly because it already owns the
        // loginctl / systemctl plumbing.
        Item {
            id: powerBtn
            Layout.preferredHeight: 22
            Layout.preferredWidth: 22
            Layout.alignment: Qt.AlignVCenter

            property bool hover: false
            Behavior on opacity { NumberAnimation { duration: Tokens.durationFast } }

            Rectangle {
                anchors.fill: parent
                radius: 11
                color: parent.hover ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
            }

            Label {
                anchors.centerIn: parent
                text: "\u23FF"   // power symbol
                color: Tokens.text
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontMd
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: powerBtn.hover = true
                onExited: powerBtn.hover = false
                onClicked: sessionMenu.open()
            }
        }
    }

    // Session menu popup -- lock / suspend / reboot / poweroff / logout.
    // Mirrors Caelestia's `session` module. Side-bottom anchored so it
    // doesn't compete with the launcher or the panels.
    Popup {
        id: sessionMenu
        focus: true
        modal: true
        x: parent.width - width - Tokens.barMargin
        y: parent.height - height - Tokens.barMargin - 38
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.95)
            radius: Tokens.radiusLg
            border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 0
            Item { Layout.preferredHeight: 8; Layout.fillWidth: true }
            Repeater {
                model: [
                    { label: "Lock",      qaction: "lock" },
                    { label: "Suspend",   qaction: "suspend" },
                    { label: "Logout",    qaction: "logout" },
                    { label: "Reboot",    qaction: "reboot" },
                    { label: "Power off", qaction: "poweroff" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: hoverArea.containsMouse
                           ? Qt.rgba(1, 1, 1, 0.06)
                           : "transparent"
                    radius: 0

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.spacingLg
                        text: parent.modelData.label
                        color: Tokens.text
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                    }
                    MouseArea {
                        id: hoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            sessionMenu.close();
                            if (!island) return;
                            switch (parent.modelData.qaction) {
                            case "lock":     island.lock();     break;
                            case "suspend":  island.suspend();  break;
                            case "logout":   island.logout();   break;
                            case "reboot":   island.reboot();   break;
                            case "poweroff": island.poweroff(); break;
                            }
                        }
                    }
                }
            }
            Item { Layout.preferredHeight: 8; Layout.fillWidth: true }
        }
    }
}
