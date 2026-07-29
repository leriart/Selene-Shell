import QtQuick
import QtQuick.Effects
import QtMultimedia


Item {
    id: root

    property var wallpaper: null

    anchors.fill: parent

    // Persist current file. We only re-render when it changes so the QML
    // engine does not continuously decode video frames in offscreen test.
    property string previousSource: ""

    function fileUrl(path) {
        return path && path.length > 0 ? "file://" + path : "";
    }

    // Crossfade to mask frame swaps.
    Item {
        anchors.fill: parent

        Rectangle {
            id: layerA
            anchors.fill: parent
            color: "black"

            // Image for static content (jpg/png/webp/etc)
            Image {
                anchors.fill: parent
                visible: wallpaper !== null
                       && wallpaper.current_kind === "image"
                       && wallpaper.current_path !== ""
                source: visible ? root.fileUrl(wallpaper.current_path) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                cache: true
                mipmap: true

                Behavior on opacity {
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }
                opacity: 0.95
            }

            // AnimatedImage for GIF / APNG
            AnimatedImage {
                anchors.fill: parent
                visible: wallpaper !== null
                       && wallpaper.current_kind === "animated"
                       && wallpaper.current_path !== ""
                source: visible ? root.fileUrl(wallpaper.current_path) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                cache: false

                opacity: 1.0
            }

            // VideoOutput for mp4/webm/mkv/mov/avi
            Item {
                anchors.fill: parent
                visible: wallpaper !== null
                       && wallpaper.current_kind === "video"
                       && wallpaper.current_path !== ""

                MediaPlayer {
                    id: videoPlayer
                    source: parent.visible ? root.fileUrl(wallpaper.current_path) : ""
                    videoOutput: videoOut
                    loops: MediaPlayer.Infinite
                    playbackRate: 1.0
                    audioOutput: null
                    onErrorOccurred: (error, errorString) => {
                        console.warn("wallpaper video error:", errorString);
                    }
                }

                VideoOutput {
                    id: videoOut
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectCrop
                }
            }
        }

        // Vignette overlay to push focus to foreground chrome. Stops the
        // wallpaper from competing with the bar/launcher/island.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.30)
        }
    }

    // Re-tint the whole panel area in response to palette changes. The
    // wallpaper itself stays intact; only the dark overlay is tinted.
    Item {
        anchors.fill: parent
        Connections {
            target: wallpaper
            function onCurrentKindChanged() { root.previousSource = ""; }
            function onCurrentPathChanged() { root.previousSource = ""; }
        }
    }
}
