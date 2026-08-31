import QtQuick
import QtQuick.Shapes

// Orbit.qml -- the visual primitive of Selene.
//
// Renders a circular orbit (the trace), and N satellites positioned
// along it. The whole rig rotates at `angularVelocity` deg/s, with an
// optional `phaseOffset` per satellite so they don't stack on top of
// each other. The visual language is the Selene moon concept:
//
//   * the centre is the moon (rendered by the parent)
//   * one or more orbit rings trace the path the satellites travel
//   * each satellite is an `Item` delegate the parent provides via
//     `satelliteComponent`
//
// Designed to be cheap: a single Shape (PathArcMoveTo + PathLine for
// the ring) and N re-positioned delegates -- no per-frame re-paint of
// the trace.
Item {
    id: root

    // ---- Geometry ---------------------------------------------------
    // All distances are computed in pixels; the caller is expected to
    // scale the whole orbit with the active shell token.
    property real radius: 80
    property int  satelliteCount: 4
    property real traceWidth: 1.2
    property real traceAlpha: 0.18
    property color traceColor: Tokens.accent
    property color accentColor: Tokens.accent
    property bool showTrace: true

    // ---- Motion -----------------------------------------------------
    // degrees per second. Negative = anticlockwise.
    property real angularVelocity: 6.0
    property bool rotating: true
    // Per-satellite angular phase, in radians.
    property real satellitePhaseOffset: 0.0
    // Pulse an extra inner stroke on beats (audio peak events).
    property bool pulsing: false
    property real pulseProgress: 0.0   // 0..1; 1 means "fully expanded"

    // ---- Delegate ---------------------------------------------------
    // The parent provides a Component for each satellite. It is
    // instantiated N times and reparented on every animation step.
    property Component satelliteComponent
    property var satelliteData: []

    // ---- Internal state --------------------------------------------
    property real _angle: 0
    readonly property var _satellites: []
    readonly property real _radiusOuter: radius + (pulsing ? pulseProgress * 28 : 0)
    readonly property real _radiusInner: pulsing ? radius - pulseProgress * 6 : radius

    // Trace -- one Shape so we don't pay QPainter overhead per ring.
    Shape {
        id: trace
        anchors.fill: parent
        visible: root.showTrace
        antialiasing: true
        layer.samples: 4

        ShapePath {
            strokeColor: Qt.rgba(root.traceColor.r, root.traceColor.g,
                                 root.traceColor.b, root.traceAlpha)
            strokeWidth: root.traceWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathArcMoveTo {
                x: parent.width / 2 + root._radiusOuter
                y: parent.height / 2
            }
            PathArc {
                x: parent.width / 2 + root._radiusOuter
                y: parent.height / 2
                radiusX: root._radiusOuter
                radiusY: root._radiusOuter
                useLargeArc: true
            }
            PathArc {
                x: parent.width / 2 + root._radiusOuter
                y: parent.height / 2
                radiusX: root._radiusOuter
                radiusY: root._radiusOuter
                useLargeArc: true
            }
        }

        // Inner pulse ring -- reveals on `pulseProgress` going 0..1.
        ShapePath {
            strokeColor: Qt.rgba(root.traceColor.r, root.traceColor.g,
                                 root.traceColor.b,
                                 0.4 * (1.0 - root.pulseProgress))
            strokeWidth: root.traceWidth * 2
            fillColor: "transparent"
            PathArcMoveTo {
                x: parent.width / 2 + root._radiusInner
                y: parent.height / 2
            }
            PathArc {
                x: parent.width / 2 + root._radiusInner
                y: parent.height / 2
                radiusX: root._radiusInner
                radiusY: root._radiusInner
                useLargeArc: true
            }
            PathArc {
                x: parent.width / 2 + root._radiusInner
                y: parent.height / 2
                radiusX: root._radiusInner
                radiusY: root._radiusInner
                useLargeArc: true
            }
        }
    }

    // Satellite rotation -- single NumberAnimation drives the rig.
    // Uses `from`/`to` swapped for negative angularVelocity so the
    // rig can spin either direction.
    NumberAnimation on _angle {
        running: root.rotating
        from: 0; to: 360
        duration: root.angularVelocity > 0
                   ? Math.abs(360000 / root.angularVelocity)
                   : 60000
        loops: Animation.Infinite
        alwaysRunToEnd: false
        // Sign of velocity controls direction (we negate the cos in
        // the satellite phase below when going backwards).
    }

    // Satellite positioning -- placed on a circle of `radius`.
    Repeater {
        model: root.satelliteCount
        delegate: Item {
            required property int index
            id: slot

            // Position is expressed in pixel coordinates; convert the
            // current rig angle + per-satellite offset into a unit
            // vector and scale by `radius`.
            property real phase: (slot.index * (2 * Math.PI / Math.max(1, root.satelliteCount)))
                                + root.satellitePhaseOffset
                                 + (root._angle * Math.PI / 180)
            x: (root.width / 2) + Math.cos(phase) * root._radiusOuter - width / 2
            y: (root.height / 2) + Math.sin(phase) * root._radiusOuter - height / 2

            // The parent must size satellites themselves; defaults to a
            // small dot if no component is set.
            Loader {
                anchors.fill: parent
                active: root.satelliteComponent !== null
                sourceComponent: root.satelliteComponent
                asynchronous: false
            }
            Rectangle {
                visible: root.satelliteComponent === null
                anchors.fill: parent
                radius: width / 2
                color: root.accentColor
            }
        }
    }
}
