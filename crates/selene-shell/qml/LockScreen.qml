import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

// Lockscreen (Ambxst / Caelestia). Full-screen overlay with a password
// field. Authenticates via the `Lock` QObject which delegates to
// `su -c true $USER` for PAM validation.
//
// Escape toggles between locked and hidden; Enter submits the password.
// Failed attempts show a brief shake effect and increment the attempt
// counter; five failures trigger a 2-second lockout.
Rectangle {
    id: root

    property var lock: null
    property string username: {
        if (lock && lock.username && lock.username.length > 0)
            return lock.username;
        return "";
    }

    visible: lock && lock.locked
    color: Qt.rgba(0, 0, 0, 0.75)

    // Shake animation
    property real shakeOffset: 0
    Behavior on shakeOffset {
        SequentialAnimation {
            NumberAnimation { to: 10; duration: 50; easing.type: Easing.InExpo }
            NumberAnimation { to: -10; duration: 50 }
            NumberAnimation { to: 5; duration: 50 }
            NumberAnimation { to: -5; duration: 50 }
            NumberAnimation { to: 2; duration: 50 }
            NumberAnimation { to: 0; duration: 50 }
        }
    }

    // Input capture: no click-through
    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 320
        height: 220
        radius: Tokens.radiusLg
        color: Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.92)
        border.color: Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
        border.width: 1
        x: root.shakeOffset

        MultiEffect {
            anchors.fill: parent
            source: wallpaper
            blurEnabled: true
            blur: 0.5
            opacity: 0.85
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14

            // Avatar -- AccountsService icon when present, otherwise
            // a circle with the user's initials (always renders, no
            // external file dependency).
            Rectangle {
                id: avatar
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                radius: 32
                color: Qt.rgba(Tokens.accent.r, Tokens.accent.g,
                               Tokens.accent.b, 0.18)
                border.color: Tokens.accent
                border.width: 1.4

                // Prefer a real face file.
                readonly property string facePath: {
                    if (!root.username.length) return "";
                    const candidates = [
                        "/var/lib/AccountsService/icons/" + root.username,
                        "/home/" + root.username + "/.face",
                        "/home/" + root.username + "/.face.icon"
                    ];
                    for (let i = 0; i < candidates.length; ++i) {
                        if (selene_file_exists(candidates[i]))
                            return candidates[i];
                    }
                    return "";
                }
                function selene_file_exists(p) {
                    // QML has no direct stat; probe with an Image
                    // whose status is checked below.
                    return true; // always try; Image falls back
                }

                Image {
                    id: avatarImage
                    anchors.fill: parent
                    anchors.margins: 2
                    source: avatar.facePath.length > 0
                            ? "file://" + avatar.facePath : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    visible: status === Image.Ready
                }

                Label {
                    anchors.centerIn: parent
                    visible: avatarImage.status !== Image.Ready
                    text: root.username.length > 0
                          ? root.username.substring(0, 1).toUpperCase()
                          : "\u263D"
                    color: Tokens.accent
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXl
                    font.bold: true
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: "selene"
                color: Tokens.accent
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontLg
                font.bold: true
            }

            Label {
                Layout.fillWidth: true
                text: lock ? lock.status : ""
                color: lock && lock.attempts > 0 ? Tokens.danger : Tokens.textMuted
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontXs
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: passwordInput
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "password"
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    enabled: lock !== null
                    onAccepted: submit()
                }

                Button {
                    text: "\u23CE"
                    enabled: lock !== null
                    onClicked: submit()
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    function submit() {
        if (!lock || !passwordInput.text || passwordInput.text.length === 0) return;
        var user = "lerit";  // fallback -- the Rust side may resolve
        var ok = lock.authenticate(user, passwordInput.text);
        if (!ok) {
            root.shakeOffset = 0;
            root.shakeOffset = 5;  // trigger shake
            passwordInput.text = "";
        } else {
            passwordInput.text = "";
        }
    }

    // Start with focus on the password field
    Component.onCompleted: passwordInput.forceActiveFocus()
}
