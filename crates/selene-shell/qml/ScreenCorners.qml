import QtQuick

// Screen corner rounding (NothingLess). Paints a filled arc at each
// screen corner using the current background colour so the window
// looks like it has rounded screen edges.
//
// The corner arcs are Canvas-based and scale with the `size` property.
// When the user enters a fullscreen app, the corners hide themselves
// so the app sees clean edges.
Item {
    id: root

    property int cornerSize: Tokens.radiusXl + 8
    property bool visibleCorners: true // set false for fullscreen apps
    property color cornerColor: Tokens.bg

    implicitWidth: cornerSize
    implicitHeight: cornerSize

    RoundCorner {
        size: cornerSize
        anchors.left: parent.left
        anchors.top: parent.top
        corner: RoundCorner.TopLeft
        visible: root.visibleCorners
        color: root.cornerColor
    }
    RoundCorner {
        size: cornerSize
        anchors.right: parent.right
        anchors.top: parent.top
        corner: RoundCorner.TopRight
        visible: root.visibleCorners
        color: root.cornerColor
    }
    RoundCorner {
        size: cornerSize
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        corner: RoundCorner.BottomLeft
        visible: root.visibleCorners
        color: root.cornerColor
    }
    RoundCorner {
        size: cornerSize
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        corner: RoundCorner.BottomRight
        visible: root.visibleCorners
        color: root.cornerColor
    }
}
