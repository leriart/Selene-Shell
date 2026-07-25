import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    // Public surface
    function open() {
        input.text = "";
        visible = true;
        card.opacity = 1.0;
        card.scale = 1.0;
        input.forceActiveFocus();
    }
    function close() {
        card.opacity = 0.0;
        card.scale = 0.96;
        visible = false;
        input.text = "";
    }
    function toggle() {
        if (visible) close();
        else open();
    }

    visible: false
    color: Qt.rgba(0, 0, 0, 0.55)

    // Crisp scaling when the panel opens
    Behavior on opacity {
        NumberAnimation { duration: Tokens.durationFast }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    // Built-in actions (mock list, replaced by mlua/exec dispatch later).
    ListModel {
        id: actionModel
        ListElement { kind: "action"; label: "Lock screen"; exec: "loginctl lock-session" }
        ListElement { kind: "action"; label: "Suspend"; exec: "systemctl suspend" }
        ListElement { kind: "action"; label: "Reload shell"; exec: "selene reload" }
        ListElement { kind: "action"; label: "Quit shell"; exec: "selene quit" }
        ListElement { kind: "action"; label: "Open settings"; exec: "selene run toggle-settings" }
    }

    // Built-in app entries (placeholder; real impl enumerates .desktop files).
    ListModel {
        id: appModel
        ListElement { kind: "app"; label: "Terminal"; exec: "kitty" }
        ListElement { kind: "app"; label: "Files"; exec: "thunar" }
        ListElement { kind: "app"; label: "Browser"; exec: "firefox" }
        ListElement { kind: "app"; label: "Editor"; exec: "code" }
        ListElement { kind: "app"; label: "Music"; exec: "spotify" }
    }

    // Fuse apps + actions into a single source list.
    property var results: []
    function update() {
        const query = input.text.trim().toLowerCase();
        const isAction = query.startsWith(">");
        const isApp = query.startsWith("@");
        const needle = (isAction ? query.slice(1) :
                        isApp    ? query.slice(1) :
                        query).trim();

        const bag = (isAction || (!isApp && query.length > 0 && needle.length === 0))
                    ? actionModel : appModel;

        if (needle.length === 0 && !isAction) {
            results = [];
            return;
        }

        const out = [];
        for (let i = 0; i < bag.count; ++i) {
            const item = bag.get(i);
            if (needle.length === 0 || item.label.toLowerCase().indexOf(needle) !== -1) {
                out.push(item);
            }
            if (out.length >= 8) break;
        }
        results = out;
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(720, root.width * 0.72)
        height: Math.min(440, root.height * 0.55)
        radius: Tokens.radiusLg
        color: Tokens.surface
        border.color: Tokens.border
        border.width: 1

        opacity: 0
        scale: 0.96

        Behavior on opacity {
            NumberAnimation { duration: Tokens.duration; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Tokens.duration; easing.type: Easing.OutCubic }
        }

        TextField {
            id: input
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 56
            leftPadding: Tokens.spacingLg
            rightPadding: Tokens.spacingLg
            placeholderText: "search apps (@), actions (>), or just type"
            placeholderTextColor: Tokens.textMuted
            color: Tokens.text
            background: Rectangle {
                color: "transparent"
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Tokens.border
                }
            }
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontLg

            onTextChanged: root.update()

            Keys.onEscapePressed: root.close()
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) {
                    resultsView.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    resultsView.decrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (resultsView.count > 0) {
                        const item = results[resultsView.currentIndex];
                        if (item) launch(item);
                    }
                    event.accepted = true;
                }
            }
        }

        Label {
            id: hint
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 18
            anchors.rightMargin: Tokens.spacingLg
            text: input.text.length === 0 ? "@ app   > action   \u2191\u2193  \u23CE  esc"
                                          : (results.length + " matches")
            color: Tokens.textMuted
            font.family: Tokens.monoFamily
            font.pixelSize: Tokens.fontXs
        }

        ListView {
            id: resultsView
            model: results
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: input.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 1
            clip: true

            // Force re-evaluation when results change
            Connections {
                target: root
                function onResultsChanged() {
                    resultsView.currentIndex = 0;
                }
            }

            delegate: Item {
                width: ListView.view.width
                height: 52

                required property var modelData
                required property int index

                Rectangle {
                    anchors.fill: parent
                    color: index === resultsView.currentIndex
                           ? Qt.darker(Tokens.accent, 4.5)
                           : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Tokens.durationFast }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Qt.darker(Tokens.border, 1.2)
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacingLg
                    anchors.rightMargin: Tokens.spacingLg
                    spacing: Tokens.spacingMd

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 6
                        color: Qt.darker(Tokens.accent, 3.0)
                        Label {
                            anchors.centerIn: parent
                            text: modelData.kind === "app" ? "@" : ">"
                            color: Tokens.accent
                            font.family: Tokens.monoFamily
                            font.pixelSize: Tokens.fontMd
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: Tokens.text
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontMd
                        elide: Text.ElideRight
                    }

                    Label {
                        text: modelData.exec
                        color: Tokens.textDim
                        font.family: Tokens.monoFamily
                        font.pixelSize: Tokens.fontXs
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: resultsView.currentIndex = index
                    onClicked: launch(modelData)
                }
            }

            Label {
                anchors.centerIn: parent
                visible: results.length === 0
                text: input.text.length === 0
                      ? "type to search"
                      : "no matches"
                color: Tokens.textDim
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
            }
        }
    }

    function launch(item) {
        if (!item) return;
        console.log("selene-launcher: would exec", item.exec, "(kind=" + item.kind + ")");
        // Real impl: forward through a Rust spawn helper that handles D-Bus
        // activation, .desktop file resolution and detached processes.
        root.close();
    }
}
