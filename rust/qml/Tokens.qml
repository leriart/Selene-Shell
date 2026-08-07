pragma Singleton

import QtQuick

QtObject {
    readonly property int radiusSm: 4
    readonly property int radiusMd: 8
    readonly property int radiusLg: 14

    readonly property int spacingXs: 4
    readonly property int spacingSm: 8
    readonly property int spacingMd: 12
    readonly property int spacingLg: 20

    readonly property int durationFast: 120
    readonly property int duration: 200
    readonly property int durationSlow: 320

    // Theme colors. These are mutable so the live palette engine can
    // re-tint them when the wallpaper changes. Defaults match the
    // Caelestia-feel dark surface palette.
    property color bg: "#0e0f12"
    property color surface: "#16181c"
    property color surfaceAlt: "#1f2128"
    property color border: "#2a2c33"
    property color borderStrong: "#3a3d46"
    property color accent: "#a78bfa"
    property color accentMuted: "#3a2e5e"
    property color text: "#e6e6ea"
    property color textMuted: "#8a8d96"
    property color textDim: "#555"
    property color success: "#7ee787"
    property color danger: "#f97583"

    Behavior on bg { ColorAnimation { duration: 600 } }
    Behavior on surface { ColorAnimation { duration: 600 } }
    Behavior on accent { ColorAnimation { duration: 600 } }
    Behavior on text { ColorAnimation { duration: 600 } }
    Behavior on textMuted { ColorAnimation { duration: 600 } }

    readonly property int barHeight: 40
    readonly property int barMargin: 12
    readonly property int chipSize: 28

    property string fontFamily: "Inter, Sans-Serif"
    readonly property string monoFamily: "JetBrains Mono, monospace"
    readonly property int fontXs: 10
    readonly property int fontSm: 12
    readonly property int fontMd: 14
    readonly property int fontLg: 18
    readonly property int fontXl: 22
}
