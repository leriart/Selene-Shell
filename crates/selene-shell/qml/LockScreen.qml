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
