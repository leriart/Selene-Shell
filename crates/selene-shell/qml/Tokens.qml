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

    // M3-style motion helpers (NothingLess `Anim.qml` port). Gated by
    // `animationsEnabled` so game mode / reduced-motion can zero every
    // duration in one write.
    property bool animationsEnabled: true

    // Animation profile -- Caelestia / NothingLess port. Switches the
    // cubic-bezier curves and per-tier durations the rest of the shell
    // uses via `animDuration()` / `animEasing()`. "off" collapses every
    // duration to 0 ms for users who want no motion at all.
    //
    //   m3      Material 3 expressive (default)
    //   subtle  tighter, faster, gentler curves
    //   bouncy  spring-like overshoot, for playful presets
    //   off     zero-duration (no transitions)
    property string animationProfile: "m3"

    function _profileTable() {
        switch (animationProfile) {
        case "subtle":
            return {
                standard:   { small: 100, medium: 160, large: 220 },
                emphasized: { small: 130, medium: 220, large: 280 },
                spatial:    { small: 180, medium: 260, large: 340 }
            };
        case "bouncy":
            return {
                standard:   { small: 180, medium: 320, large: 440 },
                emphasized: { small: 240, medium: 460, large: 580 },
                spatial:    { small: 320, medium: 480, large: 640 }
            };
        case "off":
            return {
                standard:   { small: 0, medium: 0, large: 0 },
                emphasized: { small: 0, medium: 0, large: 0 },
                spatial:    { small: 0, medium: 0, large: 0 }
            };
        case "m3":
        default:
            return {
                standard:   { small: 150, medium: 250, large: 350 },
                emphasized: { small: 200, medium: 400, large: 500 },
                spatial:    { small: 300, medium: 450, large: 600 }
            };
        }
    }

    // animDuration(type, size) -> ms.
    //   type: "standard" | "emphasized" | "spatial"
    //   size: "small" | "medium" | "large" (defaults to "medium")
    function animDuration(type, size) {
        if (!animationsEnabled || animationProfile === "off")
            return 0;
        const table = _profileTable();
        const row = table[type] || table["standard"];
        const ms = row[size] || row["medium"];
        return Math.round(ms * animScale);
    }

    // animEasing(type) -> cubic-bezier control points for
    // `easing.type: Easing.BezierSpline; easing.bezierCurve: ...`.
    // The "bouncy" profile swaps the standard curve for a spring-style
    // overshoot; "off" returns linear (irrelevant at zero duration).
    function animEasing(type) {
        if (animationProfile === "bouncy")
            return [0.34, 1.56, 0.64, 1.0, 1, 1];
        if (animationProfile === "subtle") {
            if (type === "emphasizedDecel")
                return [0.0, 0.0, 0.0, 1.0, 1, 1];
            return [0.2, 0.0, 0.2, 1.0, 1, 1];
        }
        switch (type) {
        case "emphasized":
            return [0.05, 0.7, 0.1, 1.0, 1, 1];
        case "emphasizedAccel":
            return [0.3, 0.0, 0.8, 0.15, 1, 1];
        case "emphasizedDecel":
            return [0.05, 0.7, 0.1, 1.0, 1, 1];
        case "spatial":
            return [0.27, 1.06, 0.18, 1.0, 1, 1];
        case "standardAccel":
            return [0.3, 0.0, 1.0, 1.0, 1, 1];
        case "standardDecel":
            return [0.0, 0.0, 0.0, 1.0, 1, 1];
        case "standard":
        default:
            return [0.2, 0.0, 0.0, 1.0, 1, 1];
        }
    }

// -- Theme colours (live-tunable by the palette engine) ------------
    // Ndot-style palette: monochrome surface with a single saturated
    // accent. The default theme is `monochrome-with-red-accent`,
    // which is the canonical NothingLess look -- backgrounds stay
    // pure monochrome and the red accent is reserved for state
    // changes (DND on, recording, focus mode) instead of being the
    // generic brand colour.
    property color bg:          "#0a0a0a"
    property color surface:     "#111111"
    property color surfaceAlt:  "#181818"
    property color border:      "#222222"
    property color borderStrong: "#333333"
    property color accent:      "#e74c3c"
    property color accentMuted: "#5a1f17"
    property color text:        "#f2f2f2"
    property color textMuted:   "#a0a0a0"
    property color textDim:     "#5a5a5a"
    property color success:     "#f2f2f2"
    property color danger:      "#e74c3c"

    Behavior on bg          { ColorAnimation { duration: durationSlower } }
    Behavior on surface     { ColorAnimation { duration: durationSlower } }
    Behavior on surfaceAlt  { ColorAnimation { duration: durationSlower } }
    Behavior on border      { ColorAnimation { duration: durationSlower } }
    Behavior on borderStrong { ColorAnimation { duration: durationSlower } }
    Behavior on accent      { ColorAnimation { duration: durationSlower } }
    Behavior on accentMuted { ColorAnimation { duration: durationSlower } }
    Behavior on text        { ColorAnimation { duration: durationSlower } }
    Behavior on textMuted   { ColorAnimation { duration: durationSlower } }
    Behavior on textDim     { ColorAnimation { duration: durationSlower } }
    Behavior on success     { ColorAnimation { duration: durationSlower } }
    Behavior on danger      { ColorAnimation { duration: durationSlower } }

    // -- Theme presets (NothingLess `PresetsService` port) ---------------
    // Each preset is a flat object with every token colour set; calling
    // `applyPreset(name)` writes every field, and the per-property
    // Behaviors above turn it into a smooth transition instead of a
    // hard swap. Unknown names fall through to "default".
    //
    // The lunar presets (New / Crescent / Quarter / Full) feed the
    // Selene "orbit" concept: the halo and orbit glow track the moon
    // phase metaphorically. The non-lunar presets are kept as utility
    // skins (Default, Sunset, Midnight, Monochrome).
    // Default preset on startup is `first-quarter` (Ndot's monochrome-
    // with-red-accent, half-lit moon): the red accent is visible on
    // the status indicators and moon halo from the very first paint,
    // while the chrome stays pure monochrome. Switch to `full-moon`
    // for the bright-red, fully-lit variant. The wallpaper-derived
    // accent extraction only kicks in when the user switches back to
    // `default`; everything else preserves the preset palette.
    property string themePreset: "first-quarter"

    // -- Orbital / lunar visual knobs (consumed by Orbit/Moon) --------
    // The halo radius and opacity around the central moon are preset-
    // driven so a "Full Moon" theme glows brighter than a "New Moon"
    // theme. These can also be overridden live from QML.
    property real moonHaloAlpha: 0.25
    property real moonRadiusScale: 1.0
    property real orbitAngularVelocity: 6.0   // deg/s, default slow drift
    property bool orbitsRotate: true
    property real orbitTraceAlpha: 0.18

    readonly property var _presets: ({
        // ── Ndot (canonical monochrome-with-red-accent) ───────────
        "default": {
            bg:           "#0a0a0a",
            surface:      "#111111",
            surfaceAlt:   "#181818",
            border:       "#222222",
            borderStrong: "#333333",
            accent:       "#e74c3c",
            accentMuted:  "#5a1f17",
            text:         "#f2f2f2",
            textMuted:    "#a0a0a0",
            textDim:      "#5a5a5a",
            success:      "#f2f2f2",
            danger:       "#e74c3c",
            haloAlpha:    0.20,
            moonScale:    1.0,
            orbitVel:     4.0,
            traceAlpha:   0.18
        },
        // ── Lunar cycle (Ndot "moon phase" theme family) ───────────
        "new-moon": {
            // Pure shadow: monochrome background goes near-black, the
            // moon glow is a faint silver rim around the central disc.
            bg:           "#020205",
            surface:      "#080808",
            surfaceAlt:   "#0e0e0e",
            border:       "#1a1a1a",
            borderStrong: "#262626",
            accent:       "#909090",
            accentMuted:  "#3a3a3a",
            text:         "#a8a8a8",
            textMuted:    "#707070",
            textDim:      "#3a3a3a",
            success:      "#909090",
            danger:       "#909090",
            haloAlpha:    0.10,
            moonScale:    1.0,
            orbitVel:     2.0,
            traceAlpha:   0.06
        },
        "waxing-crescent": {
            // Thin warm light begins to break the monochrome.
            bg:           "#080807",
            surface:      "#101010",
            surfaceAlt:   "#181816",
            border:       "#222220",
            borderStrong: "#333330",
            accent:       "#c45a48",
            accentMuted:  "#5a2017",
            text:         "#dadada",
            textMuted:    "#9a9a9a",
            textDim:      "#4a4a4a",
            success:      "#c4c4c4",
            danger:       "#c45a48",
            haloAlpha:    0.20,
            moonScale:    1.05,
            orbitVel:     3.5,
            traceAlpha:   0.14
        },
        "first-quarter": {
            // Half lit: the red accent deepens toward a saturated
            // scarlet; the chrome stays monochrome so the accent
            // reads as a clear state signal.
            bg:           "#0d0d0d",
            surface:      "#161616",
            surfaceAlt:   "#1f1f1f",
            border:       "#2a2a2a",
            borderStrong: "#3d3d3d",
            accent:       "#ff5a35",
            accentMuted:  "#6a2010",
            text:         "#fafafa",
            textMuted:    "#a8a8a8",
            textDim:      "#5a5a5a",
            success:      "#fafafa",
            danger:       "#ff5a35",
            haloAlpha:    0.32,
            moonScale:    1.15,
            orbitVel:     5.0,
            traceAlpha:   0.20
        },
        "full-moon": {
            // Bright monochrome with the red accent at full saturation
            // -- the most "alive" Ndot state.
            bg:           "#101010",
            surface:      "#1c1c1c",
            surfaceAlt:   "#262626",
            border:       "#333333",
            borderStrong: "#484848",
            accent:       "#ff6b4a",
            accentMuted:  "#7a2515",
            text:         "#ffffff",
            textMuted:    "#b0b0b0",
            textDim:      "#5a5a5a",
            success:      "#ffffff",
            danger:       "#ff6b4a",
            haloAlpha:    0.45,
            moonScale:    1.25,
            orbitVel:     8.0,
            traceAlpha:   0.30
        },
        // ── Utility presets (kept for power users) ─────────────────
        "sunset": {
            // A warm wash for evening sessions; the red accent is
            // desaturated to coral so it doesn't fight the background.
            bg:           "#1a0f15",
            surface:      "#2a1a1f",
            surfaceAlt:   "#3a2128",
            border:       "#4a2a32",
            borderStrong: "#5a3540",
            accent:       "#ff8a65",
            accentMuted:  "#5e2e1e",
            text:         "#fff0ea",
            textMuted:    "#c9a59c",
            textDim:      "#6e4a44",
            success:      "#a3d977",
            danger:       "#ff6b6b",
            haloAlpha:    0.25,
            moonScale:    1.05,
            orbitVel:     3.0,
            traceAlpha:   0.18
        },
        "midnight": {
            // Cool wash: blue accent over near-black surface; the
            // accent shifts away from the red so users can keep the
            // monochrome-with-blue-accent identity Ndot supports.
            bg:           "#050715",
            surface:      "#0c1024",
            surfaceAlt:   "#141a35",
            border:       "#1f274a",
            borderStrong: "#2d3868",
            accent:       "#7aa2ff",
            accentMuted:  "#1e2c5e",
            text:         "#dde6ff",
            textMuted:    "#8d9bbf",
            textDim:      "#3b4566",
            success:      "#7ee7c8",
            danger:       "#ff7aa2",
            haloAlpha:    0.30,
            moonScale:    1.1,
            orbitVel:     2.5,
            traceAlpha:   0.20
        },
        "monochrome": {
            // No accent: pure greyscale. Accent is set to a pale
            // neutral so it never reads as "active".
            bg:           "#0a0a0a",
            surface:      "#141414",
            surfaceAlt:   "#1c1c1c",
            border:       "#262626",
            borderStrong: "#3a3a3a",
            accent:       "#fafafa",
            accentMuted:  "#404040",
            text:         "#f0f0f0",
            textMuted:    "#a0a0a0",
            textDim:      "#5a5a5a",
            success:      "#d0d0d0",
            danger:       "#888888",
            haloAlpha:    0.15,
            moonScale:    1.0,
            orbitVel:     5.0,
            traceAlpha:   0.10
        }
    })

    function applyPreset(name) {
        const preset = root._presets[name];
        if (!preset) {
            console.warn("Tokens.applyPreset: unknown preset", name);
            return;
        }
        themePreset = name;
        bg           = preset.bg;
        surface      = preset.surface;
        surfaceAlt   = preset.surfaceAlt;
        border       = preset.border;
        borderStrong = preset.borderStrong;
        accent       = preset.accent;
        accentMuted  = preset.accentMuted;
        text         = preset.text;
        textMuted    = preset.textMuted;
        textDim      = preset.textDim;
        success      = preset.success;
        danger       = preset.danger;
        // Orbital / lunar knobs (defensive fallbacks for older configs).
        moonHaloAlpha       = preset.haloAlpha   !== undefined ? preset.haloAlpha   : 0.25;
        moonRadiusScale     = preset.moonScale   !== undefined ? preset.moonScale   : 1.0;
        orbitAngularVelocity = preset.orbitVel  !== undefined ? preset.orbitVel    : 6.0;
        orbitTraceAlpha     = preset.traceAlpha  !== undefined ? preset.traceAlpha  : 0.18;
    }

    // -- Backdrop glass ------------------------------------------------
    // Caelestia defaults to an opaque surface; we apply a 55% surface
    // over a MultiEffect blur of the wallpaper so the chrome reads
    // like frosted glass.
    readonly property real surfaceAlpha: 0.92
    readonly property real layerAlpha: 0.95
    readonly property real backdropBlur: 0.5
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
