import QtQuick
import QtQuick.Layouts

// Tiny round status indicator -- 8px dot. Drives off `active`; transitions
// between the `accent` color and a translucent white. Used by the bar's
// status indicator cluster (media / audio / net / bt).
Rectangle {
    property bool active: false
    property bool muted: false
    property color accent: "#a78bfa"

    Layout.preferredHeight: 8
    Layout.preferredWidth: 8
    Layout.alignment: Qt.AlignVCenter

    radius: 4
    color: active ? accent
                  : Qt.rgba(1, 1, 1, 0.1)
    border.color: Qt.rgba(0, 0, 0, 0.25)
    border.width: 1

    Behavior on color {
        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
    }
}
