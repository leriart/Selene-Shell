import QtQuick

// Single rounded corner arc (NothingLess). Paints a quarter-circle
// filled with the active background colour at one of the four screen
// corners so the compositor edge reads as rounded.
Item {
    id: root

    enum Corner { TopLeft, TopRight, BottomLeft, BottomRight }
    property var corner: RoundCorner.TopLeft
    property int size: 24
    property color color: "#0e0f12"

    implicitWidth: size
    implicitHeight: size

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d");
            var r = root.size;
            ctx.clearRect(0, 0, width, height);
            ctx.beginPath();
            switch (root.corner) {
            case RoundCorner.TopLeft:
                ctx.arc(r, r, r, Math.PI, 3 * Math.PI / 2);
                ctx.lineTo(0, 0);
                break;
            case RoundCorner.TopRight:
                ctx.arc(0, r, r, 3 * Math.PI / 2, 2 * Math.PI);
                ctx.lineTo(r, 0);
                break;
            case RoundCorner.BottomLeft:
                ctx.arc(r, 0, r, Math.PI / 2, Math.PI);
                ctx.lineTo(0, r);
                break;
            case RoundCorner.BottomRight:
                ctx.arc(0, 0, r, 0, Math.PI / 2);
                ctx.lineTo(r, r);
                break;
            }
            ctx.closePath();
            ctx.fillStyle = root.color;
            ctx.fill();
        }

        Connections {
            target: root
            function onColorChanged() { canvas.requestPaint() }
            function onCornerChanged() { canvas.requestPaint() }
            function onSizeChanged() { canvas.requestPaint() }
            function onVisibleChanged() { if (visible) canvas.requestPaint() }
        }
    }
}
