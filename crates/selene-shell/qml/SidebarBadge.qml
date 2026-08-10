import QtQuick

// Status badge used by the Sidebar's bottom cluster. Same visual
// language as StatusDot but lives in a separate file so the Sidebar
// can use a column of them without dragging in the surrounding bar.
Rectangle {
    property bool active: false
    property color accent: "#a78bfa"

    width: 8
    height: 8
    radius: 4

    color: active ? accent : Qt.rgba(1, 1, 1, 0.12)
    border.color: Qt.rgba(0, 0, 0, 0.35)
    border.width: 1

    Behavior on active {
        ColorAnimation { duration: Tokens.durationFast }
    }
}
