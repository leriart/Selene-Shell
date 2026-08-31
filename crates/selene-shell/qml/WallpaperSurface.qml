import QtQuick
import QtQuick.Effects
import QtMultimedia


// Native wallpaper engine surface (port of NothingLess's wallpaper + 
// visualizer concept, adapted for cxx-qt/Qt). Two stacked layers
// (layerA / layerB) crossfade between previous and current wallpaper so
// the GPU isn't asked to decode two sources simultaneously. The
// `WallpaperEngine` QObject owns hardware-accelerated decode, an
// on-disk downscale cache, and a pause mask that suppresses video
// decoding while the screen is locked or game mode is active.
Item {
    id: root

    // Backend references, injected by Main.qml.
    property var wallpaper: null       // gallery + current path
    property var wallpaperEngine: null // decode / cache / pause

    anchors.fill: parent

    function fileUrl(path) {
        return path && path.length > 0 ? "file://" + path : "";
    }

    // ─── Engine → effective path resolver ───────────────────────────────
    // For videos the engine writes a downscaled cache copy; for static
    // images we hand the original straight to Image.
    readonly property string _resolvedPath: {
        if (!wallpaperEngine || !wallpaper)
            return "";
        if (wallpaper.current_kind === "video")
            return wallpaperEngine.effective_path && wallpaperEngine.effective_path.length > 0
                ? wallpaperEngine.effective_path
                : wallpaper.current_path;
        return wallpaper.current_path;
    }

    readonly property string _resolvedKind: wallpaper
        ? wallpaper.current_kind : ""

    // The engine pauses decode on lock/game mode. We mirror that on
    // the MediaPlayer so the compositor stops wasting GPU cycles.
    readonly property bool _paused:
        wallpaperEngine && wallpaperEngine.video
            ? wallpaperEngine.paused
            : false

    // ─── Two-layer crossfade ─────────────────────────────────────────────
    // Each layer holds one frame of wallpaper history. On a wallpaper
    // change the previous image stays visible while the next fades in,
    // and the QQuickImageProvider keeps the prior decoded pixmap in the
    // Qt cache so the back layer isn't reloaded from disk.
    Item {
        id: stack
        anchors.fill: parent

        // Layer A — current (front).
        Rectangle {
            id: layerA
            anchors.fill: parent
            color: "black"
            visible: opacity > 0.001

            // Static images.
            Image {
                id: imgA
                anchors.fill: parent
                visible: root._resolvedKind === "image"
                         && root._resolvedPath.length > 0
                source: visible ? root.fileUrl(root._resolvedPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                cache: true
                mipmap: true
                opacity: 1.0

                // Crossfade the front layer in only once the new
                // pixmap is fully decoded -- no blank flash during
                // the fade (the old frame stays visible until Ready).
                onStatusChanged: {
                    if (status === Image.Ready) {
                        layerA.opacity = 1.0;
                        layerB.opacity = 0.0;
                    }
                }
            }

            // Animated (gif/apng).
            AnimatedImage {
                id: animA
                anchors.fill: parent
                visible: root._resolvedKind === "animated"
                         && root._resolvedPath.length > 0
                source: visible ? root.fileUrl(root._resolvedPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                cache: false
            }

            // Video (mp4/webm/mkv/...) — engine owned.
            Item {
                id: videoA
                anchors.fill: parent
                visible: root._resolvedKind === "video"
                         && root._resolvedPath.length > 0

                MediaPlayer {
                    id: videoPlayerA
                    source: parent.visible ? root.fileUrl(root._resolvedPath) : ""
                    videoOutput: videoOutA
                    loops: MediaPlayer.Infinite
                    playbackRate: 1.0
                    audioOutput: null
                    onErrorOccurred: (error, errorString) => {
                        console.warn("wallpaper video error:", errorString);
                    }
                }

                VideoOutput {
                    id: videoOutA
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                }
            }

            Behavior on opacity {
                enabled: Tokens.animationsEnabled
                NumberAnimation {
                    duration: Tokens.animDuration("standard", "medium")
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Tokens.animEasing("emphasized")
                }
            }
        }

        // Layer B — previous frame, holds the prior wallpaper so the
        // front layer can crossfade over it. `source`/`kind` are bound
        // to the *previous* path at all times (never assigned at swap
        // time), so the back layer's Image has already decoded the old
        // wallpaper when the crossfade starts -- no blank flash.
        Rectangle {
            id: layerB
            anchors.fill: parent
            color: "black"
            visible: opacity > 0.001
            opacity: 0.0

            readonly property string source: root._previousPath
            readonly property string kind: root._previousKind

            Image {
                anchors.fill: parent
                source: layerB.source.length > 0 ? "file://" + layerB.source : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                cache: true
                mipmap: true
                visible: layerB.kind === "image" || layerB.kind === "animated"
            }
            AnimatedImage {
                anchors.fill: parent
                source: layerB.source.length > 0 ? "file://" + layerB.source : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                cache: false
                visible: layerB.kind === "animated"
            }
            VideoOutput {
                id: videoOutB
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                visible: layerB.kind === "video" && layerB.source.length > 0
            }
        }
    }

    // ─── Engine pause wiring ─────────────────────────────────────────────
    // WallpaperEngine owns a paused flag + paused_reason string. The
    // MediaPlayer reacts to _paused; for static images it has no
    // effect (still cached), for videos it stops decode entirely.
    Connections {
        target: wallpaperEngine
        function onPausedChanged() {
            if (!wallpaperEngine || !wallpaperEngine.video)
                return;
            if (videoPlayerA.source.toString().length === 0)
                return;
            if (wallpaperEngine.paused)
                videoPlayerA.pause();
            else
                videoPlayerA.play();
        }
        function onEffectivePathChanged() {
            if (root._resolvedKind !== "video") return;
            const src = root.fileUrl(root._resolvedPath);
            if (videoPlayerA.source.toString() !== src)
                videoPlayerA.source = src;
            if (!wallpaperEngine.paused)
                videoPlayerA.play();
        }
    }

    // ─── Path change → crossfade ─────────────────────────────────────────
    // On every wallpaper swap we move the front-layer's content into
    // the back layer (snapshot) and load the new source on the front.
    // Image / AnimatedImage cache keep the prior decoded pixmap hot so
    // the back layer is cheap to draw.
    property string _previousPath: ""
    property string _previousKind: ""

    function _swapLayers() {
        if (_resolvedPath === _previousPath) return;
        // Record the new previous BEFORE mutating the front layer so
        // layerB's bindings re-evaluate to the old source, then fade.
        const oldPath = _previousPath;
        const oldKind = _previousKind;
        _previousPath = _resolvedPath;
        _previousKind = _resolvedKind;
        layerB.opacity = 1.0;
        layerA.opacity = 0.0;
        crossfadeTimer.restart();
    }

    Connections {
        target: wallpaper
        function onCurrentPathChanged() { root._swapLayers(); }
        function onCurrentKindChanged() { root._swapLayers(); }
    }

    Connections {
        target: wallpaperEngine
        function onEffectivePathChanged() { root._swapLayers(); }
    }

    Timer {
        id: crossfadeTimer
        interval: Tokens.animDuration("standard", "medium")
        repeat: false
        onTriggered: {
            // Animated/video crossfade fallback: the front layer is
            // considered "ready" when the source resolved; static
            // images already fade in via imgA.onStatusChanged.
            layerB.opacity = 0.0;
            layerA.opacity = 1.0;
        }
    }

    Component.onCompleted: {
        _previousPath = _resolvedPath;
        _previousKind = _resolvedKind;
        layerA.opacity = 1.0;
        if (root._resolvedKind === "video" && wallpaperEngine
            && !wallpaperEngine.paused) {
            videoPlayerA.play();
        }
    }

    // ─── Vignette overlay ────────────────────────────────────────────────
    // Tones down the wallpaper so foreground chrome reads cleanly.
    // Kept outside the crossfade so the dark layer is always present.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.30)
        z: 1
    }
}
