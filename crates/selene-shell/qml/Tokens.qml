pragma Singleton

import QtQuick

// Design tokens inspired by Caelestia's `shell-tokens.json`:
//
//   * rounding.scale, spacing.scale, padding.scale, font.scale, anim.scale
//     are applied to the base values below so the whole shell responds
//     to a single multiplier. (Caelestia applies these to a different
//     base; our values stay close to the originals but expose the
//     same fields so the surface stays predictable.)
//
//   * borderRounding controls the rounded corner radius of every
//     visible element for the "frosted glass" feel.
//
//   * backdrops use BackdropBlur via Qt Quick's MultiEffect; the
//     enabled + layer0/1 alpha values let the user mute the blur when
//     GPU-bound.
//
//   * fg/bg/surface/border etc. are mutable so the live palette
//     engine can re-tint them when the wallpaper changes; the rest
//     of the tokens are readonly (sizing, scale, etc.).
QtObject {
    // -- Scales (Caelestia-style) ---------------------------------------
    readonly property real scale: 1.0
    readonly property real roundingScale: 1.0
    readonly property real spacingScale: 1.0
    readonly property real paddingScale: 1.0
    readonly property real fontScale: 1.0
    readonly property real animScale: 1.0

    // -- Rounding -------------------------------------------------------
    readonly property int radiusXs: Math.round(2 * roundingScale)
    readonly property int radiusSm: Math.round(6 * roundingScale)
    readonly property int radiusMd: Math.round(10 * roundingScale)
    readonly property int radiusLg: Math.round(16 * roundingScale)
    readonly property int radiusXl: Math.round(22 * roundingScale)

    // -- Spacing / padding ----------------------------------------------
    readonly property int spacingXs: Math.round(4 * spacingScale)
    readonly property int spacingSm: Math.round(8 * spacingScale)
    readonly property int spacingMd: Math.round(12 * spacingScale)
    readonly property int spacingLg: Math.round(20 * spacingScale)
    readonly property int spacingXl: Math.round(32 * spacingScale)

    readonly property int paddingXs: Math.round(4 * paddingScale)
    readonly property int paddingSm: Math.round(8 * paddingScale)
    readonly property int paddingMd: Math.round(14 * paddingScale)
    readonly property int paddingLg: Math.round(20 * paddingScale)

    // -- Animation -----------------------------------------------------
    readonly property int durationFast:  Math.round(120 * animScale)
    readonly property int duration:      Math.round(200 * animScale)
    readonly property int durationSlow:  Math.round(320 * animScale)
    readonly property int durationSlower: Math.round(480 * animScale)

    // -- Theme colours (live-tunable by the palette engine) ------------
    property color bg:          "#0e0f12"
    property color surface:     "#16181c"
    property color surfaceAlt:  "#1f2128"
    property color border:      "#2a2c33"
    property color borderStrong: "#3a3d46"
    property color accent:      "#a78bfa"
    property color accentMuted: "#3a2e5e"
    property color text:        "#e6e6ea"
    property color textMuted:   "#8a8d96"
    property color textDim:     "#555"
    property color success:     "#7ee787"
    property color danger:      "#f97583"

    Behavior on bg          { ColorAnimation { duration: durationSlower } }
    Behavior on surface     { ColorAnimation { duration: durationSlower } }
    Behavior on accent      { ColorAnimation { duration: durationSlower } }
    Behavior on text        { ColorAnimation { duration: durationSlower } }
    Behavior on textMuted   { ColorAnimation { duration: durationSlower } }

    // -- Backdrop glass ------------------------------------------------
    // Caelestia defaults to an opaque surface; we apply a 55% surface
    // over a MultiEffect blur of the wallpaper so the chrome reads
    // like frosted glass.
    readonly property real surfaceAlpha: 0.55
    readonly property real layerAlpha: 0.92
    readonly property real backdropBlur: 0.7
    readonly property real backdropSaturation: 1.2
    readonly property real hairlineAlpha: 0.08

    // -- Bar geometry -------------------------------------------------
    readonly property int barHeight:         Math.round(38 * scale)
    readonly property int barMargin:         Math.round(12 * spacingScale)
    readonly property int barMaxWidth:       880
    readonly property int barPadding:        Math.round(12 * spacingScale)
    readonly property int barSpacing:        Math.round(10 * spacingScale)
    readonly property int barWorkspaceSize:  Math.round(22 * scale)
    readonly property int barChipSize:       Math.round(28 * scale)
    readonly property int barTraySize:       Math.round(22 * scale)
    readonly property int barStatusSize:     8
    readonly property int barBatteryHeight:  16
    readonly property int barBatteryWidth:   36
    readonly property int barLogoSize:       22

    // -- Typography (Caelestia-style: GoogleSans + Caskaydia mono) ----
    // We expose the family as a string so the user can swap their own
    // fonts via set_value("font.family", ...). The Optima/Sans stack
    // here is the default on a fresh theme.
    property string fontFamily: "Inter, Sans-Serif"
    readonly property string monoFamily: "JetBrains Mono, Cascadia Mono, monospace"
    readonly property int fontXs:  Math.round(10 * fontScale)
    readonly property int fontSm:  Math.round(12 * fontScale)
    readonly property int fontMd:  Math.round(14 * fontScale)
    readonly property int fontLg:  Math.round(18 * fontScale)
    readonly property int fontXl:  Math.round(22 * fontScale)
}
