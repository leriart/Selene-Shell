import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Power menu (NothingLess power menu port) -- centered overlay with
// the five session actions. Lock goes through the Lock backend so the
// in-shell LockScreen shows; the rest dispatch to systemctl/loginctl
// through the Island backend. Toggled by SUPER+ESC or
// `selene run powermenu`.
Rectangle {
    id: root

    // Backend references, injected by Main.qml.
    property var island: null   // power actions (suspend/reboot/poweroff)
    property var lock: null     // in-shell lock screen backend
    property var notifier: null // DND state, user-facing notifications

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    function toggle() { visible ? close() : open(); }
    function open() {
        visible = true;
        forceActiveFocus();
    }
    function close() { visible = false; }

    // Action dispatch -- each closes the menu first so the compositor
    // isn't blocked mid-animation when the system goes down.
    function act(action) {
        close();
        switch (action) {
        case "lock":
            if (lock) lock.lock();
            break;
        case "suspend":
            if (island) island.suspend();
            break;
        case "reboot":
            if (island) island.reboot();
            break;
        case "poweroff":
            if (island) island.poweroff();
            break;
        case "logout":
            // Hyprland exit -- ends the session back at the greeter.
            if (island) island.logout();
            break;
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: menuRow.implicitWidth + Tokens.paddingLg * 2
        height: menuRow.implicitHeight + Tokens.paddingLg * 2

        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.94)
        radius: Tokens.radiusLg
        border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        RowLayout {
            id: menuRow
            anchors.centerIn: parent
            spacing: Tokens.spacingMd

            Repeater {
                model: [
                    { action: "lock",     glyph: "\u{1F512}", label: "Lock" },
                    { action: "logout",   glyph: "\u{1F6AA}", label: "Log out" },
                    { action: "suspend",  glyph: "\u{1F4A4}", label: "Suspend" },
                    { action: "reboot",   glyph: "\u{1F504}", label: "Reboot" },
                    { action: "poweroff", glyph: "\u23FB",    label: "Power off" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    Layout.preferredWidth: 108
                    Layout.preferredHeight: 96
                    radius: Tokens.radiusMd
                    color: buttonHover.containsMouse
                           ? Qt.rgba(Tokens.accent.r, Tokens.accent.g, Tokens.accent.b, 0.25)
                           : Qt.rgba(1, 1, 1, 0.05)
                    border.color: buttonHover.containsMouse
                                  ? Tokens.accent
                                  : Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1

                    Behavior on color {
                        ColorAnimation {
                            duration: Tokens.animDuration("standard", "small")
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.spacingSm

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.glyph
                            font.pixelSize: 28
                            color: buttonHover.containsMouse ? Tokens.accent : Tokens.text
                        }
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                        }
                    }

                    MouseArea {
                        id: buttonHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act(modelData.action)
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: root.close()
}
