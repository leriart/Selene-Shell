import QtQuick

// MoonPulse.qml -- a pulse wave that expands outward from the centre.
//
// Used as a notification cue and a Game Mode / focus-mode transition
// hint: trigger `fire()` and three concentric rings grow from radius
// `startRadius` to `endRadius`, fading as they go. Cheap to animate
// (three Repeater-driven NumberAnimations on width / height / opacity,
// no Shape path).
Item {
    id: root

    // Origin (centre of the pulse).
    property real centerX: width / 2
    property real centerY: height / 2

    // Pulse geometry.
    property real startRadius: 16
    property real endRadius: 240
    property real strokeWidth: 2
    property color color: Tokens.accent
    property int  duration: 1400
    property int  stagger: 180

    property bool busy: false

    function fire() {
        if (busy) return;
        busy = true;
        for (let i = 0; i < waves.length; i++) {
            waves[i]._restart();
        }
        restartTimer.restart();
    }

    Timer {
        id: restartTimer
        interval: root.duration + root.stagger * (waves.length + 1)
        repeat: false
        onTriggered: root.busy = false
    }

    component Wave: Rectangle {
        id: waveRoot
        property real _startRadius: 16
        property real _endRadius: 240
        property int  _delay: 0
        property int  _duration: 1400
        readonly property real _size: _startRadius * 2

        radius: width / 2
        color: "transparent"
        border.color: root.color
        border.width: root.strokeWidth
        opacity: 0.0
        width: _size
        height: _size

        x: root.centerX - width / 2
        y: root.centerY - height / 2

        function _restart() {
            width = _startRadius * 2;
            height = _startRadius * 2;
            opacity = 0.0;
            _fadeIn.restart();
            _grow.restart();
        }

        Timer {
            id: _delayTimer
            interval: waveRoot._delay; repeat: false
            onTriggered: {
                waveRoot._fadeIn.restart();
                waveRoot._grow.restart();
            }
        }

        SequentialAnimation on opacity {
            id: _fadeIn
            running: false
            NumberAnimation { from: 0.0; to: 0.7; duration: 120 }
            NumberAnimation { from: 0.7; to: 0.0; duration: waveRoot._duration - 120 }
        }

        NumberAnimation on width {
            id: _grow
            running: false
            from: waveRoot._startRadius * 2
            to:   waveRoot._endRadius   * 2
            duration: waveRoot._duration
            easing.type: Easing.OutCubic
        }
        NumberAnimation on height {
            running: _grow.running
            from: waveRoot._startRadius * 2
            to:   waveRoot._endRadius   * 2
            duration: waveRoot._duration
            easing.type: Easing.OutCubic
        }

        Component.onCompleted: {
            _delayTimer.triggered.connect(function() {});
            _delayTimer.interval = _delay;
            // Auto-fire staggered waves on Component.onCompleted of the
            // parent via the parent's `fire()`.
            _delayTimer.start();
        }
    }

    // Three staggered waves.
    property var waves: [
        _wave1, _wave2, _wave3
    ]

    Wave { id: _wave1; _startRadius: root.startRadius; _endRadius: root.endRadius; _delay: 0;              _duration: root.duration }
    Wave { id: _wave2; _startRadius: root.startRadius; _endRadius: root.endRadius; _delay: root.stagger;   _duration: root.duration }
    Wave { id: _wave3; _startRadius: root.startRadius; _endRadius: root.endRadius; _delay: root.stagger*2; _duration: root.duration }
}
