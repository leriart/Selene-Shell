import QtQuick
import QtQuick.Controls

// OsdPopup.qml -- one-shot overlay that surfaces a system value
// (volume / brightness / night light / recording) for ~1.5s, then
// fades out. Circular backdrop + glyph + numeric badge, matching the
// orbital theme. `shown` is used instead of `visible` to avoid
// clobbering the built-in Item.visible property.
Item {
    id: root

    property string kind: "volume"
    property real value: 0
    property bool shown: false
    property int autoHideMs: 1500
    property real radius: 64

    readonly property string _glyph: {
        switch (kind) {
        case "volume": return value <= 0 ? "\u{1F507}"
                        : (value < 50 ? "\u{1F509}" : "\u{1F50A}");
        case "brightness": return "\u2600";
        case "nightlight": return "\u{1F319}";
        case "record": return "\u23F9";
        default: return "\u2022";
        }
    }

    readonly property string _label: {
        switch (kind) {
        case "volume": return Math.round(value) + "%";
        case "brightness": return Math.round(value * 100) + "%";
        case "nightlight": return value >= 1 ? "on" : "off";
        case "record": return value >= 1 ? "rec" : "stop";
        default: return "";
        }
    }

    function flash(kind_, value_) {
        kind = kind_;
        value = value_;
        shown = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: root.autoHideMs
        repeat: false
        onTriggered: root.shown = false
    }

    Rectangle {
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: root.radius * 2 + 60
        height: width
        radius: width / 2
        color: Qt.rgba(Tokens.bg.r, Tokens.bg.g, Tokens.bg.b, 0.65)
        border.color: Qt.rgba(1, 1, 1, 0.18)
        border.width: 1
        visible: root.shown
        opacity: root.shown ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Tokens.durationSlow } }

        Rectangle {
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
            width: root.radius * 2
            height: width
            radius: width / 2
            color: "transparent"
            border.color: root.kind === "brightness" ? Tokens.text
                        : (root.kind === "nightlight" ? "#ffd9a8" : Tokens.accent)
            border.width: 5
            opacity: Math.max(0.18, Math.min(1, root.value / 100))
        }

        Column {
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
            width: parent.width
            spacing: 4

            Label {
                text: root._glyph
                font.pixelSize: 28
                color: Tokens.text
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Label {
                text: root._label
                color: Tokens.text
                font.family: Tokens.monoFamily
                font.pixelSize: Tokens.fontSm
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
