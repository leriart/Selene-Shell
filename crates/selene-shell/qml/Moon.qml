import QtQuick
import QtQuick.Shapes

// Moon.qml -- the central lunar disc.
//
// Renders a circular moon whose shadow rotates according to the real
// lunar phase for the current date. The dark crescent is the *umbra*,
// positioned based on the synodic age (0..29.53 days). The hue of the
// lit half is driven by `Tokens.accent` so it re-tints live with the
// active theme / wallpaper palette.
//
// Used standalone (e.g. IslandPill) and as the centre of an Orbit.
Item {
    id: root

    property real radius: 22
    // 0..1 lit fraction (0 = new moon, 0.5 = first quarter, 1 = full,
    // 1.5 = last quarter). Defaults to today's phase; the parent can
    // override for static decoration.
    property real phase: _computePhase(new Date())
    // Disc colour (lit half) and shadow (dark half).
    property color litColor: Tokens.text
    property color shadowColor: Qt.darker(Tokens.surface, 1.4)
    property color haloColor: Tokens.accent
    property real haloAlpha: 0.25
    property bool showHalo: true

    // Compute lunar age in days for `d` (0..29.53 synodic month). Uses
    // the well-known Meeus 1998 simplification (good to ~1 day for
    // visual purposes -- we are a desktop shell, not an almanac).
    function _computePhase(d) {
        const ref = new Date(2000, 0, 6, 18, 14, 0); // 2000-01-06 18:14 UTC, new moon
        const ms = d.getTime() - ref.getTime();
        const days = ms / 86400000.0;
        const synodic = 29.5305882;
        let age = ((days % synodic) + synodic) % synodic;
        return age / synodic;     // 0..1 of the synodic month
    }

    // Direction the terminator is on (-1 waning, +1 waxing). True
    // direction flips twice a month; the cheap heuristic is "waxing
    // before full (age < 0.5), waning after".
    property bool _waxing: phase < 0.5

    implicitWidth: radius * 2 + (showHalo ? 14 : 0)
    implicitHeight: implicitWidth

    Shape {
        id: halo
        anchors.centerIn: parent
        width: root.radius * 2.4
        height: width
        visible: root.showHalo && root.haloAlpha > 0.001
        antialiasing: true
        opacity: root.haloAlpha

        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.rgba(root.haloColor.r, root.haloColor.g,
                               root.haloColor.b, 0.20)
            startX: 0
            startY: height / 2
            PathArcMoveTo { x: 0; y: height / 2 }
            PathArc {
                x: width; y: height / 2
                radiusX: width / 2
                radiusY: height / 2
                useLargeArc: true
            }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.rgba(root.haloColor.r, root.haloColor.g,
                               root.haloColor.b, 0.45)
            startX: 0
            startY: height / 2
            PathArcMoveTo { x: 0; y: height / 2 }
            PathArc {
                x: width; y: height / 2
                radiusX: width / 2 - root.radius * 0.4
                radiusY: height / 2 - root.radius * 0.4
                useLargeArc: true
            }
        }
    }

    Shape {
        id: lit
        anchors.centerIn: parent
        width: root.radius * 2
        height: width
        antialiasing: true

        ShapePath {
            // Whole disc in lit colour.
            strokeColor: "transparent"
            fillColor: root.litColor
            startX: 0
            startY: height / 2
            PathArcMoveTo { x: 0; y: height / 2 }
            PathArc {
                x: width; y: height / 2
                radiusX: width / 2
                radiusY: height / 2
                useLargeArc: true
            }
        }

        // Shadow disc overlay -- covers the dark half. We draw an
        // ellipse offset by `phase`-driven magnitude, producing the
        // crescent shape visually (no SVG path math needed).
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.shadowColor

            // How much of the disc is lit: |phase - 0.5| * 2 mapped to
            // 0..1 where 1 == full and 0 == new. We invert to find
            // shadow width.
            readonly property real lit: 1.0 - Math.abs(root.phase - 0.5) * 2
            readonly property real rx: Math.max(1, width / 2 * lit)
            readonly property real cx: root._waxing ? width * 0.0 : width * 1.0

            startX: cx; startY: height / 2
            PathArcMoveTo { x: cx; y: height / 2 }
            PathArc {
                x: cx; y: height / 2
                radiusX: rx
                radiusY: height / 2
                useLargeArc: true
            }
        }
    }
}
