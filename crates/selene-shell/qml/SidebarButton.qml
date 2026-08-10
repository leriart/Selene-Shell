import QtQuick
import QtQuick.Controls

// Sidebar icon button -- 32x32 rounded square with a glyph in the
// centre. Hover reveals a tooltip; click toggles a panel.
Rectangle {
    id: btn

    property string text: ""
    property string tooltip: ""
    property bool active: false
    property bool hover: false

    signal clicked()

    width: 32
    height: 32
    radius: 8

    color: active
           ? Qt.rgba(Tokens.surface.r, Tokens.surface.g, Tokens.surface.b, 0.95)
           : hover ? Qt.rgba(1, 1, 1, 0.08)
                   : "transparent"
    border.color: active
                  ? Tokens.accent
                  : Qt.rgba(1, 1, 1, Tokens.hairlineAlpha)
    border.width: 1

    Behavior on active {
        ColorAnimation { duration: Tokens.durationFast }
    }

    Label {
        anchors.centerIn: parent
        text: btn.text
        color: btn.active ? Tokens.accent : Tokens.text
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontMd
        font.bold: true
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
        onEntered: btn.hover = true
        onExited: btn.hover = false
    }

    ToolTip.visible: hover && tooltip.length > 0
    ToolTip.delay: 250
    ToolTip.text: tooltip
}
